//
//  MediaProbeService.swift
//  Convertify
//
//  Analyzes media files using ffprobe
//

import Foundation

class MediaProbeService {
    
    /// Path to ffprobe binary
    private var ffprobePath: String {
        let paths = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return "ffprobe"
    }
    
    /// Probe a media file and return its metadata
    func probe(url: URL) async throws -> MediaFile {
        let json = try await runFFprobe(url: url)
        return try parseProbeResult(json: json, url: url)
    }
    
    /// Check if a file is a valid media file
    func isValidMediaFile(url: URL) async -> Bool {
        do {
            _ = try await probe(url: url)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Private Methods
    
    private func runFFprobe(url: URL) async throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            url.path
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continuation.resume(returning: [:])
                    return
                }
                
                continuation.resume(returning: json)
            }
            
            do {
                try process.run()
            } catch {
                // Clear the termination handler before resuming to prevent potential double-resume
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func parseProbeResult(json: [String: Any], url: URL) throws -> MediaFile {
        guard !json.isEmpty else {
            throw ProbeError.invalidFile
        }
        
        let format = json["format"] as? [String: Any] ?? [:]
        let streams = json["streams"] as? [[String: Any]] ?? []
        
        // Find video and audio streams
        let videoStream = streams.first { ($0["codec_type"] as? String) == "video" }
        let audioStream = streams.first { ($0["codec_type"] as? String) == "audio" }
        
        // Extract duration
        var duration: TimeInterval = 0
        if let durationStr = format["duration"] as? String {
            duration = Double(durationStr) ?? 0
        } else if let durationStr = videoStream?["duration"] as? String {
            duration = Double(durationStr) ?? 0
        }
        
        // Extract file size
        var fileSize: Int64 = 0
        if let sizeStr = format["size"] as? String {
            fileSize = Int64(sizeStr) ?? 0
        } else {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            fileSize = (attributes?[.size] as? Int64) ?? 0
        }
        
        // Extract bitrate
        var bitrate: Int64? = nil
        if let bitrateStr = format["bit_rate"] as? String {
            bitrate = Int64(bitrateStr)
        }
        
        // Video properties
        var videoCodec: String? = nil
        var resolution: Resolution? = nil
        var frameRate: Double? = nil
        
        if let video = videoStream {
            videoCodec = video["codec_name"] as? String
            
            if let width = video["width"] as? Int,
               let height = video["height"] as? Int {
                resolution = Resolution(width: width, height: height)
            }
            
            // Parse frame rate (can be "30/1" or "29.97")
            if let fpsStr = video["r_frame_rate"] as? String {
                frameRate = parseFrameRate(fpsStr)
            } else if let fpsStr = video["avg_frame_rate"] as? String {
                frameRate = parseFrameRate(fpsStr)
            }
        }
        
        // Audio properties
        var audioCodec: String? = nil
        var audioSampleRate: Int? = nil
        var audioChannels: Int? = nil
        
        if let audio = audioStream {
            audioCodec = audio["codec_name"] as? String
            
            if let sampleRateStr = audio["sample_rate"] as? String {
                audioSampleRate = Int(sampleRateStr)
            }
            
            audioChannels = audio["channels"] as? Int
        }
        
        return MediaFile(
            id: UUID(),
            url: url,
            filename: url.lastPathComponent,
            fileExtension: url.pathExtension.lowercased(),
            fileSize: fileSize,
            duration: duration,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            resolution: resolution,
            frameRate: frameRate,
            bitrate: bitrate,
            audioSampleRate: audioSampleRate,
            audioChannels: audioChannels
        )
    }
    
    private func parseFrameRate(_ str: String) -> Double? {
        if str.contains("/") {
            let parts = str.split(separator: "/")
            guard parts.count == 2,
                  let num = Double(parts[0]),
                  let den = Double(parts[1]),
                  den != 0 else {
                return nil
            }
            return num / den
        }
        return Double(str)
    }
}

// MARK: - Errors

enum ProbeError: LocalizedError {
    case invalidFile
    case ffprobeNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "Not a valid media file"
        case .ffprobeNotFound:
            return "ffprobe not found. Please install FFmpeg via Homebrew."
        }
    }
}

