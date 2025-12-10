//
//  QualityPreset.swift
//  Convertify
//
//  Quality presets for encoding
//

import Foundation
import SwiftUI

enum QualityPreset: String, CaseIterable, Identifiable {
    case fast = "Fast"
    case balanced = "Balanced"
    case quality = "Quality"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .fast:
            return "Quick encode, smaller file"
        case .balanced:
            return "Good balance of speed and quality"
        case .quality:
            return "Best quality, larger file"
        }
    }
    
    var icon: String {
        switch self {
        case .fast: return "hare"
        case .balanced: return "scale.3d"
        case .quality: return "sparkles"
        }
    }
    
    var color: Color {
        switch self {
        case .fast: return .green
        case .balanced: return .blue
        case .quality: return .purple
        }
    }
    
    // CRF (Constant Rate Factor) - lower = better quality, bigger file
    var crf: Int {
        switch self {
        case .fast: return 28
        case .balanced: return 23
        case .quality: return 18
        }
    }
    
    // x264/x265 preset
    var encoderPreset: String {
        switch self {
        case .fast: return "veryfast"
        case .balanced: return "medium"
        case .quality: return "slow"
        }
    }
    
    // VideoToolbox quality (0-100, higher = better)
    var videotoolboxQuality: Int {
        switch self {
        case .fast: return 50
        case .balanced: return 65
        case .quality: return 85
        }
    }
    
    // Audio quality
    var audioBitrate: Int {
        switch self {
        case .fast: return 128
        case .balanced: return 192
        case .quality: return 320
        }
    }
    
    // VP9 specific
    var vp9Quality: Int {
        switch self {
        case .fast: return 35
        case .balanced: return 30
        case .quality: return 20
        }
    }
    
    var vp9Speed: Int {
        switch self {
        case .fast: return 4
        case .balanced: return 2
        case .quality: return 1
        }
    }
}

// MARK: - Encoding Parameters Helper

struct EncodingParameters {
    let preset: QualityPreset
    let useHardwareAcceleration: Bool
    let videoCodec: VideoCodec
    
    var videoArgs: [String] {
        var args: [String] = []
        
        if useHardwareAcceleration, let hwCodec = videoCodec.hardwareAcceleratedCodec {
            // VideoToolbox encoding
            args += ["-c:v", hwCodec]
            // VideoToolbox uses different quality parameter
            // -q:v for quality (1-100 where lower is better for VT, we invert)
            let quality = 100 - preset.videotoolboxQuality
            args += ["-q:v", String(quality)]
        } else {
            // Software encoding
            switch videoCodec {
            case .h264:
                args += ["-c:v", "libx264"]
                args += ["-preset", preset.encoderPreset]
                args += ["-crf", String(preset.crf)]
            case .h265:
                args += ["-c:v", "libx265"]
                args += ["-preset", preset.encoderPreset]
                args += ["-crf", String(preset.crf)]
            case .vp9:
                args += ["-c:v", "libvpx-vp9"]
                args += ["-crf", String(preset.vp9Quality)]
                args += ["-b:v", "0"] // Required for CRF mode
                args += ["-cpu-used", String(preset.vp9Speed)]
            case .av1:
                args += ["-c:v", "libaom-av1"]
                args += ["-crf", String(preset.crf + 10)] // AV1 CRF is different
                args += ["-cpu-used", "4"]
            case .gif:
                args += ["-c:v", "gif"]
            case .none:
                args += ["-vn"] // No video
            }
        }
        
        return args
    }
    
    var audioArgs: [String] {
        ["-b:a", "\(preset.audioBitrate)k"]
    }
}

