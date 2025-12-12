//
//  HardwareDetector.swift
//  Convertify
//
//  Detects hardware acceleration capabilities using FFmpegKit
//

import Foundation

// MARK: - Hardware Acceleration Info

struct HardwareAcceleration {
    let hasVideoToolbox: Bool
    let supportedEncoders: [String]
    let supportedDecoders: [String]
    let gpuName: String?
    
    var supportsH264Encoding: Bool {
        supportedEncoders.contains("h264_videotoolbox")
    }
    
    var supportsHEVCEncoding: Bool {
        supportedEncoders.contains("hevc_videotoolbox")
    }
    
    var supportsH264Decoding: Bool {
        supportedDecoders.contains("h264") || supportedDecoders.contains("h264_videotoolbox")
    }
    
    var description: String {
        if hasVideoToolbox {
            var features: [String] = []
            if supportsH264Encoding { features.append("H.264") }
            if supportsHEVCEncoding { features.append("HEVC") }
            return "VideoToolbox: \(features.joined(separator: ", "))"
        }
        return "Software encoding"
    }
    
    static let none = HardwareAcceleration(
        hasVideoToolbox: false,
        supportedEncoders: [],
        supportedDecoders: [],
        gpuName: nil
    )
}

// MARK: - Hardware Detector

class HardwareDetector {
    
    private var cachedCapabilities: HardwareAcceleration?
    
    /// Detect hardware acceleration capabilities using FFmpegKit
    func detectCapabilities() -> HardwareAcceleration {
        if let cached = cachedCapabilities {
            return cached
        }
        
        // Use our HardwareAccelerationManager to detect capabilities
        let isVTAvailable = HardwareAccelerationManager.isVideoToolboxAvailable
        let encoders = HardwareAccelerationManager.supportedEncoders
        let decoders = HardwareAccelerationManager.supportedDecoders
        let gpuName = detectGPU()
        
        let capabilities = HardwareAcceleration(
            hasVideoToolbox: isVTAvailable,
            supportedEncoders: encoders,
            supportedDecoders: decoders,
            gpuName: gpuName
        )
        
        cachedCapabilities = capabilities
        return capabilities
    }
    
    /// Check if a specific encoder is available
    func isEncoderAvailable(_ encoder: String) -> Bool {
        detectCapabilities().supportedEncoders.contains(encoder)
    }
    
    /// Get the best encoder for a codec
    func bestEncoder(for codec: VideoCodec, preferHardware: Bool = true) -> String {
        let caps = detectCapabilities()
        
        if preferHardware {
            switch codec {
            case .h264:
                if caps.supportsH264Encoding {
                    return "h264_videotoolbox"
                }
            case .h265:
                if caps.supportsHEVCEncoding {
                    return "hevc_videotoolbox"
                }
            default:
                break
            }
        }
        
        // Fall back to software encoder
        return codec.ffmpegCodec
    }
    
    // MARK: - Private Methods
    
    private func detectGPU() -> String? {
        // Use IOKit to get GPU info (works in sandbox)
        // For now, return a generic name based on architecture
        #if arch(arm64)
        return "Apple Silicon GPU"
        #else
        return "Intel GPU"
        #endif
    }
}
