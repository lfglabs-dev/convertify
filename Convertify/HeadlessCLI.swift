//
//  HeadlessCLI.swift
//  Convertify
//
//  Headless/CLI mode for debugging conversion pipelines without UI.
//

import Foundation

enum HeadlessCLI {
    enum Tool: String {
        case convert
        case trim
        case compress
        case extractAudio = "extract-audio"
        case gif = "gif"
        case all

        init?(cliValue: String) {
            let v = cliValue.lowercased()
            switch v {
            case "convert": self = .convert
            case "trim", "trim&cut", "trim-cut", "trim_and_cut": self = .trim
            case "compress": self = .compress
            case "extract-audio", "extractaudio", "extract_audio", "audio": self = .extractAudio
            case "gif", "makegif", "make-gif": self = .gif
            case "all": self = .all
            default: return nil
            }
        }
    }

    struct Options {
        var tool: Tool = .all
        var inputPath: String = ""
        var outputPath: String?
        var format: String?
        var quality: QualityPreset = .balanced

        // Trim
        var startSeconds: Double?
        var endSeconds: Double?

        // Compress
        var targetSizeMB: Double?
        var videoBitrateKbps: Int?
        
        // GIF
        var gifFps: Int = 15
        var gifWidth: Int = 480

        // Flags
        var dryRun: Bool = false
        var verbose: Bool = false
    }

    static func run(args: [String]) {
        var options = Options()

        // Parse args
        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--input" where i + 1 < args.count:
                options.inputPath = args[i + 1]
                i += 1
            case "--output" where i + 1 < args.count:
                options.outputPath = args[i + 1]
                i += 1
            case "--tool" where i + 1 < args.count:
                if let t = Tool(cliValue: args[i + 1]) {
                    options.tool = t
                }
                i += 1
            case "--format" where i + 1 < args.count:
                options.format = args[i + 1].lowercased()
                i += 1
            case "--quality" where i + 1 < args.count:
                let q = args[i + 1].lowercased()
                switch q {
                case "fast": options.quality = .fast
                case "balanced": options.quality = .balanced
                case "quality", "best": options.quality = .quality
                default: break
                }
                i += 1
            case "--start" where i + 1 < args.count:
                options.startSeconds = Double(args[i + 1])
                i += 1
            case "--end" where i + 1 < args.count:
                options.endSeconds = Double(args[i + 1])
                i += 1
            case "--target-mb" where i + 1 < args.count:
                options.targetSizeMB = Double(args[i + 1])
                i += 1
            case "--video-bitrate-kbps" where i + 1 < args.count:
                options.videoBitrateKbps = Int(args[i + 1])
                i += 1
            case "--dry-run":
                options.dryRun = true
            case "--verbose":
                options.verbose = true
            default:
                break
            }

            i += 1
        }

        guard !options.inputPath.isEmpty else {
            printUsageAndExit()
        }

        ConvertifyDiagnostics.enabled = options.verbose || args.contains("--debug") || args.contains("--headless") || args.contains("--cli")

        let inputURL = URL(fileURLWithPath: options.inputPath)
        debugLog("=== Convertify Headless Mode ===")
        debugLog("Args: \(args.joined(separator: " "))")
        debugLog("Tool: \(options.tool.rawValue)")
        debugLog("Input: \(inputURL.path)")
        debugLog("Quality: \(options.quality.rawValue)")

        // Run synchronously (but uses async internals) so the app can exit cleanly.
        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 0

        Task {
            do {
                try await runInternal(options: options, inputURL: inputURL)
                exitCode = 0
            } catch {
                exitCode = 1
                debugLog("[Headless] FAILED: \(error.localizedDescription)")
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 600) // 10 minutes
        debugLog("=== Headless Done (exit \(exitCode)) ===")
        exit(exitCode)
    }

    // MARK: - Internal

    private static func runInternal(options: Options, inputURL: URL) async throws {
        // Validate input exists and is readable
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw FFmpegKitError.openInputFailed(inputURL.path, -2) // ENOENT-ish
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: inputURL.path)
        let size = (attrs?[.size] as? Int64) ?? 0
        debugLog("[Headless] Input size: \(size) bytes")

        // Copy to temp (matches UI behavior and avoids permission issues)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + inputURL.lastPathComponent)
        try? FileManager.default.removeItem(at: tempURL)
        try FileManager.default.copyItem(at: inputURL, to: tempURL)
        debugLog("[Headless] Temp copy: \(tempURL.path)")

        // Probe metadata
        let probe = MediaProbeService()
        let media = try await probe.probe(url: tempURL, bookmarkData: nil)
        debugLog("[Headless] Probe duration: \(String(format: "%.3f", media.duration))s")
        debugLog("[Headless] Probe resolution: \(media.resolution?.description ?? "N/A")")
        debugLog("[Headless] Probe codecs: v=\(media.videoCodec ?? "N/A") a=\(media.audioCodec ?? "N/A")")

        let hw = HardwareDetector().detectCapabilities()
        ConvertifyDiagnostics.log("Hardware: VideoToolbox=\(hw.hasVideoToolbox), GPU=\(hw.gpuName ?? "N/A") encoders=\(hw.supportedEncoders)")

        switch options.tool {
        case .all:
            try await runScenario(.trim, options: options, input: media, hardware: hw)
            try await runScenario(.extractAudio, options: options, input: media, hardware: hw)
            try await runScenario(.compress, options: options, input: media, hardware: hw)
        default:
            try await runScenario(options.tool, options: options, input: media, hardware: hw)
        }
    }

    private static func runScenario(
        _ tool: Tool,
        options: Options,
        input: MediaFile,
        hardware: HardwareAcceleration
    ) async throws {
        var formatExt: String
        var outputURL: URL

        // Choose default output format per tool (can be overridden via --format / --output)
        switch tool {
        case .convert:
            formatExt = options.format ?? "mp4"
        case .trim:
            formatExt = options.format ?? "mp4"
        case .compress:
            formatExt = options.format ?? "mp4"
        case .extractAudio:
            formatExt = options.format ?? "m4a"
        case .gif:
            formatExt = "gif"
        case .all:
            formatExt = options.format ?? "mp4"
        }

        if let out = options.outputPath {
            outputURL = URL(fileURLWithPath: out)
            if outputURL.pathExtension.isEmpty {
                outputURL = outputURL.appendingPathExtension(formatExt)
            }
        } else {
            outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("convertify_headless_\(tool.rawValue)")
                .appendingPathExtension(formatExt)
        }

        // Map extension to OutputFormat
        let outputFormat: OutputFormat = {
            switch formatExt.lowercased() {
            case "mp4": return .mp4
            case "mov": return .mov
            case "mkv": return .mkv
            case "webm": return .webm
            case "avi": return .avi
            case "gif": return .gif
            case "m4a": return .m4a
            case "aac": return .aac
            case "flac": return .flac
            default: return .mp4
            }
        }()

        var advanced = AdvancedOptions()

        // Tool-specific option setup (mimics the UI defaults and interactions)
        switch tool {
        case .trim:
            let start = options.startSeconds ?? min(1.0, max(0.0, input.duration * 0.15))
            let end = options.endSeconds ?? min(input.duration, start + 2.0)
            advanced.startTime = max(0, min(start, input.duration))
            advanced.endTime = max(advanced.startTime ?? 0, min(end, input.duration))
            debugLog("[Headless][Trim] start=\(advanced.startTime ?? 0)s end=\(advanced.endTime ?? 0)s (input \(input.duration)s)")

        case .compress:
            // Use either explicit bitrate, or compute bitrate from a target size.
            let duration = max(1.0, input.duration)
            if let kbps = options.videoBitrateKbps {
                advanced.videoBitrate = .custom
                advanced.customVideoBitrate = kbps
                debugLog("[Headless][Compress] Using explicit bitrate: \(kbps) kbps")
            } else {
                let inputMB = max(1.0, Double(input.fileSize) / (1024 * 1024))
                let targetMB = options.targetSizeMB ?? max(1.0, min(inputMB, inputMB * 0.5))
                advanced.targetSizeMB = targetMB
                let audioBitrate = 128
                let totalKbps = Int((targetMB * 8 * 1024) / duration)
                let videoKbps = max(100, totalKbps - audioBitrate)
                advanced.videoBitrate = .custom
                advanced.customVideoBitrate = videoKbps
                debugLog("[Headless][Compress] targetMB=\(String(format: "%.1f", targetMB)) -> videoBitrate=\(videoKbps) kbps (duration \(duration)s)")
            }

        case .extractAudio:
            // Strip video is handled automatically by FFmpegCommandBuilder for audio formats.
            debugLog("[Headless][ExtractAudio] outputFormat=\(outputFormat.fileExtension)")
            
        case .gif:
            advanced.gifFps = options.gifFps
            advanced.gifWidth = options.gifWidth
            // Also apply trim if specified
            if let start = options.startSeconds {
                advanced.startTime = start
            }
            if let end = options.endSeconds {
                advanced.endTime = end
            }
            debugLog("[Headless][GIF] fps=\(advanced.gifFps) width=\(advanced.gifWidth) start=\(advanced.startTime ?? 0)s end=\(advanced.endTime ?? input.duration)s")

        case .convert:
            break
        case .all:
            break
        }

        // Prepare job (same shape as the UI)
        let job = ConversionJob(
            id: UUID(),
            inputFile: input,
            outputURL: outputURL,
            outputFormat: outputFormat,
            qualityPreset: options.quality,
            advancedOptions: advanced,
            status: .preparing,
            progress: 0
        )

        // Build command exactly like the UI
        let command = FFmpegCommandBuilder.build(job: job, hardwareAcceleration: hardware)
        ConvertifyDiagnostics.log("FFmpegCommand preInput: \(command.preInputArguments)")
        ConvertifyDiagnostics.log("FFmpegCommand args: \(command.arguments)")
        ConvertifyDiagnostics.log("FFmpegCommand full: \(command.fullArguments.joined(separator: " "))")

        debugLog("[Headless][\(tool.rawValue)] Output: \(outputURL.path)")

        if options.dryRun {
            debugLog("[Headless][\(tool.rawValue)] Dry-run enabled (not executing).")
            return
        }

        // Delete output if exists
        try? FileManager.default.removeItem(at: outputURL)

        let _ /*effectiveDuration*/: TimeInterval = {
            if advanced.hasTrimming {
                let s = advanced.startTime ?? 0
                let e = advanced.endTime ?? input.duration
                return max(1, e - s)
            }
            return max(1, input.duration)
        }()

        // GIF uses system ffmpeg (bundled FFmpegKit doesn't have GIF muxer)
        if tool == .gif || outputFormat == .gif {
            // Prefer system ffmpeg which has full GIF support
            if SystemFFmpegGifTranscoder.isAvailable() {
                debugLog("[Headless][GIF] Using system ffmpeg for GIF generation")
                let transcoder = SystemFFmpegGifTranscoder(
                    inputPath: input.url.path,
                    outputPath: outputURL.path,
                    fps: advanced.gifFps,
                    width: advanced.gifWidth,
                    startTime: advanced.startTime,
                    endTime: advanced.endTime
                )
                
                var lastPct = -1
                do {
                    try transcoder.transcode { progress in
                        let pct = Int(progress.percentage * 100)
                        if pct != lastPct {
                            lastPct = pct
                            let timeStr = String(format: "%.2f", progress.currentTime)
                            debugLog("[Headless][\(tool.rawValue)] \(pct)% t=\(timeStr)s")
                        }
                    }
                } catch {
                    debugLog("[Headless][\(tool.rawValue)] ERROR: \(error.localizedDescription)")
                    throw error
                }
            } else {
                // Try bundled transcoder as fallback (will likely fail without GIF muxer)
                debugLog("[Headless][GIF] System ffmpeg not available, trying bundled (may fail)")
                let transcoder = GifTranscoder(
                    inputPath: input.url.path,
                    outputPath: outputURL.path,
                    fps: advanced.gifFps,
                    width: advanced.gifWidth,
                    crop: nil,
                    startTime: advanced.startTime,
                    endTime: advanced.endTime
                )
                
                var lastPct = -1
                do {
                    try transcoder.transcode { progress in
                        let pct = Int(progress.percentage * 100)
                        if pct != lastPct {
                            lastPct = pct
                            let timeStr = String(format: "%.2f", progress.currentTime)
                            let speedStr = String(format: "%.1f", progress.speed)
                            debugLog("[Headless][\(tool.rawValue)] \(pct)% t=\(timeStr)s speed=\(speedStr)x")
                        }
                    }
                } catch {
                    debugLog("[Headless][\(tool.rawValue)] ERROR: \(error.localizedDescription)")
                    debugLog("[Headless][GIF] 💡 Install ffmpeg for GIF support: brew install ffmpeg")
                    throw error
                }
            }
        } else {
            // Use TranscodingPipeline for non-GIF (bypasses @MainActor FFmpegService)
            let outputExt = outputURL.pathExtension.lowercased()
            var config = command.toTranscodingConfig(format: outputExt)
            
            // Select hardware encoder if available
            if config.videoCodec == nil || config.videoCodec == "libx264" {
                let (encoder, isHW) = EncoderSelector.selectEncoder(for: outputExt, preferHardware: true)
                if isHW {
                    config.videoCodec = encoder
                }
            }
            
            ConvertifyDiagnostics.log("TranscodingConfig: video=\(config.videoCodec ?? "nil") audio=\(config.audioCodec ?? "nil") start=\(config.startTime ?? -1) end=\(config.endTime ?? -1)")
            
            let pipeline = TranscodingPipeline(config: config)
            
            var lastPct = -1
            do {
                try pipeline.transcode { progress in
                    let pct = Int(progress.percentage * 100)
                    if pct != lastPct {
                        lastPct = pct
                        let timeStr = String(format: "%.2f", progress.currentTime)
                        let speedStr = String(format: "%.1f", progress.speed)
                        debugLog("[Headless][\(tool.rawValue)] \(pct)% t=\(timeStr)s speed=\(speedStr)x")
                    }
                }
            } catch {
                debugLog("[Headless][\(tool.rawValue)] ERROR: \(error.localizedDescription)")
                throw error
            }
        }

        // Validate output
        if FileManager.default.fileExists(atPath: outputURL.path) {
            let outAttrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
            let outSize = (outAttrs?[.size] as? Int64) ?? 0
            debugLog("[Headless][\(tool.rawValue)] ✅ Output created (\(outSize) bytes)")
        } else {
            debugLog("[Headless][\(tool.rawValue)] ❌ Output was not created")
            throw FFmpegError.conversionFailed("Output file was not created")
        }
    }

    private static func printUsageAndExit() -> Never {
        let exe = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "Convertify"
        print("""
        Convertify headless mode

        Usage:
          \(exe) --headless --input <path> [--tool <convert|trim|compress|extract-audio|all>]
                               [--output <path>] [--format <ext>] [--quality <fast|balanced|quality>]
                               [--start <seconds>] [--end <seconds>]
                               [--target-mb <mb>] [--video-bitrate-kbps <kbps>]
                               [--dry-run] [--verbose]

        Examples:
          \(exe) --headless --input ./video.mp4 --tool trim --start 1 --end 3 --verbose
          \(exe) --headless --input ./video.mp4 --tool extract-audio --format m4a
          \(exe) --headless --input ./video.mp4 --tool compress --target-mb 10
          \(exe) --headless --input ./video.mp4 --tool all --verbose
        """)
        exit(1)
    }
}

