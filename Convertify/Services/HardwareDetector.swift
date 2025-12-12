//
//  HardwareDetector.swift
//  Convertify
//
//  Detects hardware acceleration capabilities (VideoToolbox)
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
    
    private var ffmpegExecutableURL: URL? {
        ExecutableLocator.resolveExecutableURL(
            named: "ffmpeg",
            preferredAbsolutePaths: [
                "/opt/homebrew/bin/ffmpeg",
                "/usr/local/bin/ffmpeg",
                "/usr/bin/ffmpeg"
            ]
        )
    }
    
    /// Detect hardware acceleration capabilities
    func detectCapabilities() -> HardwareAcceleration {
        if let cached = cachedCapabilities {
            return cached
        }
        
        let encoders = detectEncoders()
        let decoders = detectDecoders()
        let gpuName = detectGPU()
        
        // Check for VideoToolbox support
        let hasVT = encoders.contains("h264_videotoolbox") || 
                    encoders.contains("hevc_videotoolbox")
        
        let capabilities = HardwareAcceleration(
            hasVideoToolbox: hasVT,
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
    
    private func detectEncoders() -> [String] {
        guard let ffmpegExecutableURL else { return [] }

        let process = Process()
        process.executableURL = ffmpegExecutableURL
        process.arguments = ["-encoders", "-hide_banner"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            return parseEncoders(output)
        } catch {
            return []
        }
    }
    
    private func detectDecoders() -> [String] {
        guard let ffmpegExecutableURL else { return [] }

        let process = Process()
        process.executableURL = ffmpegExecutableURL
        process.arguments = ["-decoders", "-hide_banner"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            return parseDecoders(output)
        } catch {
            return []
        }
    }
    
    private func parseEncoders(_ output: String) -> [String] {
        var encoders: [String] = []
        
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Look for VideoToolbox encoders and common video encoders
            if trimmed.contains("videotoolbox") ||
               trimmed.contains("libx264") ||
               trimmed.contains("libx265") ||
               trimmed.contains("libvpx") {
                
                // Parse encoder name from line like "V..... h264_videotoolbox"
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2 {
                    let encoder = String(parts[1])
                    encoders.append(encoder)
                }
            }
        }
        
        return encoders
    }
    
    private func parseDecoders(_ output: String) -> [String] {
        var decoders: [String] = []
        
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.contains("videotoolbox") ||
               trimmed.hasPrefix("V") {
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2 {
                    let decoder = String(parts[1])
                    decoders.append(decoder)
                }
            }
        }
        
        return decoders
    }
    
    private func detectGPU() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPDisplaysDataType", "-json"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let displays = json["SPDisplaysDataType"] as? [[String: Any]],
                  let first = displays.first,
                  let name = first["sppci_model"] as? String else {
                return nil
            }
            
            return name
        } catch {
            return nil
        }
    }
}

