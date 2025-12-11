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

// MARK: - FFmpeg Service

class FFmpegService: ObservableObject {
    private var currentProcess: Process?
    private var isCancelled = false
    
    /// Path to FFmpeg binary - tries Homebrew locations
    private var ffmpegPath: String {
        // Common Homebrew locations
        let paths = [
            "/opt/homebrew/bin/ffmpeg",  // Apple Silicon
            "/usr/local/bin/ffmpeg",      // Intel
            "/usr/bin/ffmpeg"             // System
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Fallback to PATH
        return "ffmpeg"
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
        FileManager.default.fileExists(atPath: ffmpegPath) || {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["ffmpeg"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }()
    }
    
    /// Get FFmpeg version
    func getVersion() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
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
        onProgress: @escaping (ConversionProgress) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = command.fullArguments
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        currentProcess = process
        
        // Progress parsing state
        var currentProgress = ConversionProgress(
            currentTime: 0,
            percentage: 0,
            speed: 0,
            frame: 0,
            fps: 0,
            bitrate: "N/A",
            size: 0
        )
        
        // Handle stdout (progress output)
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard self?.isCancelled != true else { return }
            
            let data = handle.availableData
            guard !data.isEmpty,
                  let output = String(data: data, encoding: .utf8) else { return }
            
            // Parse progress key=value pairs
            for line in output.components(separatedBy: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                
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
                        onProgress(currentProgress)
                    }
                default:
                    break
                }
            }
        }
        
        // Capture stderr for error messages with thread-safe access
        let stderrQueue = DispatchQueue(label: "com.convertify.stderr")
        var stderrOutput = ""
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8) {
                stderrQueue.sync {
                    stderrOutput += output
                }
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
        
        // Synchronize to ensure any in-progress handler has completed
        let finalStderrOutput = stderrQueue.sync { stderrOutput }
        
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

