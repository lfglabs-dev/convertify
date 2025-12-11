//
//  ConversionJob.swift
//  Convertify
//
//  Represents a conversion task with its progress and status
//

import Foundation

struct ConversionJob: Identifiable {
    let id: UUID
    let inputFile: MediaFile
    let outputURL: URL
    let outputFormat: OutputFormat
    let qualityPreset: QualityPreset
    let advancedOptions: AdvancedOptions
    var status: ConversionStatus
    var progress: Double // 0.0 to 1.0
    var currentTime: TimeInterval?
    var speed: Double?
    var startedAt: Date?
    var completedAt: Date?
    
    var progressPercentage: Int {
        Int(progress * 100)
    }
    
    var formattedSpeed: String? {
        guard let speed = speed else { return nil }
        return String(format: "%.1fx", speed)
    }
    
    /// The actual duration being converted, accounting for trim settings
    var effectiveDuration: TimeInterval {
        let start = advancedOptions.startTime ?? 0
        let end = advancedOptions.endTime ?? inputFile.duration
        return max(0, end - start)
    }
    
    var estimatedTimeRemaining: TimeInterval? {
        guard let speed = speed, speed > 0, progress > 0 else { return nil }
        let remaining = effectiveDuration * (1 - progress)
        return remaining / speed
    }
    
    var formattedETR: String? {
        guard let etr = estimatedTimeRemaining else { return nil }
        let minutes = Int(etr) / 60
        let seconds = Int(etr) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s remaining"
        } else {
            return "\(seconds)s remaining"
        }
    }
}

// MARK: - Conversion Status

enum ConversionStatus: Equatable {
    case preparing
    case converting
    case completed
    case failed(String)
    case cancelled
    
    var isActive: Bool {
        switch self {
        case .preparing, .converting:
            return true
        default:
            return false
        }
    }
    
    var icon: String {
        switch self {
        case .preparing: return "hourglass"
        case .converting: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }
    
    var label: String {
        switch self {
        case .preparing: return "Preparing..."
        case .converting: return "Converting..."
        case .completed: return "Completed"
        case .failed(let error): return "Failed: \(error)"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Advanced Options

struct AdvancedOptions: Equatable {
    // Resolution
    var resolutionOverride: ResolutionOverride = .original
    var customResolution: Resolution?
    
    // Video
    var videoBitrate: BitrateOption = .auto
    var customVideoBitrate: Int? // in kbps
    
    // Audio
    var audioBitrate: AudioBitrateOption = .auto
    var audioCodec: AudioCodecOption = .auto
    var audioChannels: AudioChannelsOption = .original
    
    // Trimming
    var startTime: TimeInterval?
    var endTime: TimeInterval?
    
    // Cropping (percentage-based: 0-100)
    var cropLeft: Double = 0
    var cropRight: Double = 100
    var cropTop: Double = 0
    var cropBottom: Double = 100
    
    // GIF settings
    var gifFps: Int = 15
    var gifWidth: Int = 480
    
    // Compression
    var targetSizeMB: Double? // Target file size in MB
    
    // Image quality
    var imageQuality: Int = 85 // 1-100 for JPEG/WebP/HEIC
    
    // Custom args
    var customFFmpegArgs: String = ""
    
    var hasTrimming: Bool {
        startTime != nil || endTime != nil
    }
    
    var hasCropping: Bool {
        cropLeft > 0 || cropRight < 100 || cropTop > 0 || cropBottom < 100
    }
}

// MARK: - Resolution Override

enum ResolutionOverride: String, CaseIterable, Identifiable {
    case original = "Original"
    case p4K = "4K (2160p)"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var resolution: Resolution? {
        switch self {
        case .original, .custom: return nil
        case .p4K: return .p4K
        case .p1080: return .p1080
        case .p720: return .p720
        case .p480: return .p480
        }
    }
}

// MARK: - Bitrate Options

enum BitrateOption: String, CaseIterable, Identifiable {
    case auto = "Auto (CRF)"
    case custom = "Custom"
    
    var id: String { rawValue }
}

enum AudioBitrateOption: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case kbps128 = "128 kbps"
    case kbps192 = "192 kbps"
    case kbps256 = "256 kbps"
    case kbps320 = "320 kbps"
    
    var id: String { rawValue }
    
    var kbps: Int? {
        switch self {
        case .auto: return nil
        case .kbps128: return 128
        case .kbps192: return 192
        case .kbps256: return 256
        case .kbps320: return 320
        }
    }
}

// MARK: - Audio Codec Options

enum AudioCodecOption: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case aac = "AAC"
    case mp3 = "MP3"
    case opus = "Opus"
    case flac = "FLAC"
    case copy = "Copy (No re-encode)"
    
    var id: String { rawValue }
    
    var ffmpegCodec: String? {
        switch self {
        case .auto: return nil
        case .aac: return "aac"
        case .mp3: return "libmp3lame"
        case .opus: return "libopus"
        case .flac: return "flac"
        case .copy: return "copy"
        }
    }
}

// MARK: - Audio Channels

enum AudioChannelsOption: String, CaseIterable, Identifiable {
    case original = "Original"
    case mono = "Mono"
    case stereo = "Stereo"
    case surround51 = "5.1 Surround"
    
    var id: String { rawValue }
    
    var channels: Int? {
        switch self {
        case .original: return nil
        case .mono: return 1
        case .stereo: return 2
        case .surround51: return 6
        }
    }
}

