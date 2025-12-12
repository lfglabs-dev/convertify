//
//  HardwareAcceleration.swift
//  Convertify
//
//  VideoToolbox hardware acceleration integration for FFmpeg
//

import Foundation
import Libavcodec
import Libavformat
import Libavutil

// MARK: - Hardware Acceleration Manager

/// Manages VideoToolbox hardware acceleration for encoding and decoding
final class HardwareAccelerationManager {
    
    // MARK: - Properties
    
    private var hwDeviceContext: UnsafeMutablePointer<AVBufferRef>?
    private var hwFramesContext: UnsafeMutablePointer<AVBufferRef>?
    
    /// Whether VideoToolbox is available on this system
    static var isVideoToolboxAvailable: Bool {
        // Check if VideoToolbox encoder exists
        return avcodec_find_encoder_by_name("h264_videotoolbox") != nil
    }
    
    /// Supported hardware encoders
    static var supportedEncoders: [String] {
        var encoders: [String] = []
        if avcodec_find_encoder_by_name("h264_videotoolbox") != nil {
            encoders.append("h264_videotoolbox")
        }
        if avcodec_find_encoder_by_name("hevc_videotoolbox") != nil {
            encoders.append("hevc_videotoolbox")
        }
        return encoders
    }
    
    /// Supported hardware decoders
    static var supportedDecoders: [String] {
        var decoders: [String] = []
        if avcodec_find_decoder_by_name("h264_videotoolbox") != nil {
            decoders.append("h264_videotoolbox")
        }
        if avcodec_find_decoder_by_name("hevc_videotoolbox") != nil {
            decoders.append("hevc_videotoolbox")
        }
        return decoders
    }
    
    // MARK: - Initialization
    
    init() {}
    
    deinit {
        cleanup()
    }
    
    // MARK: - Hardware Context Setup
    
    /// Initialize hardware device context for VideoToolbox
    func initializeHardwareContext() throws {
        var deviceCtx: UnsafeMutablePointer<AVBufferRef>? = nil
        
        let ret = av_hwdevice_ctx_create(&deviceCtx, AV_HWDEVICE_TYPE_VIDEOTOOLBOX, nil, nil, 0)
        guard ret >= 0, deviceCtx != nil else {
            throw FFmpegKitError.hardwareAccelerationUnavailable
        }
        
        hwDeviceContext = deviceCtx
    }
    
    /// Get the hardware device context
    var deviceContext: UnsafeMutablePointer<AVBufferRef>? {
        return hwDeviceContext
    }
    
    /// Setup hardware frames context for a decoder
    func setupHardwareFramesContext(decoderContext: UnsafeMutablePointer<AVCodecContext>,
                                    pixelFormat: AVPixelFormat) throws {
        guard let deviceCtx = hwDeviceContext else {
            throw FFmpegKitError.hardwareAccelerationUnavailable
        }
        
        // Allocate hardware frames context
        guard let framesRef = av_hwframe_ctx_alloc(deviceCtx) else {
            throw FFmpegKitError.allocationFailed("hardware frames context")
        }
        
        let framesCtx = UnsafeMutableRawPointer(framesRef.pointee.data)
            .bindMemory(to: AVHWFramesContext.self, capacity: 1)
        
        framesCtx.pointee.format = AV_PIX_FMT_VIDEOTOOLBOX
        framesCtx.pointee.sw_format = pixelFormat
        framesCtx.pointee.width = decoderContext.pointee.width
        framesCtx.pointee.height = decoderContext.pointee.height
        framesCtx.pointee.initial_pool_size = 20
        
        let ret = av_hwframe_ctx_init(framesRef)
        guard ret >= 0 else {
            av_buffer_unref(&framesRef)
            throw FFmpegKitError.allocationFailed("hardware frames context init")
        }
        
        hwFramesContext = framesRef
        decoderContext.pointee.hw_frames_ctx = av_buffer_ref(framesRef)
    }
    
    // MARK: - Encoder Configuration
    
    /// Configure encoder context for hardware acceleration
    func configureEncoderForHardware(encoderContext: UnsafeMutablePointer<AVCodecContext>,
                                     codecName: String) throws {
        guard let deviceCtx = hwDeviceContext else {
            throw FFmpegKitError.hardwareAccelerationUnavailable
        }
        
        // Set hardware device context on encoder
        encoderContext.pointee.hw_device_ctx = av_buffer_ref(deviceCtx)
        
        // VideoToolbox specific settings
        if codecName.contains("videotoolbox") {
            // Use VT's internal rate control
            encoderContext.pointee.rc_buffer_size = 0
            
            // Enable B-frames for H.264
            if codecName == "h264_videotoolbox" {
                // B-frames improve compression but need proper setup
                // Set via codec options instead
            }
        }
    }
    
    /// Get the best hardware encoder for a codec ID
    static func getHardwareEncoder(for codecID: AVCodecID) -> String? {
        switch codecID {
        case AV_CODEC_ID_H264:
            if avcodec_find_encoder_by_name("h264_videotoolbox") != nil {
                return "h264_videotoolbox"
            }
        case AV_CODEC_ID_HEVC:
            if avcodec_find_encoder_by_name("hevc_videotoolbox") != nil {
                return "hevc_videotoolbox"
            }
        default:
            break
        }
        return nil
    }
    
    /// Get the software fallback encoder for a codec ID
    static func getSoftwareEncoder(for codecID: AVCodecID) -> String? {
        switch codecID {
        case AV_CODEC_ID_H264:
            return "libx264"
        case AV_CODEC_ID_HEVC:
            return "libx265"
        case AV_CODEC_ID_VP9:
            return "libvpx-vp9"
        case AV_CODEC_ID_AV1:
            return "libaom-av1"
        default:
            return nil
        }
    }
    
    // MARK: - Frame Transfer
    
    /// Transfer hardware frame to software frame
    func transferHardwareFrame(_ hwFrame: UnsafeMutablePointer<AVFrame>,
                               to swFrame: UnsafeMutablePointer<AVFrame>) throws {
        let ret = av_hwframe_transfer_data(swFrame, hwFrame, 0)
        guard ret >= 0 else {
            throw FFmpegKitError.decodingFailed(ret)
        }
        
        swFrame.pointee.pts = hwFrame.pointee.pts
    }
    
    /// Check if a frame is a hardware frame
    static func isHardwareFrame(_ frame: UnsafeMutablePointer<AVFrame>) -> Bool {
        return frame.pointee.format == AV_PIX_FMT_VIDEOTOOLBOX.rawValue
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        if hwFramesContext != nil {
            av_buffer_unref(&hwFramesContext)
        }
        if hwDeviceContext != nil {
            av_buffer_unref(&hwDeviceContext)
        }
    }
}

// MARK: - Pixel Format Helpers

extension HardwareAccelerationManager {
    
    /// Get the software pixel format for a hardware format
    static func getSoftwarePixelFormat(for hwFormat: AVPixelFormat) -> AVPixelFormat {
        if hwFormat == AV_PIX_FMT_VIDEOTOOLBOX {
            return AV_PIX_FMT_NV12
        }
        return hwFormat
    }
    
    /// Check if pixel format is compatible with VideoToolbox
    static func isCompatibleWithVideoToolbox(_ pixelFormat: AVPixelFormat) -> Bool {
        switch pixelFormat {
        case AV_PIX_FMT_NV12, AV_PIX_FMT_YUV420P, AV_PIX_FMT_P010LE, AV_PIX_FMT_VIDEOTOOLBOX:
            return true
        default:
            return false
        }
    }
}

// MARK: - Codec Selection

/// Helper to select the best encoder based on hardware availability
struct EncoderSelector {
    
    /// Select the best encoder for the given output format
    static func selectEncoder(for outputFormat: String,
                             preferHardware: Bool = true) -> (encoder: String, isHardware: Bool) {
        let format = outputFormat.lowercased()
        
        switch format {
        case "mp4", "mov", "m4v":
            if preferHardware && HardwareAccelerationManager.isVideoToolboxAvailable {
                return ("h264_videotoolbox", true)
            }
            return ("libx264", false)
            
        case "mkv":
            if preferHardware && HardwareAccelerationManager.isVideoToolboxAvailable {
                return ("h264_videotoolbox", true)
            }
            return ("libx264", false)
            
        case "webm":
            // VP9 doesn't have VideoToolbox support
            return ("libvpx-vp9", false)
            
        case "gif":
            return ("gif", false)
            
        case "hevc", "heic":
            if preferHardware && HardwareAccelerationManager.supportedEncoders.contains("hevc_videotoolbox") {
                return ("hevc_videotoolbox", true)
            }
            return ("libx265", false)
            
        default:
            return ("libx264", false)
        }
    }
    
    /// Get encoder options for quality settings
    static func getEncoderOptions(encoder: String,
                                  bitrate: Int64?,
                                  crf: Int?) -> [String: String] {
        var options: [String: String] = [:]
        
        if encoder.contains("videotoolbox") {
            // VideoToolbox options
            if let br = bitrate {
                options["b:v"] = String(br)
            }
            // VT uses different quality control
            options["allow_sw"] = "0"  // Don't fall back to software
            options["realtime"] = "0"  // Non-realtime for better quality
        } else if encoder == "libx264" || encoder == "libx265" {
            // x264/x265 options
            options["preset"] = "medium"
            if let c = crf {
                options["crf"] = String(c)
            } else if let br = bitrate {
                options["b:v"] = String(br)
            }
        } else if encoder == "libvpx-vp9" {
            // VP9 options
            if let c = crf {
                options["crf"] = String(c)
                options["b:v"] = "0"  // CRF mode
            }
            options["row-mt"] = "1"  // Row-based multithreading
        }
        
        return options
    }
}

