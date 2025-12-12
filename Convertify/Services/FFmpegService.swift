//
//  FFmpegService.swift
//  Convertify
//
//  Handles FFmpeg process execution and progress monitoring
//

import Foundation
import Combine

// MARK: - FFmpeg Command

struct FFmpegCommand {
    let inputPath: String
    let outputPath: String
    let preInputArguments: [String] // Arguments that must appear before -i (e.g., -hwaccel)
    let arguments: [String]
    
    var fullArguments: [String] {
        var args = ["-y"] // Overwrite output
        args += preInputArguments // Hardware acceleration must come before -i
        args += ["-i", inputPath]
        args += arguments
        args += ["-progress", "pipe:1"] // Progress to stdout
        args += ["-stats_period", "0.5"] // Update every 0.5s
        args += [outputPath]
        return args
    }
}

// MARK: - Progress Info

struct ConversionProgress {
    var currentTime: TimeInterval
    var percentage: Double
    var speed: Double
    var frame: Int
    var fps: Double
    var bitrate: String
    var size: Int64
}

// MARK: - Thread-safe helpers (Swift 6 SendableClosureCaptures)

private final class LockedString: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String = ""

    func append(_ chunk: String) {
        lock.lock()
        value += chunk
        lock.unlock()
    }

    func snapshot() -> String {
        lock.lock()
        let out = value
        lock.unlock()
        return out
    }
}

private final class ReadGate: @unchecked Sendable {
    private let lock = NSLock()

    func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class FFmpegProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private let duration: TimeInterval
    private let onProgress: @Sendable (ConversionProgress) -> Void

    private var buffer: String = ""
    private var currentProgress = ConversionProgress(
        currentTime: 0,
        percentage: 0,
        speed: 0,
        frame: 0,
        fps: 0,
        bitrate: "N/A",
        size: 0
    )

    init(duration: TimeInterval, onProgress: @Sendable @escaping (ConversionProgress) -> Void) {
        self.duration = duration
        self.onProgress = onProgress
    }

    func consume(_ chunk: String) {
        // Collect snapshots to emit outside the lock
        var snapshots: [ConversionProgress] = []

        lock.lock()
        buffer += chunk

        // Split into lines while preserving a possible partial last line.
        let endsWithNewline = buffer.hasSuffix("\n")
        let parts = buffer.split(separator: "\n", omittingEmptySubsequences: false)

        let linesToProcess: ArraySlice<Substring>
        if endsWithNewline {
            linesToProcess = parts[...]
            buffer = ""
        } else {
            linesToProcess = parts.dropLast()
            buffer = String(parts.last ?? "")
        }

        for rawLine in linesToProcess {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let kv = line.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }

            let key = kv[0].trimmingCharacters(in: .whitespaces)
            let value = kv[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "frame":
                currentProgress.frame = Int(value) ?? 0
            case "fps":
                currentProgress.fps = Double(value) ?? 0
            case "bitrate":
                currentProgress.bitrate = value
            case "total_size":
                currentProgress.size = Int64(value) ?? 0
            case "out_time_us":
                if let microseconds = Double(value) {
                    currentProgress.currentTime = microseconds / 1_000_000
                    if duration > 0 {
                        currentProgress.percentage = min(currentProgress.currentTime / duration, 1.0)
                    }
                }
            case "speed":
                // Speed is like "1.5x" or "N/A"
                let speedStr = value.replacingOccurrences(of: "x", with: "")
                currentProgress.speed = Double(speedStr) ?? 0
            case "progress":
                if value == "continue" || value == "end" {
                    snapshots.append(currentProgress)
                }
            default:
                break
            }
        }

        lock.unlock()

        // Emit outside the lock to avoid blocking the pipe thread.
        for snapshot in snapshots {
            onProgress(snapshot)
        }
    }

    func flushRemainder() {
        lock.lock()
        let remainder = buffer
        buffer = ""
        lock.unlock()

        guard !remainder.isEmpty else { return }
        // Treat the remainder as a complete line.
        consume(remainder + "\n")
    }
}

// MARK: - FFmpeg Service

@MainActor
class FFmpegService: ObservableObject {
    private var currentProcess: Process?
    private var isCancelled = false
    
    private var ffmpegExecutableURL: URL? {
        ExecutableLocator.resolveExecutableURL(
            named: "ffmpeg",
            preferredAbsolutePaths: [
                "/opt/homebrew/bin/ffmpeg",   // Apple Silicon Homebrew
                "/usr/local/bin/ffmpeg",      // Intel Homebrew
                "/usr/bin/ffmpeg"             // System (rarely present)
            ]
        )
    }
    
    /// Execute FFmpeg command and yield progress updates
    func execute(command: FFmpegCommand, duration: TimeInterval) -> AsyncThrowingStream<ConversionProgress, Error> {
        isCancelled = false
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.runProcess(command: command, duration: duration) { progress in
                        continuation.yield(progress)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Cancel the current conversion
    func cancel() {
        isCancelled = true
        currentProcess?.terminate()
        currentProcess = nil
    }
    
    /// Check if FFmpeg is available
    func isAvailable() -> Bool {
        ffmpegExecutableURL != nil
    }
    
    /// Get FFmpeg version
    func getVersion() -> String? {
        guard let ffmpegExecutableURL else { return nil }

        let process = Process()
        process.executableURL = ffmpegExecutableURL
        process.arguments = ["-version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            
            // Extract version from first line
            if let firstLine = output.components(separatedBy: "\n").first {
                return firstLine
            }
            return nil
        } catch {
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func runProcess(
        command: FFmpegCommand,
        duration: TimeInterval,
        onProgress: @Sendable @escaping (ConversionProgress) -> Void
    ) async throws {
        guard let ffmpegExecutableURL else {
            throw FFmpegError.notFound
        }

        let process = Process()
        process.executableURL = ffmpegExecutableURL
        process.arguments = command.fullArguments
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        currentProcess = process
        
        let progressParser = FFmpegProgressParser(duration: duration, onProgress: onProgress)
        let stderrCollector = LockedString()
        let stdoutReadGate = ReadGate()
        let stderrReadGate = ReadGate()
        
        // Handle stdout (progress output)
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            stdoutReadGate.withLock {
                let data = handle.availableData
                guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
                progressParser.consume(output)
            }
        }
        
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderrReadGate.withLock {
                let data = handle.availableData
                guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
                stderrCollector.append(output)
            }
        }
        
        // Wait for completion - set terminationHandler before run() to avoid race condition
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                continuation.resume()
            }
            
            do {
                try process.run()
            } catch {
                // Clear the termination handler before resuming to prevent potential double-resume
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        
        // Clean up handlers
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        // Flush any remaining buffered output after handlers are removed.
        let remainingStdout = stdoutReadGate.withLock {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        if let remainingOutStr = String(data: remainingStdout, encoding: .utf8), !remainingOutStr.isEmpty {
            progressParser.consume(remainingOutStr)
        }
        progressParser.flushRemainder()

        let remainingStderr = stderrReadGate.withLock {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }
        if let remainingErrStr = String(data: remainingStderr, encoding: .utf8), !remainingErrStr.isEmpty {
            stderrCollector.append(remainingErrStr)
        }

        let finalStderrOutput = stderrCollector.snapshot()

        stdoutPipe.fileHandleForReading.closeFile()
        stderrPipe.fileHandleForReading.closeFile()
        
        currentProcess = nil
        
        // Check exit status
        if isCancelled {
            throw FFmpegError.cancelled
        }
        
        if process.terminationStatus != 0 {
            throw FFmpegError.conversionFailed(finalStderrOutput)
        }
    }
}

// MARK: - Errors

enum FFmpegError: LocalizedError {
    case notFound
    case conversionFailed(String)
    case cancelled
    case invalidInput
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "FFmpeg not found. Please install it via Homebrew: brew install ffmpeg"
        case .conversionFailed(let message):
            // Extract the most relevant error message
            let lines = message.components(separatedBy: "\n")
            if let errorLine = lines.last(where: { $0.contains("Error") || $0.contains("error") }) {
                return errorLine.trimmingCharacters(in: .whitespaces)
            }
            return "Conversion failed"
        case .cancelled:
            return "Conversion was cancelled"
        case .invalidInput:
            return "Invalid input file"
        }
    }
}

