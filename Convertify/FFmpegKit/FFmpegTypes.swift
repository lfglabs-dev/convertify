//
//  FFmpegTypes.swift
//  Convertify
//
//  Swift wrappers for FFmpeg C types and error handling
//

import Foundation
import Libavcodec
import Libavformat
import Libavutil
import Libswresample
import Libswscale
import Libavfilter

// MARK: - FFmpeg Error Handling

/// Swift error type wrapping FFmpeg error codes
enum FFmpegKitError: LocalizedError {
    case openInputFailed(String, Int32)
    case streamInfoNotFound(String)
    case noVideoStream
    case noAudioStream
    case codecNotFound(String)
    case codecOpenFailed(String, Int32)
    case outputFormatNotFound(String)
    case outputOpenFailed(String, Int32)
    case writeHeaderFailed(Int32)
    case encodingFailed(Int32)
    case decodingFailed(Int32)
    case filterGraphFailed(String)
    case allocationFailed(String)
    case invalidArgument(String)
    case endOfFile
    case cancelled
    case hardwareAccelerationUnavailable
    case noStreamsToMux
    case unknown(Int32)
    
    var errorDescription: String? {
        switch self {
        case .openInputFailed(let path, let code):
            return "Failed to open input file '\(path)': \(ffmpegErrorString(code))"
        case .streamInfoNotFound(let path):
            return "Could not find stream information in '\(path)'"
        case .noVideoStream:
            return "No video stream found in input"
        case .noAudioStream:
            return "No audio stream found in input"
        case .codecNotFound(let name):
            return "Codec '\(name)' not found"
        case .codecOpenFailed(let name, let code):
            return "Failed to open codec '\(name)': \(ffmpegErrorString(code))"
        case .outputFormatNotFound(let ext):
            return "Output format for '\(ext)' not found"
        case .outputOpenFailed(let path, let code):
            return "Failed to open output '\(path)': \(ffmpegErrorString(code))"
        case .writeHeaderFailed(let code):
            return "Failed to write output header: \(ffmpegErrorString(code))"
        case .encodingFailed(let code):
            return "Encoding failed: \(ffmpegErrorString(code))"
        case .decodingFailed(let code):
            return "Decoding failed: \(ffmpegErrorString(code))"
        case .filterGraphFailed(let reason):
            return "Filter graph error: \(reason)"
        case .allocationFailed(let what):
            return "Failed to allocate \(what)"
        case .invalidArgument(let reason):
            return "Invalid argument: \(reason)"
        case .endOfFile:
            return "End of file reached"
        case .cancelled:
            return "Operation was cancelled"
        case .hardwareAccelerationUnavailable:
            return "Hardware acceleration is not available"
        case .noStreamsToMux:
            return "No streams available to write - input may be missing required audio/video"
        case .unknown(let code):
            return "Unknown error: \(ffmpegErrorString(code))"
        }
    }
}

/// Convert FFmpeg error code to readable string
func ffmpegErrorString(_ errorCode: Int32) -> String {
    var buffer = [CChar](repeating: 0, count: 256)
    av_strerror(errorCode, &buffer, 256)
    return String(cString: buffer)
}

/// Check FFmpeg return value and throw if error
func ffmpegCheck(_ ret: Int32, or error: @autoclosure () -> FFmpegKitError) throws {
    if ret < 0 {
        throw error()
    }
}

/// Common FFmpeg error codes
let AVERROR_EOF_VALUE: Int32 = -541478725  // AVERROR_EOF

/// Platform-specific EAGAIN value
/// macOS uses EAGAIN = 35, Linux uses EAGAIN = 11
/// FFmpeg's AVERROR macro negates POSIX error codes
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
let AVERROR_EAGAIN_VALUE: Int32 = -35      // macOS/Darwin EAGAIN
#else
let AVERROR_EAGAIN_VALUE: Int32 = -11      // Linux EAGAIN
#endif

func isAVErrorEOF(_ code: Int32) -> Bool {
    return code == AVERROR_EOF_VALUE || code == -Int32(MKTAG("E", "O", "F", " "))
}

func isAVErrorEAGAIN(_ code: Int32) -> Bool {
    return code == AVERROR_EAGAIN_VALUE
}

/// Create AVERROR from POSIX error
func MKTAG(_ a: Character, _ b: Character, _ c: Character, _ d: Character) -> UInt32 {
    return UInt32(a.asciiValue!) | (UInt32(b.asciiValue!) << 8) | (UInt32(c.asciiValue!) << 16) | (UInt32(d.asciiValue!) << 24)
}

// MARK: - Pixel Format Utilities

extension AVPixelFormat {
    /// Check if this is a hardware pixel format
    var isHardwareFormat: Bool {
        switch self {
        case AV_PIX_FMT_VIDEOTOOLBOX:
            return true
        default:
            return false
        }
    }
    
    /// Get a compatible software pixel format
    var softwareEquivalent: AVPixelFormat {
        switch self {
        case AV_PIX_FMT_VIDEOTOOLBOX:
            return AV_PIX_FMT_NV12
        default:
            return self
        }
    }
}

// MARK: - Codec Utilities

extension AVCodecID {
    /// Get encoder name for this codec ID
    var encoderName: String? {
        guard let codec = avcodec_find_encoder(self) else { return nil }
        return String(cString: codec.pointee.name)
    }
    
    /// Get decoder name for this codec ID
    var decoderName: String? {
        guard let codec = avcodec_find_decoder(self) else { return nil }
        return String(cString: codec.pointee.name)
    }
}

// MARK: - Time Utilities

/// AV_NOPTS_VALUE constant (not available as Swift macro)
let AV_NOPTS_VALUE_SWIFT: Int64 = Int64(bitPattern: 0x8000000000000000)

/// Convert FFmpeg timestamp to seconds
func timestampToSeconds(_ pts: Int64, timeBase: AVRational) -> Double {
    guard pts != AV_NOPTS_VALUE_SWIFT else { return 0 }
    return Double(pts) * Double(timeBase.num) / Double(timeBase.den)
}

/// Convert seconds to FFmpeg timestamp
func secondsToTimestamp(_ seconds: Double, timeBase: AVRational) -> Int64 {
    return Int64(seconds * Double(timeBase.den) / Double(timeBase.num))
}

/// Rescale timestamp between time bases
func rescaleTimestamp(_ pts: Int64, from: AVRational, to: AVRational) -> Int64 {
    return av_rescale_q(pts, from, to)
}

// MARK: - Rational Utilities

extension AVRational {
    /// Convert to Double
    var doubleValue: Double {
        guard den != 0 else { return 0 }
        return Double(num) / Double(den)
    }
    
    /// Create from frame rate
    static func frameRate(_ fps: Double) -> AVRational {
        // Common frame rates
        if abs(fps - 23.976) < 0.01 {
            return AVRational(num: 24000, den: 1001)
        } else if abs(fps - 29.97) < 0.01 {
            return AVRational(num: 30000, den: 1001)
        } else if abs(fps - 59.94) < 0.01 {
            return AVRational(num: 60000, den: 1001)
        } else {
            return AVRational(num: Int32(fps * 1000), den: 1000)
        }
    }
}

// MARK: - Dictionary Utilities

/// Convert Swift dictionary to AVDictionary
func createAVDictionary(_ dict: [String: String]) -> OpaquePointer? {
    var avDict: OpaquePointer? = nil
    for (key, value) in dict {
        av_dict_set(&avDict, key, value, 0)
    }
    return avDict
}

/// Free AVDictionary
func freeAVDictionary(_ dict: inout OpaquePointer?) {
    av_dict_free(&dict)
}

// MARK: - Frame/Packet Memory Management

/// Allocate a new AVFrame
func allocateFrame() -> UnsafeMutablePointer<AVFrame>? {
    return av_frame_alloc()
}

/// Free an AVFrame
func freeFrame(_ frame: inout UnsafeMutablePointer<AVFrame>?) {
    av_frame_free(&frame)
}

/// Allocate a new AVPacket
func allocatePacket() -> UnsafeMutablePointer<AVPacket>? {
    return av_packet_alloc()
}

/// Free an AVPacket
func freePacket(_ packet: inout UnsafeMutablePointer<AVPacket>?) {
    av_packet_free(&packet)
}

// MARK: - Stream Info

/// Information about a media stream
struct StreamInfo {
    let index: Int
    let codecType: AVMediaType
    let codecID: AVCodecID
    let codecName: String
    let timeBase: AVRational
    let duration: Int64
    let bitrate: Int64
    
    // Video specific
    let width: Int32?
    let height: Int32?
    let pixelFormat: AVPixelFormat?
    let frameRate: AVRational?
    
    // Audio specific
    let sampleRate: Int32?
    let channels: Int32?
    let sampleFormat: AVSampleFormat?
    let channelLayout: AVChannelLayout?
    
    init(stream: UnsafeMutablePointer<AVStream>, index: Int) {
        self.index = index
        let codecpar = stream.pointee.codecpar.pointee
        self.codecType = codecpar.codec_type
        self.codecID = codecpar.codec_id
        self.timeBase = stream.pointee.time_base
        self.duration = stream.pointee.duration
        self.bitrate = codecpar.bit_rate
        
        if let codecDesc = avcodec_descriptor_get(codecpar.codec_id) {
            self.codecName = String(cString: codecDesc.pointee.name)
        } else {
            self.codecName = "unknown"
        }
        
        if codecpar.codec_type == AVMEDIA_TYPE_VIDEO {
            self.width = codecpar.width
            self.height = codecpar.height
            self.pixelFormat = AVPixelFormat(rawValue: codecpar.format)
            self.frameRate = stream.pointee.avg_frame_rate
            self.sampleRate = nil
            self.channels = nil
            self.sampleFormat = nil
            self.channelLayout = nil
        } else if codecpar.codec_type == AVMEDIA_TYPE_AUDIO {
            self.width = nil
            self.height = nil
            self.pixelFormat = nil
            self.frameRate = nil
            self.sampleRate = codecpar.sample_rate
            self.channels = codecpar.ch_layout.nb_channels
            self.sampleFormat = AVSampleFormat(rawValue: codecpar.format)
            self.channelLayout = codecpar.ch_layout
        } else {
            self.width = nil
            self.height = nil
            self.pixelFormat = nil
            self.frameRate = nil
            self.sampleRate = nil
            self.channels = nil
            self.sampleFormat = nil
            self.channelLayout = nil
        }
    }
}

// MARK: - Transcoding Configuration

/// Configuration for a transcoding operation
struct TranscodingConfig {
    // Input
    let inputPath: String
    
    // Output
    let outputPath: String
    let outputFormat: String  // e.g., "mp4", "mov", "mp3"
    
    // Video settings
    var videoCodec: String?  // e.g., "libx264", "h264_videotoolbox"
    var videoBitrate: Int64?
    var videoCRF: Int?
    var width: Int32?
    var height: Int32?
    var frameRate: Double?
    var pixelFormat: AVPixelFormat?
    
    // Audio settings
    var audioCodec: String?  // e.g., "aac", "libmp3lame"
    var audioBitrate: Int64?
    var sampleRate: Int32?
    var audioChannels: Int32?
    
    // Trimming
    var startTime: Double?
    var endTime: Double?
    
    // Filters
    var videoFilters: [String] = []
    var audioFilters: [String] = []
    
    // Options
    var useHardwareAcceleration: Bool = true
    var copyVideo: Bool = false
    var copyAudio: Bool = false
    var stripVideo: Bool = false
    var stripAudio: Bool = false
    
    // Metadata
    var metadata: [String: String] = [:]
    
    init(inputPath: String, outputPath: String, outputFormat: String) {
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.outputFormat = outputFormat
    }
}

// MARK: - Progress Reporting

/// Progress information during transcoding
struct TranscodingProgress {
    var currentTime: TimeInterval = 0
    var totalDuration: TimeInterval = 0
    var percentage: Double = 0
    var speed: Double = 0
    var frame: Int = 0
    var fps: Double = 0
    var bitrate: Int64 = 0
    var size: Int64 = 0
}

/// Protocol for receiving progress updates
protocol TranscodingProgressDelegate: AnyObject {
    func transcodingDidUpdateProgress(_ progress: TranscodingProgress)
    func transcodingDidComplete()
    func transcodingDidFail(with error: Error)
}

