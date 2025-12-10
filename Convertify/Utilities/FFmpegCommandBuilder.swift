//
//  FFmpegCommandBuilder.swift
//  Convertify
//
//  Builds FFmpeg command arguments based on conversion settings
//

import Foundation

struct FFmpegCommandBuilder {
    
    /// Build a complete FFmpeg command for a conversion job
    static func build(job: ConversionJob, hardwareAcceleration: HardwareAcceleration) -> FFmpegCommand {
        var args: [String] = []
        
        let inputFile = job.inputFile
        let format = job.outputFormat
        _ = job.qualityPreset // Used in sub-functions via job parameter
        let options = job.advancedOptions
        
        // Handle image conversions separately
        if format.isImageFormat || inputFile.isImage {
            return buildImageCommand(job: job)
        }
        
        // Pre-input options (must appear before -i for hardware decoding)
        let preInputArgs = buildInputOptions(hardwareAcceleration: hardwareAcceleration)
        
        // Trimming (seeking)
        if let startTime = options.startTime, startTime > 0 {
            args += ["-ss", formatTime(startTime)]
        }
        
        // Duration / end time
        if let endTime = options.endTime {
            let duration = endTime - (options.startTime ?? 0)
            if duration > 0 {
                args += ["-t", formatTime(duration)]
            }
        }
        
        // Video encoding
        if format.isVideoFormat && inputFile.isVideo {
            args += buildVideoArgs(
                job: job,
                hardwareAcceleration: hardwareAcceleration
            )
        } else if format.isAudioFormat {
            // Audio-only output, strip video
            args += ["-vn"]
        }
        
        // Audio encoding
        if format != .gif {
            args += buildAudioArgs(job: job)
        } else {
            args += ["-an"] // No audio for GIF
        }
        
        // Format-specific options
        args += buildFormatOptions(format: format)
        
        // Resolution override
        args += buildResolutionArgs(job: job)
        
        // Custom FFmpeg arguments
        if !options.customFFmpegArgs.isEmpty {
            args += parseCustomArgs(options.customFFmpegArgs)
        }
        
        return FFmpegCommand(
            inputPath: job.inputFile.url.path,
            outputPath: job.outputURL.path,
            preInputArguments: preInputArgs,
            arguments: args
        )
    }
    
    // MARK: - Image Conversion
    
    private static func buildImageCommand(job: ConversionJob) -> FFmpegCommand {
        var args: [String] = []
        let format = job.outputFormat
        let options = job.advancedOptions
        
        // Build video filter chain
        var filters: [String] = []
        
        // Cropping (if any)
        if options.hasCropping, let res = job.inputFile.resolution {
            let cropWidth = Int(Double(res.width) * (options.cropRight - options.cropLeft) / 100)
            let cropHeight = Int(Double(res.height) * (options.cropBottom - options.cropTop) / 100)
            let cropX = Int(Double(res.width) * options.cropLeft / 100)
            let cropY = Int(Double(res.height) * options.cropTop / 100)
            filters.append("crop=\(cropWidth):\(cropHeight):\(cropX):\(cropY)")
        }
        
        // Resolution scaling
        if let targetRes = options.resolutionOverride.resolution ?? options.customResolution {
            filters.append("scale=\(targetRes.width):\(targetRes.height):flags=lanczos")
        }
        
        // Apply filters if any
        if !filters.isEmpty {
            args += ["-vf", filters.joined(separator: ",")]
        }
        
        // Format-specific quality settings using imageQuality
        let quality = options.imageQuality
        
        switch format {
        case .jpg:
            // JPEG quality: 2-31 where lower is better
            // Map 1-100 to 31-2
            let jpegQuality = max(2, min(31, 31 - Int(Double(quality - 1) / 99 * 29)))
            args += ["-q:v", "\(jpegQuality)"]
        case .png:
            args += ["-compression_level", "6"] // PNG compression (0-9)
        case .webp:
            args += ["-quality", "\(quality)"] // WebP quality (0-100)
            args += ["-preset", "default"]
        case .heic:
            args += ["-c:v", "hevc"]
            args += ["-tag:v", "hvc1"]
            // Map quality 1-100 to CRF 51-0 (lower CRF = better quality)
            let crf = max(0, min(51, 51 - Int(Double(quality) / 100 * 51)))
            args += ["-crf", "\(crf)"]
        case .tiff:
            args += ["-compression_algo", "lzw"]
        case .bmp:
            // BMP doesn't need special options
            break
        case .ico:
            // ICO - scale to standard icon size if not specified
            if options.resolutionOverride == .original && options.customResolution == nil && !options.hasCropping {
                args += ["-vf", "scale=256:256:flags=lanczos"]
            }
        default:
            break
        }
        
        // Custom arguments
        if !options.customFFmpegArgs.isEmpty {
            args += parseCustomArgs(options.customFFmpegArgs)
        }
        
        return FFmpegCommand(
            inputPath: job.inputFile.url.path,
            outputPath: job.outputURL.path,
            preInputArguments: [], // Image conversion doesn't need hardware decoding
            arguments: args
        )
    }
    
    // MARK: - Input Options
    
    private static func buildInputOptions(hardwareAcceleration: HardwareAcceleration) -> [String] {
        var args: [String] = []
        
        // Use hardware decoding if available
        if hardwareAcceleration.hasVideoToolbox {
            args += ["-hwaccel", "videotoolbox"]
        }
        
        return args
    }
    
    // MARK: - Video Arguments
    
    private static func buildVideoArgs(
        job: ConversionJob,
        hardwareAcceleration: HardwareAcceleration
    ) -> [String] {
        var args: [String] = []
        let format = job.outputFormat
        let preset = job.qualityPreset
        let options = job.advancedOptions
        
        let videoCodec = format.defaultVideoCodec
        
        // Special handling for GIF
        if format == .gif {
            return buildGifArgs(job: job)
        }
        
        // Choose encoder
        let useHardware = hardwareAcceleration.hasVideoToolbox && 
                          format.supportsHardwareAcceleration
        
        if useHardware, let hwEncoder = videoCodec.hardwareAcceleratedCodec,
           hardwareAcceleration.supportedEncoders.contains(hwEncoder) {
            // Hardware encoding (VideoToolbox)
            args += ["-c:v", hwEncoder]
            
            // VideoToolbox quality control
            // Use average bitrate for better quality control
            if case .custom = options.videoBitrate, let bitrate = options.customVideoBitrate {
                args += ["-b:v", "\(bitrate)k"]
            } else {
                // Calculate target bitrate based on resolution and quality
                let targetBitrate = calculateTargetBitrate(job: job)
                args += ["-b:v", "\(targetBitrate)k"]
            }
            
            // Enable B-frames for better compression (H.264 only)
            if videoCodec == .h264 {
                args += ["-bf", "3"]
            }
            
        } else {
            // Software encoding
            switch videoCodec {
            case .h264:
                args += ["-c:v", "libx264"]
                args += ["-preset", preset.encoderPreset]
                if case .custom = options.videoBitrate, let bitrate = options.customVideoBitrate {
                    args += ["-b:v", "\(bitrate)k"]
                } else {
                    args += ["-crf", String(preset.crf)]
                }
                // Use High profile for better quality
                args += ["-profile:v", "high"]
                args += ["-level", "4.1"]
                
            case .h265:
                args += ["-c:v", "libx265"]
                args += ["-preset", preset.encoderPreset]
                if case .custom = options.videoBitrate, let bitrate = options.customVideoBitrate {
                    args += ["-b:v", "\(bitrate)k"]
                } else {
                    args += ["-crf", String(preset.crf)]
                }
                // Suppress x265 logging
                args += ["-x265-params", "log-level=error"]
                
            case .vp9:
                args += ["-c:v", "libvpx-vp9"]
                args += ["-crf", String(preset.vp9Quality)]
                args += ["-b:v", "0"]
                args += ["-cpu-used", String(preset.vp9Speed)]
                args += ["-row-mt", "1"] // Enable row-based multithreading
                
            case .av1:
                args += ["-c:v", "libaom-av1"]
                args += ["-crf", String(preset.crf + 15)]
                args += ["-cpu-used", "4"]
                args += ["-row-mt", "1"]
                
            default:
                break
            }
        }
        
        // Pixel format for compatibility
        if format == .mp4 || format == .mov {
            args += ["-pix_fmt", "yuv420p"]
        }
        
        return args
    }
    
    // MARK: - GIF Arguments
    
    private static func buildGifArgs(job: ConversionJob) -> [String] {
        var args: [String] = []
        let options = job.advancedOptions
        
        // GIF requires special handling with palette generation for quality
        // Using filter_complex for high-quality GIF
        
        // Use advancedOptions for FPS and width (from GifOptionsSection)
        let fps = options.gifFps > 0 ? options.gifFps : 15
        let scale = options.gifWidth > 0 ? options.gifWidth : (options.resolutionOverride.resolution?.width ?? 480)
        
        // Generate palette and apply it in one pass
        let filterComplex = "[0:v] fps=\(fps),scale=\(scale):-1:flags=lanczos,split [a][b];[a] palettegen=stats_mode=single [p];[b][p] paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle"
        
        args += ["-filter_complex", filterComplex]
        args += ["-loop", "0"] // Loop forever
        
        return args
    }
    
    // MARK: - Audio Arguments
    
    private static func buildAudioArgs(job: ConversionJob) -> [String] {
        var args: [String] = []
        let format = job.outputFormat
        let preset = job.qualityPreset
        let options = job.advancedOptions
        
        // Audio codec
        if let codec = options.audioCodec.ffmpegCodec {
            if codec == "copy" {
                args += ["-c:a", "copy"]
                return args // No other audio options when copying
            } else {
                args += ["-c:a", codec]
            }
        } else {
            // Auto-select based on format
            args += ["-c:a", format.defaultAudioCodec]
        }
        
        // Audio bitrate
        if let bitrate = options.audioBitrate.kbps {
            args += ["-b:a", "\(bitrate)k"]
        } else {
            args += ["-b:a", "\(preset.audioBitrate)k"]
        }
        
        // Audio channels
        if let channels = options.audioChannels.channels {
            args += ["-ac", String(channels)]
        }
        
        // Sample rate (keep original by default)
        if format == .wav {
            // WAV might need explicit sample rate
            args += ["-ar", "44100"]
        }
        
        return args
    }
    
    // MARK: - Format-Specific Options
    
    private static func buildFormatOptions(format: OutputFormat) -> [String] {
        var args: [String] = []
        
        switch format {
        case .mp4:
            // Fast start for web streaming
            args += ["-movflags", "+faststart"]
            
        case .mov:
            args += ["-movflags", "+faststart"]
            
        case .mkv:
            // MKV doesn't need special options
            break
            
        case .webm:
            // WebM specific
            args += ["-f", "webm"]
            
        case .avi:
            // AVI format
            args += ["-f", "avi"]
            
        case .gif:
            // Handled in buildGifArgs
            break
            
        case .mp3:
            args += ["-f", "mp3"]
            // ID3v2 tags
            args += ["-id3v2_version", "3"]
            
        case .aac:
            args += ["-f", "adts"]
            
        case .wav:
            args += ["-f", "wav"]
            
        case .flac:
            args += ["-f", "flac"]
            // Compression level
            args += ["-compression_level", "8"]
            
        case .ogg:
            args += ["-f", "ogg"]
            
        case .m4a:
            args += ["-f", "ipod"]
            args += ["-movflags", "+faststart"]
            
        // Image formats are handled separately in buildImageCommand
        case .jpg, .png, .webp, .heic, .tiff, .bmp, .ico:
            break
        }
        
        return args
    }
    
    // MARK: - Resolution Arguments
    
    private static func buildResolutionArgs(job: ConversionJob) -> [String] {
        var args: [String] = []
        let options = job.advancedOptions
        
        guard job.outputFormat.isVideoFormat else { return args }
        guard job.outputFormat != .gif else { return args } // GIF handled separately
        
        var filters: [String] = []
        
        // Cropping (if any)
        if options.hasCropping, let res = job.inputFile.resolution {
            let cropWidth = Int(Double(res.width) * (options.cropRight - options.cropLeft) / 100)
            let cropHeight = Int(Double(res.height) * (options.cropBottom - options.cropTop) / 100)
            let cropX = Int(Double(res.width) * options.cropLeft / 100)
            let cropY = Int(Double(res.height) * options.cropTop / 100)
            // Ensure dimensions are divisible by 2
            let adjustedWidth = (cropWidth / 2) * 2
            let adjustedHeight = (cropHeight / 2) * 2
            filters.append("crop=\(adjustedWidth):\(adjustedHeight):\(cropX):\(cropY)")
        }
        
        // Resolution scaling
        let targetResolution: Resolution?
        
        switch options.resolutionOverride {
        case .original:
            targetResolution = nil
        case .custom:
            targetResolution = options.customResolution
        default:
            targetResolution = options.resolutionOverride.resolution
        }
        
        if let resolution = targetResolution {
            // Scale while maintaining aspect ratio
            // -2 ensures the dimension is divisible by 2 (required by most codecs)
            filters.append("scale=\(resolution.width):-2")
        }
        
        // Apply filters if any
        if !filters.isEmpty {
            args += ["-vf", filters.joined(separator: ",")]
        }
        
        return args
    }
    
    // MARK: - Helper Methods
    
    private static func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%02d:%02d:%06.3f", hours, minutes, secs)
    }
    
    private static func parseCustomArgs(_ args: String) -> [String] {
        // Simple parsing - split by spaces, respecting quotes
        var result: [String] = []
        var current = ""
        var inQuotes = false
        
        for char in args {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == " " && !inQuotes {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        
        if !current.isEmpty {
            result.append(current)
        }
        
        return result
    }
    
    private static func calculateTargetBitrate(job: ConversionJob) -> Int {
        let preset = job.qualityPreset
        let resolution = job.inputFile.resolution ?? Resolution(width: 1920, height: 1080)
        
        // Base bitrate calculation based on resolution
        let pixelCount = resolution.width * resolution.height
        
        // Baseline: ~0.1 bits per pixel for 1080p at balanced quality
        let baseBpp: Double
        switch preset {
        case .fast: baseBpp = 0.07
        case .balanced: baseBpp = 0.1
        case .quality: baseBpp = 0.15
        }
        
        // Calculate bitrate in kbps
        // Assuming 30fps, but this is averaged out
        let bitrate = Int(Double(pixelCount) * baseBpp * 30 / 1000)
        
        // Clamp to reasonable ranges
        return max(500, min(50000, bitrate))
    }
}

