//
//  TranscodingPipeline.swift
//  Convertify
//
//  Core transcoding engine using FFmpeg's libav* APIs
//

import Foundation
import Libavformat
import Libavcodec
import Libavutil
import Libswresample
import Libswscale
import Libavfilter

// MARK: - Transcoding Pipeline

/// Core transcoding engine that handles demux -> decode -> [filter] -> encode -> mux
final class TranscodingPipeline {
    
    // MARK: - Properties
    
    private var inputFormatContext: UnsafeMutablePointer<AVFormatContext>?
    private var outputFormatContext: UnsafeMutablePointer<AVFormatContext>?
    
    private var videoDecoderContext: UnsafeMutablePointer<AVCodecContext>?
    private var audioDecoderContext: UnsafeMutablePointer<AVCodecContext>?
    private var videoEncoderContext: UnsafeMutablePointer<AVCodecContext>?
    private var audioEncoderContext: UnsafeMutablePointer<AVCodecContext>?
    
    private var videoFilterGraph: UnsafeMutablePointer<AVFilterGraph>?
    private var videoBufferSrcContext: UnsafeMutablePointer<AVFilterContext>?
    private var videoBufferSinkContext: UnsafeMutablePointer<AVFilterContext>?
    
    private var audioFilterGraph: UnsafeMutablePointer<AVFilterGraph>?
    private var audioBufferSrcContext: UnsafeMutablePointer<AVFilterContext>?
    private var audioBufferSinkContext: UnsafeMutablePointer<AVFilterContext>?
    
    private var swsContext: OpaquePointer?
    private var swrContext: OpaquePointer?
    
    private var videoStreamIndex: Int32 = -1
    private var audioStreamIndex: Int32 = -1
    private var outputVideoStreamIndex: Int32 = -1
    private var outputAudioStreamIndex: Int32 = -1
    
    private var inputDuration: Int64 = 0
    private var startPts: Int64 = 0
    private var endPts: Int64 = Int64.max
    
    private let config: TranscodingConfig
    private var shouldStop = false
    private var progressCallback: ((TranscodingProgress) -> Void)?
    
    // Hardware acceleration
    private var hwDeviceContext: UnsafeMutablePointer<AVBufferRef>?
    private var useHardwareDecoding = false
    private var useHardwareEncoding = false
    
    // MARK: - Initialization
    
    init(config: TranscodingConfig) {
        self.config = config
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Public Methods
    
    /// Start transcoding with progress callback
    func transcode(progress: @escaping (TranscodingProgress) -> Void) throws {
        self.progressCallback = progress
        self.shouldStop = false
        
        defer { cleanup() }
        
        try openInput()
        try openOutput()
        try setupStreams()
        try writeHeader()
        try processFrames()
        try writeTrailer()
    }
    
    /// Cancel the transcoding operation
    func cancel() {
        shouldStop = true
    }
    
    // MARK: - Input Setup
    
    private func openInput() throws {
        var ret: Int32 = 0
        
        // Open input file
        ret = avformat_open_input(&inputFormatContext, config.inputPath, nil, nil)
        guard ret >= 0, let ctx = inputFormatContext else {
            throw FFmpegKitError.openInputFailed(config.inputPath, ret)
        }
        
        // Find stream info
        ret = avformat_find_stream_info(ctx, nil)
        guard ret >= 0 else {
            throw FFmpegKitError.streamInfoNotFound(config.inputPath)
        }
        
        // Store duration for progress
        inputDuration = ctx.pointee.duration
        
        // Find video and audio streams
        for i in 0..<Int32(ctx.pointee.nb_streams) {
            let stream = ctx.pointee.streams[Int(i)]!
            let codecType = stream.pointee.codecpar.pointee.codec_type
            
            if codecType == AVMEDIA_TYPE_VIDEO && videoStreamIndex < 0 && !config.stripVideo {
                videoStreamIndex = i
            } else if codecType == AVMEDIA_TYPE_AUDIO && audioStreamIndex < 0 && !config.stripAudio {
                audioStreamIndex = i
            }
        }
        
        // Setup decoders
        if videoStreamIndex >= 0 {
            try setupVideoDecoder()
        }
        
        if audioStreamIndex >= 0 {
            try setupAudioDecoder()
        }
        
        // Calculate seek positions for trimming
        if let startTime = config.startTime {
            startPts = Int64(startTime * Double(AV_TIME_BASE))
            
            // Seek to start position
            ret = av_seek_frame(ctx, -1, startPts, AVSEEK_FLAG_BACKWARD)
            if ret < 0 {
                // Seek failed, will start from beginning
                startPts = 0
            }
        }
        
        if let endTime = config.endTime {
            endPts = Int64(endTime * Double(AV_TIME_BASE))
        }
    }
    
    private func setupVideoDecoder() throws {
        guard let ctx = inputFormatContext else { return }
        let stream = ctx.pointee.streams[Int(videoStreamIndex)]!
        guard let codecpar = stream.pointee.codecpar else { return }
        
        // Find decoder
        guard let decoder = avcodec_find_decoder(codecpar.pointee.codec_id) else {
            throw FFmpegKitError.codecNotFound("video decoder")
        }
        
        // Allocate decoder context
        guard let decoderCtx = avcodec_alloc_context3(decoder) else {
            throw FFmpegKitError.allocationFailed("video decoder context")
        }
        videoDecoderContext = decoderCtx
        
        // Copy codec parameters
        var ret = avcodec_parameters_to_context(decoderCtx, codecpar)
        guard ret >= 0 else {
            throw FFmpegKitError.codecOpenFailed("video decoder", ret)
        }
        
        // Set threading
        decoderCtx.pointee.thread_count = 0  // Auto-detect
        
        // Open decoder
        ret = avcodec_open2(decoderCtx, decoder, nil)
        guard ret >= 0 else {
            throw FFmpegKitError.codecOpenFailed("video decoder", ret)
        }
    }
    
    private func setupAudioDecoder() throws {
        guard let ctx = inputFormatContext else { return }
        let stream = ctx.pointee.streams[Int(audioStreamIndex)]!
        guard let codecpar = stream.pointee.codecpar else { return }
        
        // Find decoder
        guard let decoder = avcodec_find_decoder(codecpar.pointee.codec_id) else {
            throw FFmpegKitError.codecNotFound("audio decoder")
        }
        
        // Allocate decoder context
        guard let decoderCtx = avcodec_alloc_context3(decoder) else {
            throw FFmpegKitError.allocationFailed("audio decoder context")
        }
        audioDecoderContext = decoderCtx
        
        // Copy codec parameters
        var ret = avcodec_parameters_to_context(decoderCtx, codecpar)
        guard ret >= 0 else {
            throw FFmpegKitError.codecOpenFailed("audio decoder", ret)
        }
        
        // Open decoder
        ret = avcodec_open2(decoderCtx, decoder, nil)
        guard ret >= 0 else {
            throw FFmpegKitError.codecOpenFailed("audio decoder", ret)
        }
    }
    
    // MARK: - Output Setup
    
    private func openOutput() throws {
        var ret: Int32 = 0
        
        // Allocate output format context
        ret = avformat_alloc_output_context2(&outputFormatContext, nil, nil, config.outputPath)
        guard ret >= 0, let outCtx = outputFormatContext else {
            throw FFmpegKitError.outputFormatNotFound(config.outputFormat)
        }
        
        // Open output file if not a format that writes to memory
        if outCtx.pointee.oformat.pointee.flags & AVFMT_NOFILE == 0 {
            ret = avio_open(&outCtx.pointee.pb, config.outputPath, AVIO_FLAG_WRITE)
            guard ret >= 0 else {
                throw FFmpegKitError.outputOpenFailed(config.outputPath, ret)
            }
        }
    }
    
    private func setupStreams() throws {
        // Setup video encoder if we have video input and want video output
        if videoStreamIndex >= 0 && !config.stripVideo {
            try setupVideoEncoder()
        }
        
        // Setup audio encoder if we have audio input and want audio output
        if audioStreamIndex >= 0 && !config.stripAudio {
            try setupAudioEncoder()
        }
    }
    
    private func setupVideoEncoder() throws {
        guard let outCtx = outputFormatContext,
              let inCtx = inputFormatContext,
              let decoderCtx = videoDecoderContext else { return }
        
        let inputStream = inCtx.pointee.streams[Int(videoStreamIndex)]!
        
        // Determine encoder
        let encoderName: String
        if config.copyVideo {
            // Stream copy - no encoding needed
            guard let outStream = avformat_new_stream(outCtx, nil) else {
                throw FFmpegKitError.allocationFailed("output video stream")
            }
            outputVideoStreamIndex = Int32(outCtx.pointee.nb_streams - 1)
            
            let ret = avcodec_parameters_copy(outStream.pointee.codecpar, inputStream.pointee.codecpar)
            guard ret >= 0 else {
                throw FFmpegKitError.allocationFailed("codec parameters copy")
            }
            outStream.pointee.codecpar.pointee.codec_tag = 0
            return
        }
        
        if let codecName = config.videoCodec {
            encoderName = codecName
        } else {
            // Default based on output format
            encoderName = getDefaultVideoEncoder()
        }
        
        // Find encoder
        guard let encoder = avcodec_find_encoder_by_name(encoderName) else {
            throw FFmpegKitError.codecNotFound(encoderName)
        }
        
        // Create output stream
        guard let outStream = avformat_new_stream(outCtx, encoder) else {
            throw FFmpegKitError.allocationFailed("output video stream")
        }
        outputVideoStreamIndex = Int32(outCtx.pointee.nb_streams - 1)
        
        // Allocate encoder context
        guard let encoderCtx = avcodec_alloc_context3(encoder) else {
            throw FFmpegKitError.allocationFailed("video encoder context")
        }
        videoEncoderContext = encoderCtx
        
        // Configure encoder
        let targetWidth = config.width ?? decoderCtx.pointee.width
        let targetHeight = config.height ?? decoderCtx.pointee.height
        
        encoderCtx.pointee.width = targetWidth
        encoderCtx.pointee.height = targetHeight
        encoderCtx.pointee.sample_aspect_ratio = decoderCtx.pointee.sample_aspect_ratio
        
        // Pixel format
        if let pixFmt = config.pixelFormat {
            encoderCtx.pointee.pix_fmt = pixFmt
        } else if let supportedFormats = encoder.pointee.pix_fmts {
            encoderCtx.pointee.pix_fmt = supportedFormats.pointee
        } else {
            encoderCtx.pointee.pix_fmt = AV_PIX_FMT_YUV420P
        }
        
        // Time base and frame rate
        if let fps = config.frameRate {
            encoderCtx.pointee.time_base = AVRational(num: 1, den: Int32(fps))
            encoderCtx.pointee.framerate = AVRational(num: Int32(fps), den: 1)
        } else {
            encoderCtx.pointee.time_base = av_inv_q(inputStream.pointee.avg_frame_rate)
            encoderCtx.pointee.framerate = inputStream.pointee.avg_frame_rate
        }
        
        // Bitrate / quality
        if let bitrate = config.videoBitrate {
            encoderCtx.pointee.bit_rate = bitrate
        }
        // CRF will be handled when opening encoder below
        
        // Threading
        encoderCtx.pointee.thread_count = 0
        
        // Global header for certain formats
        if outCtx.pointee.oformat.pointee.flags & AVFMT_GLOBALHEADER != 0 {
            encoderCtx.pointee.flags |= AV_CODEC_FLAG_GLOBAL_HEADER
        }
        
        // Open encoder
        var opts: OpaquePointer? = nil
        if let crf = config.videoCRF {
            av_dict_set(&opts, "crf", String(crf), 0)
        }
        
        // Preset for x264/x265
        if encoderName == "libx264" || encoderName == "libx265" {
            av_dict_set(&opts, "preset", "medium", 0)
        }
        
        var ret = avcodec_open2(encoderCtx, encoder, &opts)
        av_dict_free(&opts)
        
        guard ret >= 0 else {
            throw FFmpegKitError.codecOpenFailed(encoderName, ret)
        }
        
        // Copy encoder parameters to output stream
        ret = avcodec_parameters_from_context(outStream.pointee.codecpar, encoderCtx)
        guard ret >= 0 else {
            throw FFmpegKitError.allocationFailed("codec parameters from context")
        }
        
        outStream.pointee.time_base = encoderCtx.pointee.time_base
        
        // Setup video filters if needed
        try setupVideoFilters()
    }
    
    private func setupAudioEncoder() throws {
        guard let outCtx = outputFormatContext,
              let inCtx = inputFormatContext,
              let decoderCtx = audioDecoderContext else { return }
        
        let inputStream = inCtx.pointee.streams[Int(audioStreamIndex)]!
        
        // Determine encoder
        let encoderName: String
        if config.copyAudio {
            // Stream copy
            guard let outStream = avformat_new_stream(outCtx, nil) else {
                throw FFmpegKitError.allocationFailed("output audio stream")
            }
            outputAudioStreamIndex = Int32(outCtx.pointee.nb_streams - 1)
            
            let ret = avcodec_parameters_copy(outStream.pointee.codecpar, inputStream.pointee.codecpar)
            guard ret >= 0 else {
                throw FFmpegKitError.allocationFailed("codec parameters copy")
            }
            outStream.pointee.codecpar.pointee.codec_tag = 0
            return
        }
        
        if let codecName = config.audioCodec {
            encoderName = codecName
        } else {
            encoderName = getDefaultAudioEncoder()
        }
        
        // Find encoder
        guard let encoder = avcodec_find_encoder_by_name(encoderName) else {
            throw FFmpegKitError.codecNotFound(encoderName)
        }
        
        // Create output stream
        guard let outStream = avformat_new_stream(outCtx, encoder) else {
            throw FFmpegKitError.allocationFailed("output audio stream")
        }
        outputAudioStreamIndex = Int32(outCtx.pointee.nb_streams - 1)
        
        // Allocate encoder context
        guard let encoderCtx = avcodec_alloc_context3(encoder) else {
            throw FFmpegKitError.allocationFailed("audio encoder context")
        }
        audioEncoderContext = encoderCtx
        
        // Configure encoder
        encoderCtx.pointee.sample_rate = config.sampleRate ?? decoderCtx.pointee.sample_rate
        encoderCtx.pointee.ch_layout = decoderCtx.pointee.ch_layout
        
        if let channels = config.audioChannels {
            av_channel_layout_default(&encoderCtx.pointee.ch_layout, channels)
        }
        
        // Sample format
        if let supportedFormats = encoder.pointee.sample_fmts {
            encoderCtx.pointee.sample_fmt = supportedFormats.pointee
        } else {
            encoderCtx.pointee.sample_fmt = AV_SAMPLE_FMT_FLTP
        }
        
        // Bitrate
        if let bitrate = config.audioBitrate {
            encoderCtx.pointee.bit_rate = bitrate
        } else {
            encoderCtx.pointee.bit_rate = 128000  // Default 128kbps
        }
        
        // Time base
        encoderCtx.pointee.time_base = AVRational(num: 1, den: encoderCtx.pointee.sample_rate)
        
        // Global header
        if outCtx.pointee.oformat.pointee.flags & AVFMT_GLOBALHEADER != 0 {
            encoderCtx.pointee.flags |= AV_CODEC_FLAG_GLOBAL_HEADER
        }
        
        // Open encoder
        var ret = avcodec_open2(encoderCtx, encoder, nil)
        guard ret >= 0 else {
            throw FFmpegKitError.codecOpenFailed(encoderName, ret)
        }
        
        // Copy parameters to output stream
        ret = avcodec_parameters_from_context(outStream.pointee.codecpar, encoderCtx)
        guard ret >= 0 else {
            throw FFmpegKitError.allocationFailed("codec parameters from context")
        }
        
        outStream.pointee.time_base = encoderCtx.pointee.time_base
        
        // Setup audio resampler if needed
        try setupAudioResampler()
    }
    
    // MARK: - Filters
    
    private func setupVideoFilters() throws {
        guard let decoderCtx = videoDecoderContext,
              let encoderCtx = videoEncoderContext else { return }
        
        // Build filter string from config
        var filters: [String] = config.videoFilters
        
        // Add scale filter if dimensions differ
        let needsScale = decoderCtx.pointee.width != encoderCtx.pointee.width ||
                         decoderCtx.pointee.height != encoderCtx.pointee.height
        
        if needsScale {
            filters.append("scale=\(encoderCtx.pointee.width):\(encoderCtx.pointee.height)")
        }
        
        // Add format filter for pixel format conversion
        if decoderCtx.pointee.pix_fmt != encoderCtx.pointee.pix_fmt {
            let fmtName = String(cString: av_get_pix_fmt_name(encoderCtx.pointee.pix_fmt))
            filters.append("format=\(fmtName)")
        }
        
        // If no filters needed, don't create filter graph
        guard !filters.isEmpty else { return }
        
        let filterString = filters.joined(separator: ",")
        try createVideoFilterGraph(filterString: filterString)
    }
    
    private func createVideoFilterGraph(filterString: String) throws {
        guard let decoderCtx = videoDecoderContext,
              let encoderCtx = videoEncoderContext,
              let inCtx = inputFormatContext else { return }
        
        let inputStream = inCtx.pointee.streams[Int(videoStreamIndex)]!
        
        // Allocate filter graph
        guard let graph = avfilter_graph_alloc() else {
            throw FFmpegKitError.allocationFailed("filter graph")
        }
        videoFilterGraph = graph
        
        // Create buffer source
        guard let bufferSrc = avfilter_get_by_name("buffer") else {
            throw FFmpegKitError.filterGraphFailed("buffer filter not found")
        }
        
        let timeBase = inputStream.pointee.time_base
        let pixFmtName = String(cString: av_get_pix_fmt_name(decoderCtx.pointee.pix_fmt))
        let srcArgs = "video_size=\(decoderCtx.pointee.width)x\(decoderCtx.pointee.height):pix_fmt=\(pixFmtName):time_base=\(timeBase.num)/\(timeBase.den):pixel_aspect=\(decoderCtx.pointee.sample_aspect_ratio.num)/\(max(1, decoderCtx.pointee.sample_aspect_ratio.den))"
        
        var ret = avfilter_graph_create_filter(&videoBufferSrcContext, bufferSrc, "in", srcArgs, nil, graph)
        guard ret >= 0 else {
            throw FFmpegKitError.filterGraphFailed("failed to create buffer source")
        }
        
        // Create buffer sink
        guard let bufferSink = avfilter_get_by_name("buffersink") else {
            throw FFmpegKitError.filterGraphFailed("buffersink filter not found")
        }
        
        ret = avfilter_graph_create_filter(&videoBufferSinkContext, bufferSink, "out", nil, nil, graph)
        guard ret >= 0 else {
            throw FFmpegKitError.filterGraphFailed("failed to create buffer sink")
        }
        
        // Set output pixel format
        var pixFmts: [AVPixelFormat] = [encoderCtx.pointee.pix_fmt, AVPixelFormat(rawValue: -1)]
        ret = av_opt_set_bin(videoBufferSinkContext, "pix_fmts",
                            &pixFmts, Int32(MemoryLayout<AVPixelFormat>.size * pixFmts.count),
                            AV_OPT_SEARCH_CHILDREN)
        guard ret >= 0 else {
            throw FFmpegKitError.filterGraphFailed("failed to set output pixel format")
        }
        
        // Parse and link filter graph
        var outputs = avfilter_inout_alloc()
        var inputs = avfilter_inout_alloc()
        
        defer {
            avfilter_inout_free(&outputs)
            avfilter_inout_free(&inputs)
        }
        
        outputs?.pointee.name = av_strdup("in")
        outputs?.pointee.filter_ctx = videoBufferSrcContext
        outputs?.pointee.pad_idx = 0
        outputs?.pointee.next = nil
        
        inputs?.pointee.name = av_strdup("out")
        inputs?.pointee.filter_ctx = videoBufferSinkContext
        inputs?.pointee.pad_idx = 0
        inputs?.pointee.next = nil
        
        ret = avfilter_graph_parse_ptr(graph, filterString, &inputs, &outputs, nil)
        guard ret >= 0 else {
            throw FFmpegKitError.filterGraphFailed("failed to parse filter graph: \(filterString)")
        }
        
        ret = avfilter_graph_config(graph, nil)
        guard ret >= 0 else {
            throw FFmpegKitError.filterGraphFailed("failed to configure filter graph")
        }
    }
    
    private func setupAudioResampler() throws {
        guard let decoderCtx = audioDecoderContext,
              let encoderCtx = audioEncoderContext else { return }
        
        // Check if resampling is needed
        let needsResample = decoderCtx.pointee.sample_rate != encoderCtx.pointee.sample_rate ||
                           decoderCtx.pointee.sample_fmt != encoderCtx.pointee.sample_fmt ||
                           av_channel_layout_compare(&decoderCtx.pointee.ch_layout, &encoderCtx.pointee.ch_layout) != 0
        
        guard needsResample else { return }
        
        // Allocate resampler
        var swr: OpaquePointer? = nil
        var ret = swr_alloc_set_opts2(&swr,
                                       &encoderCtx.pointee.ch_layout,
                                       encoderCtx.pointee.sample_fmt,
                                       encoderCtx.pointee.sample_rate,
                                       &decoderCtx.pointee.ch_layout,
                                       decoderCtx.pointee.sample_fmt,
                                       decoderCtx.pointee.sample_rate,
                                       0, nil)
        guard ret >= 0, let swrCtx = swr else {
            throw FFmpegKitError.allocationFailed("audio resampler")
        }
        
        swrContext = swrCtx
        
        ret = swr_init(swrCtx)
        guard ret >= 0 else {
            throw FFmpegKitError.allocationFailed("audio resampler init")
        }
    }
    
    // MARK: - Muxing
    
    private func writeHeader() throws {
        guard let outCtx = outputFormatContext else { return }
        
        var opts: OpaquePointer? = nil
        
        // Format-specific options
        if config.outputFormat == "mp4" || config.outputFormat == "mov" {
            av_dict_set(&opts, "movflags", "+faststart", 0)
        }
        
        let ret = avformat_write_header(outCtx, &opts)
        av_dict_free(&opts)
        
        guard ret >= 0 else {
            throw FFmpegKitError.writeHeaderFailed(ret)
        }
    }
    
    private func writeTrailer() throws {
        guard let outCtx = outputFormatContext else { return }
        
        // Flush encoders
        if let encoderCtx = videoEncoderContext {
            try flushEncoder(encoderCtx: encoderCtx, streamIndex: outputVideoStreamIndex)
        }
        if let encoderCtx = audioEncoderContext {
            try flushEncoder(encoderCtx: encoderCtx, streamIndex: outputAudioStreamIndex)
        }
        
        let ret = av_write_trailer(outCtx)
        guard ret >= 0 else {
            throw FFmpegKitError.encodingFailed(ret)
        }
    }
    
    // MARK: - Frame Processing
    
    private func processFrames() throws {
        guard let inCtx = inputFormatContext else { return }
        
        var packet = av_packet_alloc()
        var frame = av_frame_alloc()
        var filteredFrame = av_frame_alloc()
        
        defer {
            av_packet_free(&packet)
            av_frame_free(&frame)
            av_frame_free(&filteredFrame)
        }
        
        var progress = TranscodingProgress()
        progress.totalDuration = Double(inputDuration) / Double(AV_TIME_BASE)
        
        var frameCount = 0
        let startTime = Date()
        
        while !shouldStop {
            let ret = av_read_frame(inCtx, packet)
            
            if ret < 0 {
                if isAVErrorEOF(ret) {
                    break  // End of file
                }
                continue  // Other errors, try next packet
            }
            
            defer { av_packet_unref(packet) }
            
            let streamIndex = packet!.pointee.stream_index
            
            // Check if we've passed the end time
            if endPts < Int64.max {
                let packetPts = packet!.pointee.pts
                let stream = inCtx.pointee.streams[Int(streamIndex)]!
                let ptsInTimeBase = av_rescale_q(packetPts, stream.pointee.time_base, AVRational(num: 1, den: Int32(AV_TIME_BASE)))
                
                if ptsInTimeBase > endPts {
                    break
                }
            }
            
            // Process video packet
            if streamIndex == videoStreamIndex && videoDecoderContext != nil && !config.copyVideo {
                try processVideoPacket(packet!, frame: frame!, filteredFrame: filteredFrame!)
                frameCount += 1
            }
            // Process audio packet
            else if streamIndex == audioStreamIndex && audioDecoderContext != nil && !config.copyAudio {
                try processAudioPacket(packet!, frame: frame!)
            }
            // Stream copy
            else if (streamIndex == videoStreamIndex && config.copyVideo) ||
                    (streamIndex == audioStreamIndex && config.copyAudio) {
                try copyPacket(packet!, inputStreamIndex: streamIndex)
            }
            
            // Update progress
            if frameCount % 30 == 0 {  // Update every 30 frames
                let packetPts = packet!.pointee.pts
                let stream = inCtx.pointee.streams[Int(streamIndex)]!
                let currentTime = timestampToSeconds(packetPts, timeBase: stream.pointee.time_base)
                
                progress.currentTime = currentTime
                progress.percentage = progress.totalDuration > 0 ? currentTime / progress.totalDuration : 0
                progress.frame = frameCount
                
                let elapsed = Date().timeIntervalSince(startTime)
                progress.fps = elapsed > 0 ? Double(frameCount) / elapsed : 0
                progress.speed = progress.totalDuration > 0 && elapsed > 0 ? currentTime / elapsed : 0
                
                progressCallback?(progress)
            }
        }
        
        if shouldStop {
            throw FFmpegKitError.cancelled
        }
    }
    
    private func processVideoPacket(_ packet: UnsafeMutablePointer<AVPacket>,
                                    frame: UnsafeMutablePointer<AVFrame>,
                                    filteredFrame: UnsafeMutablePointer<AVFrame>) throws {
        guard let decoderCtx = videoDecoderContext,
              videoEncoderContext != nil else { return }
        
        // Send packet to decoder
        var ret = avcodec_send_packet(decoderCtx, packet)
        if ret < 0 && !isAVErrorEAGAIN(ret) {
            throw FFmpegKitError.decodingFailed(ret)
        }
        
        // Receive decoded frames
        while true {
            ret = avcodec_receive_frame(decoderCtx, frame)
            
            if isAVErrorEAGAIN(ret) || isAVErrorEOF(ret) {
                break
            }
            guard ret >= 0 else {
                throw FFmpegKitError.decodingFailed(ret)
            }
            
            defer { av_frame_unref(frame) }
            
            // Apply filters if present
            if videoFilterGraph != nil {
                try filterVideoFrame(frame, output: filteredFrame)
                try encodeVideoFrame(filteredFrame)
                av_frame_unref(filteredFrame)
            } else {
                try encodeVideoFrame(frame)
            }
        }
    }
    
    private func filterVideoFrame(_ input: UnsafeMutablePointer<AVFrame>,
                                  output: UnsafeMutablePointer<AVFrame>) throws {
        guard let srcCtx = videoBufferSrcContext,
              let sinkCtx = videoBufferSinkContext else { return }
        
        var ret = av_buffersrc_add_frame_flags(srcCtx, input, Int32(AV_BUFFERSRC_FLAG_KEEP_REF))
        guard ret >= 0 else {
            throw FFmpegKitError.filterGraphFailed("failed to feed frame to filter")
        }
        
        ret = av_buffersink_get_frame(sinkCtx, output)
        guard ret >= 0 else {
            if isAVErrorEAGAIN(ret) { return }
            throw FFmpegKitError.filterGraphFailed("failed to get frame from filter")
        }
    }
    
    private func encodeVideoFrame(_ frame: UnsafeMutablePointer<AVFrame>?) throws {
        guard let encoderCtx = videoEncoderContext else { return }
        
        var ret = avcodec_send_frame(encoderCtx, frame)
        if ret < 0 && !isAVErrorEAGAIN(ret) {
            throw FFmpegKitError.encodingFailed(ret)
        }
        
        var packet = av_packet_alloc()
        defer { av_packet_free(&packet) }
        
        while true {
            ret = avcodec_receive_packet(encoderCtx, packet)
            
            if isAVErrorEAGAIN(ret) || isAVErrorEOF(ret) {
                break
            }
            guard ret >= 0 else {
                throw FFmpegKitError.encodingFailed(ret)
            }
            
            defer { av_packet_unref(packet) }
            
            try writePacket(packet!, streamIndex: outputVideoStreamIndex)
        }
    }
    
    private func processAudioPacket(_ packet: UnsafeMutablePointer<AVPacket>,
                                    frame: UnsafeMutablePointer<AVFrame>) throws {
        guard let decoderCtx = audioDecoderContext,
              let encoderCtx = audioEncoderContext else { return }
        
        var ret = avcodec_send_packet(decoderCtx, packet)
        if ret < 0 && !isAVErrorEAGAIN(ret) {
            throw FFmpegKitError.decodingFailed(ret)
        }
        
        while true {
            ret = avcodec_receive_frame(decoderCtx, frame)
            
            if isAVErrorEAGAIN(ret) || isAVErrorEOF(ret) {
                break
            }
            guard ret >= 0 else {
                throw FFmpegKitError.decodingFailed(ret)
            }
            
            defer { av_frame_unref(frame) }
            
            // Resample if needed
            if let swr = swrContext {
                try resampleAndEncode(frame, swr: swr, encoderCtx: encoderCtx)
            } else {
                try encodeAudioFrame(frame)
            }
        }
    }
    
    private func resampleAndEncode(_ frame: UnsafeMutablePointer<AVFrame>,
                                   swr: OpaquePointer,
                                   encoderCtx: UnsafeMutablePointer<AVCodecContext>) throws {
        // Allocate output frame
        var outFrame = av_frame_alloc()
        defer { av_frame_free(&outFrame) }
        
        guard let output = outFrame else { return }
        
        output.pointee.sample_rate = encoderCtx.pointee.sample_rate
        output.pointee.ch_layout = encoderCtx.pointee.ch_layout
        output.pointee.format = encoderCtx.pointee.sample_fmt.rawValue
        output.pointee.nb_samples = swr_get_out_samples(swr, frame.pointee.nb_samples)
        
        var ret = av_frame_get_buffer(output, 0)
        guard ret >= 0 else {
            throw FFmpegKitError.allocationFailed("resampled audio frame")
        }
        
        ret = swr_convert_frame(swr, output, frame)
        guard ret >= 0 else {
            throw FFmpegKitError.encodingFailed(ret)
        }
        
        try encodeAudioFrame(output)
    }
    
    private func encodeAudioFrame(_ frame: UnsafeMutablePointer<AVFrame>?) throws {
        guard let encoderCtx = audioEncoderContext else { return }
        
        var ret = avcodec_send_frame(encoderCtx, frame)
        if ret < 0 && !isAVErrorEAGAIN(ret) {
            throw FFmpegKitError.encodingFailed(ret)
        }
        
        var packet = av_packet_alloc()
        defer { av_packet_free(&packet) }
        
        while true {
            ret = avcodec_receive_packet(encoderCtx, packet)
            
            if isAVErrorEAGAIN(ret) || isAVErrorEOF(ret) {
                break
            }
            guard ret >= 0 else {
                throw FFmpegKitError.encodingFailed(ret)
            }
            
            defer { av_packet_unref(packet) }
            
            try writePacket(packet!, streamIndex: outputAudioStreamIndex)
        }
    }
    
    private func copyPacket(_ packet: UnsafeMutablePointer<AVPacket>, inputStreamIndex: Int32) throws {
        guard let inCtx = inputFormatContext,
              let outCtx = outputFormatContext else { return }
        
        let outputStreamIndex: Int32
        if inputStreamIndex == videoStreamIndex {
            outputStreamIndex = outputVideoStreamIndex
        } else if inputStreamIndex == audioStreamIndex {
            outputStreamIndex = outputAudioStreamIndex
        } else {
            return
        }
        
        guard outputStreamIndex >= 0 else { return }
        
        let inStream = inCtx.pointee.streams[Int(inputStreamIndex)]!
        let outStream = outCtx.pointee.streams[Int(outputStreamIndex)]!
        
        // Rescale timestamps
        packet.pointee.pts = av_rescale_q_rnd(packet.pointee.pts, inStream.pointee.time_base, outStream.pointee.time_base, AVRounding(rawValue: AVRounding.RawValue(AV_ROUND_NEAR_INF.rawValue | AV_ROUND_PASS_MINMAX.rawValue)))
        packet.pointee.dts = av_rescale_q_rnd(packet.pointee.dts, inStream.pointee.time_base, outStream.pointee.time_base, AVRounding(rawValue: AVRounding.RawValue(AV_ROUND_NEAR_INF.rawValue | AV_ROUND_PASS_MINMAX.rawValue)))
        packet.pointee.duration = av_rescale_q(packet.pointee.duration, inStream.pointee.time_base, outStream.pointee.time_base)
        packet.pointee.stream_index = outputStreamIndex
        packet.pointee.pos = -1
        
        let ret = av_interleaved_write_frame(outCtx, packet)
        if ret < 0 && !isAVErrorEOF(ret) {
            throw FFmpegKitError.encodingFailed(ret)
        }
    }
    
    private func writePacket(_ packet: UnsafeMutablePointer<AVPacket>, streamIndex: Int32) throws {
        guard let outCtx = outputFormatContext else { return }
        guard streamIndex >= 0 else { return }
        
        packet.pointee.stream_index = streamIndex
        
        let ret = av_interleaved_write_frame(outCtx, packet)
        if ret < 0 && !isAVErrorEOF(ret) {
            throw FFmpegKitError.encodingFailed(ret)
        }
    }
    
    private func flushEncoder(encoderCtx: UnsafeMutablePointer<AVCodecContext>, streamIndex: Int32) throws {
        // Send flush signal
        avcodec_send_frame(encoderCtx, nil)
        
        var packet = av_packet_alloc()
        defer { av_packet_free(&packet) }
        
        while true {
            let ret = avcodec_receive_packet(encoderCtx, packet)
            if ret < 0 { break }
            
            defer { av_packet_unref(packet) }
            try writePacket(packet!, streamIndex: streamIndex)
        }
    }
    
    // MARK: - Helpers
    
    private func getDefaultVideoEncoder() -> String {
        switch config.outputFormat.lowercased() {
        case "mp4", "mov", "m4v":
            return "libx264"
        case "mkv", "avi":
            return "libx264"
        case "webm":
            return "libvpx-vp9"
        case "gif":
            return "gif"
        default:
            return "libx264"
        }
    }
    
    private func getDefaultAudioEncoder() -> String {
        switch config.outputFormat.lowercased() {
        case "mp4", "mov", "m4a", "m4v":
            return "aac"
        case "mkv":
            return "aac"
        case "webm", "ogg":
            return "libopus"
        case "mp3":
            return "libmp3lame"
        case "wav":
            return "pcm_s16le"
        case "flac":
            return "flac"
        case "aac":
            return "aac"
        default:
            return "aac"
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        // Free filter graphs
        if videoFilterGraph != nil {
            avfilter_graph_free(&videoFilterGraph)
        }
        if audioFilterGraph != nil {
            avfilter_graph_free(&audioFilterGraph)
        }
        
        // Free resampler
        if swrContext != nil {
            swr_free(&swrContext)
        }
        
        // Free scaler
        if swsContext != nil {
            sws_freeContext(swsContext)
            swsContext = nil
        }
        
        // Free encoder contexts
        if videoEncoderContext != nil {
            avcodec_free_context(&videoEncoderContext)
        }
        if audioEncoderContext != nil {
            avcodec_free_context(&audioEncoderContext)
        }
        
        // Free decoder contexts
        if videoDecoderContext != nil {
            avcodec_free_context(&videoDecoderContext)
        }
        if audioDecoderContext != nil {
            avcodec_free_context(&audioDecoderContext)
        }
        
        // Close output
        if let outCtx = outputFormatContext {
            if outCtx.pointee.pb != nil && outCtx.pointee.oformat.pointee.flags & AVFMT_NOFILE == 0 {
                avio_closep(&outCtx.pointee.pb)
            }
            avformat_free_context(outCtx)
            outputFormatContext = nil
        }
        
        // Close input
        avformat_close_input(&inputFormatContext)
        
        // Free hardware context
        if hwDeviceContext != nil {
            av_buffer_unref(&hwDeviceContext)
        }
    }
}

