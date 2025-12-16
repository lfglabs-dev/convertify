//
//  OutputFormat.swift
//  Convertify
//
//  Supported output formats for conversion
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum OutputFormat: String, CaseIterable, Identifiable {
    // Video formats
    case mp4 = "MP4"
    case mov = "MOV"
    case mkv = "MKV"
    case webm = "WebM"
    case avi = "AVI"
    case gif = "GIF"
    
    // Audio formats
    case mp3 = "MP3"
    case aac = "AAC"
    case wav = "WAV"
    case flac = "FLAC"
    case ogg = "OGG"
    case m4a = "M4A"
    
    // Image formats
    case jpg = "JPEG"
    case png = "PNG"
    case webp = "WebP"
    case heic = "HEIC"
    case tiff = "TIFF"
    case bmp = "BMP"
    case ico = "ICO"
    
    var id: String { rawValue }
    
    /// UTType for NSSavePanel file type restrictions
    var utType: UTType {
        switch self {
        case .mp4: return .mpeg4Movie
        case .mov: return .quickTimeMovie
        case .mkv: return UTType(filenameExtension: "mkv") ?? .movie
        case .webm: return UTType(filenameExtension: "webm") ?? .movie
        case .avi: return .avi
        case .gif: return .gif
        case .mp3: return .mp3
        case .aac: return UTType(filenameExtension: "aac") ?? .audio
        case .wav: return .wav
        case .flac: return UTType(filenameExtension: "flac") ?? .audio
        case .ogg: return UTType(filenameExtension: "ogg") ?? .audio
        case .m4a: return UTType(filenameExtension: "m4a") ?? .audio
        case .jpg: return .jpeg
        case .png: return .png
        case .webp: return .webP
        case .heic: return .heic
        case .tiff: return .tiff
        case .bmp: return .bmp
        case .ico: return .ico
        }
    }
    
    var fileExtension: String {
        switch self {
        case .mp4: return "mp4"
        case .mov: return "mov"
        case .mkv: return "mkv"
        case .webm: return "webm"
        case .avi: return "avi"
        case .gif: return "gif"
        case .mp3: return "mp3"
        case .aac: return "aac"
        case .wav: return "wav"
        case .flac: return "flac"
        case .ogg: return "ogg"
        case .m4a: return "m4a"
        case .jpg: return "jpg"
        case .png: return "png"
        case .webp: return "webp"
        case .heic: return "heic"
        case .tiff: return "tiff"
        case .bmp: return "bmp"
        case .ico: return "ico"
        }
    }
    
    var formatType: FormatType {
        switch self {
        case .mp4, .mov, .mkv, .webm, .avi, .gif:
            return .video
        case .mp3, .aac, .wav, .flac, .ogg, .m4a:
            return .audio
        case .jpg, .png, .webp, .heic, .tiff, .bmp, .ico:
            return .image
        }
    }
    
    var isVideoFormat: Bool { formatType == .video }
    var isAudioFormat: Bool { formatType == .audio }
    var isImageFormat: Bool { formatType == .image }
    
    var icon: String {
        switch formatType {
        case .video: return "film"
        case .audio: return "waveform"
        case .image: return "photo"
        }
    }
    
    var color: Color {
        switch formatType {
        case .video: return Color(hex: "3B82F6")
        case .audio: return Color(hex: "F97316")
        case .image: return Color(hex: "22C55E")
        }
    }
    
    var description: String {
        switch self {
        case .mp4: return "Most compatible video format"
        case .mov: return "Apple QuickTime format"
        case .mkv: return "Flexible container, great for archiving"
        case .webm: return "Web-optimized video"
        case .avi: return "Legacy video format"
        case .gif: return "Animated image (no audio)"
        case .mp3: return "Universal audio format"
        case .aac: return "High-quality compressed audio"
        case .wav: return "Uncompressed audio"
        case .flac: return "Lossless audio compression"
        case .ogg: return "Open source audio format"
        case .m4a: return "Apple audio format"
        case .jpg: return "Universal image format"
        case .png: return "Lossless with transparency"
        case .webp: return "Modern web image format"
        case .heic: return "Apple high efficiency format"
        case .tiff: return "High quality, large files"
        case .bmp: return "Uncompressed bitmap"
        case .ico: return "Icon format for apps/web"
        }
    }
    
    var defaultVideoCodec: VideoCodec {
        switch self {
        case .mp4, .mov, .m4a: return .h264
        case .mkv, .avi: return .h264
        case .webm: return .vp9
        case .gif: return .gif
        default: return .none
        }
    }
    
    var defaultAudioCodec: String {
        switch self {
        case .mp4, .mov, .m4a, .mkv: return "aac"
        case .webm, .ogg: return "libopus"
        case .avi: return "mp3"
        case .gif: return "none"
        case .mp3: return "mp3"
        case .aac: return "aac"
        case .wav: return "pcm_s16le"
        case .flac: return "flac"
        default: return "none"
        }
    }
    
    var supportsHardwareAcceleration: Bool {
        switch self {
        case .mp4, .mov, .mkv, .avi:
            return true
        default:
            return false
        }
    }
    
    var supportsQualitySlider: Bool {
        switch self {
        case .jpg, .webp, .heic:
            return true
        default:
            return false
        }
    }
    
    // Group formats for picker
    // Note: GIF is excluded because the bundled FFmpegKit doesn't include the GIF muxer.
    // WebM is also excluded as libvpx may not be available.
    static var videoFormats: [OutputFormat] {
        [.mp4, .mov, .mkv, .avi]
    }
    
    static var audioFormats: [OutputFormat] {
        // Keep this list in sync with what the bundled libavformat can actually mux.
        // (mp3/wav/ogg muxers are not present in our App Store–compatible build.)
        [.m4a, .aac, .flac]
    }
    
    static var imageFormats: [OutputFormat] {
        [.jpg, .png, .webp, .heic, .tiff, .bmp, .ico]
    }
}

// MARK: - Format Type

enum FormatType: String {
    case video = "Video"
    case audio = "Audio"
    case image = "Image"
    
    var icon: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        case .image: return "photo"
        }
    }
    
    var color: Color {
        switch self {
        case .video: return Color(hex: "3B82F6")
        case .audio: return Color(hex: "F97316")
        case .image: return Color(hex: "22C55E")
        }
    }
}

// MARK: - Video Codec

enum VideoCodec: String {
    case h264 = "H.264"
    case h265 = "H.265/HEVC"
    case vp9 = "VP9"
    case av1 = "AV1"
    case gif = "GIF"
    case none = "None"
    
    var ffmpegCodec: String {
        switch self {
        case .h264: return "libx264"
        case .h265: return "libx265"
        case .vp9: return "libvpx-vp9"
        case .av1: return "libaom-av1"
        case .gif: return "gif"
        case .none: return ""
        }
    }
    
    var hardwareAcceleratedCodec: String? {
        switch self {
        case .h264: return "h264_videotoolbox"
        case .h265: return "hevc_videotoolbox"
        default: return nil
        }
    }
}

