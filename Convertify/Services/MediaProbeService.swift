//
//  MediaProbeService.swift
//  Convertify
//
//  Analyzes media files using FFmpegKit's libavformat
//

import Foundation
import Libavformat
import Libavcodec
import Libavutil

final class MediaProbeService: Sendable {
    
    /// Probe a media file and return its metadata
    func probe(url: URL, bookmarkData: Data? = nil) async throws -> MediaFile {
        try await withCheckedThrowingContinuation { continuation in
            // Run on background thread since libav operations can be slow
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.probeSync(url: url, bookmarkData: bookmarkData)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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
    
    private func probeSync(url: URL, bookmarkData: Data? = nil) throws -> MediaFile {
        var formatContext: UnsafeMutablePointer<AVFormatContext>? = nil
        let path = url.path
        
        // Open input file
        var ret = avformat_open_input(&formatContext, path, nil, nil)
        guard ret >= 0, let ctx = formatContext else {
            throw FFmpegKitError.openInputFailed(path, ret)
        }
        
        // Ensure cleanup
        defer {
            avformat_close_input(&formatContext)
        }
        
        // Find stream info
        ret = avformat_find_stream_info(ctx, nil)
        guard ret >= 0 else {
            throw FFmpegKitError.streamInfoNotFound(path)
        }
        
        // Extract format-level info
        // NOTE: `AVFormatContext.duration` can be 0/AV_NOPTS_VALUE for some MOVs.
        // Fall back to per-stream duration to keep Trim/Compress accurate.
        let duration: TimeInterval = {
            let raw = ctx.pointee.duration
            if raw != AV_NOPTS_VALUE_SWIFT, raw > 0 {
                // Duration is in AV_TIME_BASE units (microseconds)
                return Double(raw) / Double(AV_TIME_BASE)
            }
            
            var maxStreamDuration: Double = 0
            for i in 0..<Int(ctx.pointee.nb_streams) {
                guard let stream = ctx.pointee.streams[i] else { continue }
                
                let d = stream.pointee.duration
                if d != AV_NOPTS_VALUE_SWIFT, d > 0 {
                    let tb = stream.pointee.time_base
                    if tb.den != 0 {
                        let seconds = Double(d) * Double(tb.num) / Double(tb.den)
                        if seconds > maxStreamDuration {
                            maxStreamDuration = seconds
                        }
                    }
                    continue
                }
                
                // Last resort: estimate from frame count / fps (rough)
                let frames = stream.pointee.nb_frames
                let fps = stream.pointee.avg_frame_rate
                if frames > 0, fps.den != 0, fps.num != 0 {
                    let seconds = Double(frames) * Double(fps.den) / Double(fps.num)
                    if seconds > maxStreamDuration {
                        maxStreamDuration = seconds
                    }
                }
            }
            
            return max(0, maxStreamDuration)
        }()
        
        let bitrate: Int64? = ctx.pointee.bit_rate > 0 ? ctx.pointee.bit_rate : nil
        
        // Get file size
        let fileSize: Int64 = {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
                return (attrs[.size] as? Int64) ?? 0
            }
            return 0
        }()
        
        // Find video and audio streams
        var videoStream: UnsafeMutablePointer<AVStream>? = nil
        var audioStream: UnsafeMutablePointer<AVStream>? = nil
        
        for i in 0..<Int(ctx.pointee.nb_streams) {
            let stream = ctx.pointee.streams[i]!
            let codecType = stream.pointee.codecpar.pointee.codec_type
            
            if codecType == AVMEDIA_TYPE_VIDEO && videoStream == nil {
                videoStream = stream
            } else if codecType == AVMEDIA_TYPE_AUDIO && audioStream == nil {
                audioStream = stream
            }
        }
        
        // Video properties
        var videoCodec: String? = nil
        var resolution: Resolution? = nil
        var frameRate: Double? = nil
        
        if let video = videoStream {
            let codecpar = video.pointee.codecpar.pointee
            
            // Get codec name
            if let codecDesc = avcodec_descriptor_get(codecpar.codec_id) {
                videoCodec = String(cString: codecDesc.pointee.name)
            }
            
            // Resolution
            if codecpar.width > 0 && codecpar.height > 0 {
                resolution = Resolution(width: Int(codecpar.width), height: Int(codecpar.height))
            }
            
            // Frame rate
            let avgFps = video.pointee.avg_frame_rate
            if avgFps.den > 0 && avgFps.num > 0 {
                frameRate = Double(avgFps.num) / Double(avgFps.den)
            } else {
                let rFps = video.pointee.r_frame_rate
                if rFps.den > 0 && rFps.num > 0 {
                    frameRate = Double(rFps.num) / Double(rFps.den)
                }
            }
        }
        
        // Audio properties
        var audioCodec: String? = nil
        var audioSampleRate: Int? = nil
        var audioChannels: Int? = nil
        
        if let audio = audioStream {
            let codecpar = audio.pointee.codecpar.pointee
            
            // Get codec name
            if let codecDesc = avcodec_descriptor_get(codecpar.codec_id) {
                audioCodec = String(cString: codecDesc.pointee.name)
            }
            
            // Sample rate
            if codecpar.sample_rate > 0 {
                audioSampleRate = Int(codecpar.sample_rate)
            }
            
            // Channels
            let channels = codecpar.ch_layout.nb_channels
            if channels > 0 {
                audioChannels = Int(channels)
            }
        }
        
        // Use the passed bookmark data (created on main thread while fileImporter access was valid)
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
            audioChannels: audioChannels,
            bookmarkData: bookmarkData
        )
    }
}

// MARK: - Errors

enum ProbeError: LocalizedError {
    case invalidFile
    case ffprobeNotFound  // Kept for API compatibility, but no longer used
    
    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "Not a valid media file"
        case .ffprobeNotFound:
            return "Media probing failed"
        }
    }
}
