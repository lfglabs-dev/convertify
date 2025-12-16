//
//  MediaFile.swift
//  Convertify
//
//  Represents an input media file with its metadata
//

import Foundation

struct MediaFile: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let filename: String
    let fileExtension: String
    let fileSize: Int64
    let duration: TimeInterval
    let videoCodec: String?
    let audioCodec: String?
    let resolution: Resolution?
    let frameRate: Double?
    let bitrate: Int64?
    let audioSampleRate: Int?
    let audioChannels: Int?
    
    /// Security-scoped bookmark for sandbox access
    let bookmarkData: Data?
    
    /// Resolves the bookmark and starts security-scoped access. Returns true if access was granted.
    /// Caller MUST call stopAccessingSecurityScopedResource() when done.
    func startAccess() -> Bool {
        // First try the bookmark
        if let bookmarkData = bookmarkData {
            var isStale = false
            if let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if resolvedURL.startAccessingSecurityScopedResource() {
                    return true
                }
            }
        }
        // Fall back to direct access
        return url.startAccessingSecurityScopedResource()
    }
    
    func stopAccess() {
        url.stopAccessingSecurityScopedResource()
    }
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    var isVideo: Bool {
        videoCodec != nil
    }
    
    var isAudioOnly: Bool {
        videoCodec == nil && audioCodec != nil
    }
    
    var mediaType: MediaType {
        // Check image first by extension (most reliable for images)
        if isImage {
            return .image
        } else if isVideo {
            return .video
        } else if isAudioOnly {
            return .audio
        } else {
            return .unknown
        }
    }
    
    var isImage: Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp", "ico", "svg"]
        return imageExtensions.contains(fileExtension.lowercased())
    }
}

// MARK: - Resolution

struct Resolution: Equatable, CustomStringConvertible {
    let width: Int
    let height: Int
    
    var description: String {
        "\(width)×\(height)"
    }
    
    var aspectRatio: Double {
        guard height > 0 else { return 0 }
        return Double(width) / Double(height)
    }
    
    var qualityLabel: String {
        switch height {
        case 2160...: return "4K"
        case 1440..<2160: return "1440p"
        case 1080..<1440: return "1080p"
        case 720..<1080: return "720p"
        case 480..<720: return "480p"
        case 360..<480: return "360p"
        default: return "\(height)p"
        }
    }
    
    // Common presets
    static let p4K = Resolution(width: 3840, height: 2160)
    static let p1440 = Resolution(width: 2560, height: 1440)
    static let p1080 = Resolution(width: 1920, height: 1080)
    static let p720 = Resolution(width: 1280, height: 720)
    static let p480 = Resolution(width: 854, height: 480)
    static let p360 = Resolution(width: 640, height: 360)
}

// MARK: - Media Type

enum MediaType {
    case video
    case audio
    case image
    case unknown
    
    var icon: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        case .image: return "photo"
        case .unknown: return "doc.questionmark"
        }
    }
}

// MARK: - Convenience Initializer

extension MediaFile {
    /// Creates a MediaFile with minimal information (for testing or when probe fails)
    static func basic(url: URL, bookmarkData: Data? = nil) -> MediaFile {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? Int64) ?? 0
        
        return MediaFile(
            id: UUID(),
            url: url,
            filename: url.lastPathComponent,
            fileExtension: url.pathExtension.lowercased(),
            fileSize: fileSize,
            duration: 0,
            videoCodec: nil,
            audioCodec: nil,
            resolution: nil,
            frameRate: nil,
            bitrate: nil,
            audioSampleRate: nil,
            audioChannels: nil,
            bookmarkData: bookmarkData
        )
    }
}

