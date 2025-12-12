//
//  FFmpegService.swift
//  Convertify
//
//  FFmpegKit-based transcoding service for App Store distribution
//

import Foundation
import Combine

// MARK: - FFmpeg Command

struct FFmpegCommand {
    let inputPath: String
    let outputPath: String
    let preInputArguments: [String] // Kept for API compatibility
    let arguments: [String]
    
    // New: Convert to TranscodingConfig
    func toTranscodingConfig(format: String) -> TranscodingConfig {
        var config = TranscodingConfig(
            inputPath: inputPath,
            outputPath: outputPath,
            outputFormat: format
        )
        
        // Parse arguments to extract settings
        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            
            switch arg {
            case "-c:v":
                if i + 1 < arguments.count {
                    config.videoCodec = arguments[i + 1]
                    i += 1
                }
            case "-c:a":
                if i + 1 < arguments.count {
                    let codec = arguments[i + 1]
                    if codec == "copy" {
                        config.copyAudio = true
                    } else {
                        config.audioCodec = codec
                    }
                    i += 1
                }
            case "-b:v":
                if i + 1 < arguments.count {
                    let bitrateStr = arguments[i + 1].replacingOccurrences(of: "k", with: "000")
                    config.videoBitrate = Int64(bitrateStr)
                    i += 1
                }
            case "-b:a":
                if i + 1 < arguments.count {
                    let bitrateStr = arguments[i + 1].replacingOccurrences(of: "k", with: "000")
                    config.audioBitrate = Int64(bitrateStr)
                    i += 1
                }
            case "-crf":
                if i + 1 < arguments.count {
                    config.videoCRF = Int(arguments[i + 1])
                    i += 1
                }
            case "-vn":
                config.stripVideo = true
            case "-an":
                config.stripAudio = true
            case "-t":
                if i + 1 < arguments.count {
                    config.endTime = parseTimeString(arguments[i + 1])
                    i += 1
                }
            case "-vf":
                if i + 1 < arguments.count {
                    config.videoFilters = [arguments[i + 1]]
                    i += 1
                }
            case "-ar":
                if i + 1 < arguments.count {
                    config.sampleRate = Int32(arguments[i + 1])
                    i += 1
                }
            case "-ac":
                if i + 1 < arguments.count {
                    config.audioChannels = Int32(arguments[i + 1])
                    i += 1
                }
            default:
                break
            }
            i += 1
        }
        
        // Parse pre-input arguments for start time
        for j in 0..<preInputArguments.count {
            if preInputArguments[j] == "-ss" && j + 1 < preInputArguments.count {
                config.startTime = parseTimeString(preInputArguments[j + 1])
            }
        }
        
        return config
    }
    
    private func parseTimeString(_ str: String) -> Double {
        // Format: HH:MM:SS.mmm or just seconds
        if str.contains(":") {
            let parts = str.split(separator: ":")
            if parts.count == 3 {
                let hours = Double(parts[0]) ?? 0
                let minutes = Double(parts[1]) ?? 0
                let seconds = Double(parts[2]) ?? 0
                return hours * 3600 + minutes * 60 + seconds
            }
        }
        return Double(str) ?? 0
    }
    
    var fullArguments: [String] {
        var args = ["-y"]
        args += preInputArguments
        args += ["-i", inputPath]
        args += arguments
        args += ["-progress", "pipe:1"]
        args += ["-stats_period", "0.5"]
        args += [outputPath]
        return args
    }
}

// MARK: - Progress Info

struct ConversionProgress {
    var currentTime: TimeInterval = 0
    var percentage: Double = 0
    var speed: Double = 0
    var frame: Int = 0
    var fps: Double = 0
    var bitrate: String = "N/A"
    var size: Int64 = 0
}

// MARK: - FFmpeg Service

@MainActor
class FFmpegService: ObservableObject {
    private var currentPipeline: TranscodingPipeline?
    private var currentGifTranscoder: GifTranscoder?
    private var isCancelled = false
    
    /// Execute FFmpeg command and yield progress updates
    func execute(command: FFmpegCommand, duration: TimeInterval) -> AsyncThrowingStream<ConversionProgress, Error> {
        isCancelled = false
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.runTranscoding(command: command, duration: duration) { progress in
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
        currentPipeline?.cancel()
        currentGifTranscoder?.cancel()
        currentPipeline = nil
        currentGifTranscoder = nil
    }
    
    /// Check if FFmpeg is available (always true with bundled FFmpegKit)
    func isAvailable() -> Bool {
        return true
    }
    
    /// Get FFmpeg version
    func getVersion() -> String? {
        // Return version from bundled FFmpegKit
        return "FFmpegKit 6.1 (bundled)"
    }
    
    // MARK: - Private Methods
    
    private func runTranscoding(
        command: FFmpegCommand,
        duration: TimeInterval,
        onProgress: @escaping (ConversionProgress) -> Void
    ) async throws {
        let outputExt = (command.outputPath as NSString).pathExtension.lowercased()
        
        // Determine the type of transcoding
        if outputExt == "gif" {
            try await runGifTranscoding(command: command, duration: duration, onProgress: onProgress)
        } else if isImageFormat(outputExt) && isImageInput(command.inputPath) {
            try await runImageTranscoding(command: command, onProgress: onProgress)
        } else {
            try await runVideoAudioTranscoding(command: command, duration: duration, onProgress: onProgress)
        }
    }
    
    private func runVideoAudioTranscoding(
        command: FFmpegCommand,
        duration: TimeInterval,
        onProgress: @escaping (ConversionProgress) -> Void
    ) async throws {
        let outputExt = (command.outputPath as NSString).pathExtension.lowercased()
        var config = command.toTranscodingConfig(format: outputExt)
        
        // Select hardware encoder if available
        if config.videoCodec == nil || config.videoCodec == "libx264" {
            let (encoder, isHardware) = EncoderSelector.selectEncoder(for: outputExt, preferHardware: true)
            if isHardware {
                config.videoCodec = encoder
            }
        }
        
        let pipeline = TranscodingPipeline(config: config)
        currentPipeline = pipeline
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try pipeline.transcode { transcodingProgress in
                        let progress = ConversionProgress(
                            currentTime: transcodingProgress.currentTime,
                            percentage: transcodingProgress.percentage,
                            speed: transcodingProgress.speed,
                            frame: transcodingProgress.frame,
                            fps: transcodingProgress.fps,
                            bitrate: "\(transcodingProgress.bitrate / 1000)k",
                            size: transcodingProgress.size
                        )
                        DispatchQueue.main.async {
                            onProgress(progress)
                        }
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
        currentPipeline = nil
    }
    
    private func runGifTranscoding(
        command: FFmpegCommand,
        duration: TimeInterval,
        onProgress: @escaping (ConversionProgress) -> Void
    ) async throws {
        // Parse GIF settings from arguments
        var fps = 15
        var width = 480
        var startTime: Double? = nil
        var endTime: Double? = nil
        
        // Parse from video filters
        for arg in command.arguments {
            if arg.contains("fps=") {
                if let match = arg.range(of: "fps=(\\d+)", options: .regularExpression) {
                    let fpsStr = String(arg[match]).replacingOccurrences(of: "fps=", with: "")
                    fps = Int(fpsStr) ?? 15
                }
            }
            if arg.contains("scale=") {
                if let match = arg.range(of: "scale=(\\d+)", options: .regularExpression) {
                    let widthStr = String(arg[match]).replacingOccurrences(of: "scale=", with: "")
                    width = Int(widthStr) ?? 480
                }
            }
        }
        
        // Parse start/end time from pre-input args
        for i in 0..<command.preInputArguments.count {
            if command.preInputArguments[i] == "-ss" && i + 1 < command.preInputArguments.count {
                startTime = parseTimeString(command.preInputArguments[i + 1])
            }
        }
        
        for i in 0..<command.arguments.count {
            if command.arguments[i] == "-t" && i + 1 < command.arguments.count {
                let durationVal = parseTimeString(command.arguments[i + 1])
                if let start = startTime {
                    endTime = start + durationVal
                } else {
                    endTime = durationVal
                }
            }
        }
        
        let transcoder = GifTranscoder(
            inputPath: command.inputPath,
            outputPath: command.outputPath,
            fps: fps,
            width: width,
            startTime: startTime,
            endTime: endTime
        )
        currentGifTranscoder = transcoder
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try transcoder.transcode { transcodingProgress in
                        let progress = ConversionProgress(
                            currentTime: transcodingProgress.currentTime,
                            percentage: transcodingProgress.percentage,
                            speed: transcodingProgress.speed,
                            frame: transcodingProgress.frame,
                            fps: transcodingProgress.fps,
                            bitrate: "N/A",
                            size: 0
                        )
                        DispatchQueue.main.async {
                            onProgress(progress)
                        }
                    }
                    continuation.resume()
            } catch {
                continuation.resume(throwing: error)
                }
            }
        }
        
        currentGifTranscoder = nil
    }
    
    private func runImageTranscoding(
        command: FFmpegCommand,
        onProgress: @escaping (ConversionProgress) -> Void
    ) async throws {
        // Parse quality from arguments
        var quality = 90
        var width: Int? = nil
        var height: Int? = nil
        
        for i in 0..<command.arguments.count {
            let arg = command.arguments[i]
            if arg == "-q:v" && i + 1 < command.arguments.count {
                // JPEG quality is inverse (2-31, lower is better)
                let q = Int(command.arguments[i + 1]) ?? 5
                quality = 100 - (q * 100 / 31)
            }
            if arg == "-quality" && i + 1 < command.arguments.count {
                // WebP quality (0-100)
                quality = Int(command.arguments[i + 1]) ?? 90
            }
        }
        
        // Parse scale filter for dimensions
        for arg in command.arguments {
            if arg.contains("scale=") {
                let parts = arg.replacingOccurrences(of: "scale=", with: "").split(separator: ":")
                if parts.count >= 2 {
                    width = Int(parts[0])
                    height = Int(parts[1])
                }
            }
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try ImageTranscoder.convert(
                        inputPath: command.inputPath,
                        outputPath: command.outputPath,
                        width: width,
                        height: height,
                        quality: quality
                    )
                    
                    // Report completion
                    let progress = ConversionProgress(
                        currentTime: 1,
                        percentage: 1.0,
                        speed: 1,
                        frame: 1,
                        fps: 1,
                        bitrate: "N/A",
                        size: 0
                    )
                    DispatchQueue.main.async {
                        onProgress(progress)
                    }
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func parseTimeString(_ str: String) -> Double {
        if str.contains(":") {
            let parts = str.split(separator: ":")
            if parts.count == 3 {
                let hours = Double(parts[0]) ?? 0
                let minutes = Double(parts[1]) ?? 0
                let seconds = Double(parts[2]) ?? 0
                return hours * 3600 + minutes * 60 + seconds
            }
        }
        return Double(str) ?? 0
    }
    
    private func isImageFormat(_ ext: String) -> Bool {
        return ["jpg", "jpeg", "png", "webp", "bmp", "tiff", "tif", "heic", "ico"].contains(ext)
    }
    
    private func isImageInput(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return isImageFormat(ext)
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
            return "FFmpeg is not available"
        case .conversionFailed(let message):
            return message
        case .cancelled:
            return "Conversion was cancelled"
        case .invalidInput:
            return "Invalid input file"
        }
    }
}
