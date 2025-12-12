//
//  FilterGraph.swift
//  Convertify
//
//  Filter graph utilities for video/audio processing
//

import Foundation
import Libavformat
import Libavfilter
import Libavcodec
import Libavutil
import Libswscale

// MARK: - Filter Graph Builder

/// Helper class to build and manage FFmpeg filter graphs
final class FilterGraphBuilder {
    
    // MARK: - Video Filter Presets
    
    /// Build a simple video filter string
    static func buildVideoFilterString(
        scale: (width: Int, height: Int)? = nil,
        crop: (x: Int, y: Int, width: Int, height: Int)? = nil,
        fps: Double? = nil,
        format: String? = nil
    ) -> String {
        var filters: [String] = []
        
        if let c = crop {
            filters.append("crop=\(c.width):\(c.height):\(c.x):\(c.y)")
        }
        
        if let f = fps {
            filters.append("fps=\(f)")
        }
        
        if let s = scale {
            filters.append("scale=\(s.width):\(s.height):flags=lanczos")
        }
        
        if let fmt = format {
            filters.append("format=\(fmt)")
        }
        
        return filters.joined(separator: ",")
    }
    
    /// Build a GIF filter string with palette generation
    static func buildGifFilterString(
        fps: Int = 15,
        width: Int = 480,
        crop: (x: Int, y: Int, width: Int, height: Int)? = nil,
        ditherMode: String = "bayer",
        bayerScale: Int = 5
    ) -> String {
        var baseFilters: [String] = []
        
        if let c = crop {
            baseFilters.append("crop=\(c.width):\(c.height):\(c.x):\(c.y)")
        }
        
        baseFilters.append("fps=\(fps)")
        baseFilters.append("scale=\(width):-1:flags=lanczos")
        
        let preFilters = baseFilters.joined(separator: ",")
        
        // Split -> palettegen -> paletteuse
        return "[0:v] \(preFilters),split [a][b];[a] palettegen=stats_mode=single [p];[b][p] paletteuse=dither=\(ditherMode):bayer_scale=\(bayerScale):diff_mode=rectangle"
    }
    
    /// Build an audio filter string
    static func buildAudioFilterString(
        sampleRate: Int? = nil,
        channels: Int? = nil,
        volume: Double? = nil
    ) -> String {
        var filters: [String] = []
        
        if let sr = sampleRate {
            filters.append("aresample=\(sr)")
        }
        
        if let ch = channels {
            filters.append("pan=\(ch)c")
        }
        
        if let vol = volume {
            filters.append("volume=\(vol)")
        }
        
        return filters.joined(separator: ",")
    }
}

// MARK: - GIF Transcoder

/// Specialized transcoder for high-quality GIF generation
final class GifTranscoder {
    
    private var inputFormatContext: UnsafeMutablePointer<AVFormatContext>?
    private var outputFormatContext: UnsafeMutablePointer<AVFormatContext>?
    private var decoderContext: UnsafeMutablePointer<AVCodecContext>?
    private var filterGraph: UnsafeMutablePointer<AVFilterGraph>?
    private var bufferSrcContext: UnsafeMutablePointer<AVFilterContext>?
    private var bufferSinkContext: UnsafeMutablePointer<AVFilterContext>?
    
    private var videoStreamIndex: Int32 = -1
    private var shouldStop = false
    
    private let inputPath: String
    private let outputPath: String
    private let fps: Int
    private let width: Int
    private let crop: (x: Int, y: Int, width: Int, height: Int)?
    private let startTime: Double?
    private let endTime: Double?
    
    init(inputPath: String,
         outputPath: String,
         fps: Int = 15,
         width: Int = 480,
         crop: (x: Int, y: Int, width: Int, height: Int)? = nil,
         startTime: Double? = nil,
         endTime: Double? = nil) {
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.fps = fps
        self.width = width
        self.crop = crop
        self.startTime = startTime
        self.endTime = endTime
    }
    
    deinit {
        cleanup()
    }
    
    func transcode(progress: @escaping (TranscodingProgress) -> Void) throws {
        defer { cleanup() }
        
        try openInput()
        try setupDecoder()
        try setupFilterGraph()
        try openOutput()
        try processFrames(progress: progress)
    }
    
    func cancel() {
        shouldStop = true
    }
    
    private func openInput() throws {
        var ret = avformat_open_input(&inputFormatContext, inputPath, nil, nil)
        guard ret >= 0 else {
            throw FFmpegKitError.openInputFailed(inputPath, ret)
        }
        
        ret = avformat_find_stream_info(inputFormatContext, nil)
        guard ret >= 0 else {
            throw FFmpegKitError.streamInfoNotFound(inputPath)
        }
        
        // Find video stream
        guard let ctx = inputFormatContext else { return }
        for i in 0..<Int32(ctx.pointee.nb_streams) {
            let stream = ctx.pointee.streams[Int(i)]!
            if stream.pointee.codecpar?.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                videoStreamIndex = i
                break
            }
        }
        
        guard videoStreamIndex >= 0 else {
            throw FFmpegKitError.noVideoStream
        }
        
        // Seek if needed
        if let start = startTime {
            let pts = Int64(start * Double(AV_TIME_BASE))
            av_seek_frame(ctx, -1, pts, AVSEEK_FLAG_BACKWARD)
        }
    }
    
    private func setupDecoder() throws {
        guard let ctx = inputFormatContext else { return }
        let stream = ctx.pointee.streams[Int(videoStreamIndex)]!
        guard let codecpar = stream.pointee.codecpar else { return }
        
        guard let decoder = avcodec_find_decoder(codecpar.pointee.codec_id) else {
            throw FFmpegKitError.codecNotFound("video decoder")
        }
        
        guard let decCtx = avcodec_alloc_context3(decoder) else {
            throw FFmpegKitError.allocationFailed("decoder context")
        }
        decoderContext = decCtx
        
        var ret = avcodec_parameters_to_context(decCtx, codecpar)
        guard ret >= 0 else {
            throw FFmpegKitError.codecOpenFailed("decoder", ret)
        }
        
        ret = avcodec_open2(decCtx, decoder, nil)
        guard ret >= 0 else {
            throw FFmpegKitError.codecOpenFailed("decoder", ret)
        }
    }
    
    private func setupFilterGraph() throws {
        guard let decCtx = decoderContext,
              let inCtx = inputFormatContext else { return }
        
        let stream = inCtx.pointee.streams[Int(videoStreamIndex)]!
        
        guard let graph = avfilter_graph_alloc() else {
            throw FFmpegKitError.allocationFailed("filter graph")
        }
        filterGraph = graph
        
        // Buffer source
        guard let bufferSrc = avfilter_get_by_name("buffer") else {
            throw FFmpegKitError.filterGraphFailed("buffer not found")
        }
        
        let timeBase = stream.pointee.time_base
        let pixFmtName = String(cString: av_get_pix_fmt_name(decCtx.pointee.pix_fmt))
        let args = "video_size=\(decCtx.pointee.width)x\(decCtx.pointee.height):pix_fmt=\(pixFmtName):time_base=\(timeBase.num)/\(timeBase.den):pixel_aspect=1/1"
        
        var ret = avfilter_graph_create_filter(&bufferSrcContext, bufferSrc, "in", args, nil, graph)
        guard ret >= 0 else {
            throw FFmpegKitError.filterGraphFailed("buffer source creation failed")
        }
        
        // Buffer sink
        guard let bufferSink = avfilter_get_by_name("buffersink") else {
            throw FFmpegKitError.filterGraphFailed("buffersink not found")
        }
        
        ret = avfilter_graph_create_filter(&bufferSinkContext, bufferSink, "out", nil, nil, graph)
        guard ret >= 0 else {
            throw FFmpegKitError.filterGraphFailed("buffer sink creation failed")
        }
        
        // Build filter string
        let filterString = FilterGraphBuilder.buildGifFilterString(
            fps: fps,
            width: width,
            crop: crop
        )
        
        // Parse filter graph
        var outputs = avfilter_inout_alloc()
        var inputs = avfilter_inout_alloc()
        
        defer {
            avfilter_inout_free(&outputs)
            avfilter_inout_free(&inputs)
        }
        
        outputs?.pointee.name = av_strdup("in")
        outputs?.pointee.filter_ctx = bufferSrcContext
        outputs?.pointee.pad_idx = 0
        outputs?.pointee.next = nil
        
        inputs?.pointee.name = av_strdup("out")
        inputs?.pointee.filter_ctx = bufferSinkContext
        inputs?.pointee.pad_idx = 0
        inputs?.pointee.next = nil
        
        ret = avfilter_graph_parse_ptr(graph, filterString, &inputs, &outputs, nil)
        guard ret >= 0 else {
            throw FFmpegKitError.filterGraphFailed("parse failed: \(filterString)")
        }
        
        ret = avfilter_graph_config(graph, nil)
        guard ret >= 0 else {
            throw FFmpegKitError.filterGraphFailed("config failed")
        }
    }
    
    private func openOutput() throws {
        var ret = avformat_alloc_output_context2(&outputFormatContext, nil, "gif", outputPath)
        guard ret >= 0, let outCtx = outputFormatContext else {
            throw FFmpegKitError.outputFormatNotFound("gif")
        }
        
        // Create output stream
        guard let encoder = avcodec_find_encoder(AV_CODEC_ID_GIF),
              let outStream = avformat_new_stream(outCtx, encoder) else {
            throw FFmpegKitError.codecNotFound("gif encoder")
        }
        
        // Configure
        let codecpar = outStream.pointee.codecpar!
        codecpar.pointee.codec_type = AVMEDIA_TYPE_VIDEO
        codecpar.pointee.codec_id = AV_CODEC_ID_GIF
        codecpar.pointee.width = Int32(width)
        
        // Calculate height from aspect ratio (scale filter will use width:-1 which means auto-height)
        // Get the output height from the buffersink after filter graph is configured
        guard let sinkCtx = bufferSinkContext else {
            throw FFmpegKitError.filterGraphFailed("buffer sink not initialized")
        }
        let outputHeight = av_buffersink_get_h(sinkCtx)
        codecpar.pointee.height = outputHeight
        
        // Open output file
        if outCtx.pointee.oformat.pointee.flags & AVFMT_NOFILE == 0 {
            ret = avio_open(&outCtx.pointee.pb, outputPath, AVIO_FLAG_WRITE)
            guard ret >= 0 else {
                throw FFmpegKitError.outputOpenFailed(outputPath, ret)
            }
        }
        
        ret = avformat_write_header(outCtx, nil)
        guard ret >= 0 else {
            throw FFmpegKitError.writeHeaderFailed(ret)
        }
    }
    
    private func processFrames(progress: @escaping (TranscodingProgress) -> Void) throws {
        guard let inCtx = inputFormatContext,
              let decCtx = decoderContext,
              let srcCtx = bufferSrcContext,
              let sinkCtx = bufferSinkContext,
              let outCtx = outputFormatContext else { return }
        
        var packet = av_packet_alloc()
        var frame = av_frame_alloc()
        var filteredFrame = av_frame_alloc()
        
        defer {
            av_packet_free(&packet)
            av_frame_free(&frame)
            av_frame_free(&filteredFrame)
        }
        
        let duration = Double(inCtx.pointee.duration) / Double(AV_TIME_BASE)
        var progressInfo = TranscodingProgress()
        progressInfo.totalDuration = duration
        
        let endPts: Int64? = endTime.map { Int64($0 * Double(AV_TIME_BASE)) }
        var frameCount = 0
        
        while !shouldStop {
            let ret = av_read_frame(inCtx, packet)
            if ret < 0 { break }
            
            defer { av_packet_unref(packet) }
            
            guard packet!.pointee.stream_index == videoStreamIndex else { continue }
            
            // Check end time
            if let end = endPts {
                let stream = inCtx.pointee.streams[Int(videoStreamIndex)]!
                let pts = av_rescale_q(packet!.pointee.pts, stream.pointee.time_base, AVRational(num: 1, den: Int32(AV_TIME_BASE)))
                if pts > end { break }
            }
            
            // Decode
            var decRet = avcodec_send_packet(decCtx, packet)
            if decRet < 0 { continue }
            
            while true {
                decRet = avcodec_receive_frame(decCtx, frame)
                if decRet < 0 { break }
                
                defer { av_frame_unref(frame) }
                
                // Filter
                var filterRet = av_buffersrc_add_frame_flags(srcCtx, frame, Int32(AV_BUFFERSRC_FLAG_KEEP_REF))
                if filterRet < 0 { continue }
                
                while true {
                    filterRet = av_buffersink_get_frame(sinkCtx, filteredFrame)
                    if filterRet < 0 { break }
                    
                    defer { av_frame_unref(filteredFrame) }
                    
                    // Write frame as GIF
                    var outPacket = av_packet_alloc()
                    defer { av_packet_free(&outPacket) }
                    
                    // For GIF, we write raw frames
                    outPacket?.pointee.data = filteredFrame!.pointee.data.0
                    outPacket?.pointee.size = Int32(filteredFrame!.pointee.linesize.0 * filteredFrame!.pointee.height)
                    outPacket?.pointee.pts = Int64(frameCount)
                    outPacket?.pointee.dts = Int64(frameCount)
                    outPacket?.pointee.stream_index = 0
                    
                    av_interleaved_write_frame(outCtx, outPacket)
                    frameCount += 1
                }
            }
            
            // Progress update
            if frameCount % 10 == 0 {
                let stream = inCtx.pointee.streams[Int(videoStreamIndex)]!
                let currentTime = timestampToSeconds(packet!.pointee.pts, timeBase: stream.pointee.time_base)
                progressInfo.currentTime = currentTime
                progressInfo.percentage = duration > 0 ? currentTime / duration : 0
                progressInfo.frame = frameCount
                progress(progressInfo)
            }
        }
        
        // Write trailer
        av_write_trailer(outCtx)
        
        if shouldStop {
            throw FFmpegKitError.cancelled
        }
    }
    
    private func cleanup() {
        if filterGraph != nil {
            avfilter_graph_free(&filterGraph)
        }
        if decoderContext != nil {
            avcodec_free_context(&decoderContext)
        }
        if let outCtx = outputFormatContext {
            if outCtx.pointee.pb != nil {
                avio_closep(&outCtx.pointee.pb)
            }
            avformat_free_context(outCtx)
            outputFormatContext = nil
        }
        avformat_close_input(&inputFormatContext)
    }
}

// MARK: - Image Transcoder

/// Specialized transcoder for image format conversion
final class ImageTranscoder {
    
    /// Convert a single image from one format to another
    static func convert(inputPath: String,
                       outputPath: String,
                       width: Int? = nil,
                       height: Int? = nil,
                       quality: Int = 90) throws {
        var inputContext: UnsafeMutablePointer<AVFormatContext>? = nil
        var outputContext: UnsafeMutablePointer<AVFormatContext>? = nil
        var decoderContext: UnsafeMutablePointer<AVCodecContext>? = nil
        var encoderContext: UnsafeMutablePointer<AVCodecContext>? = nil
        
        defer {
            if decoderContext != nil { avcodec_free_context(&decoderContext) }
            if encoderContext != nil { avcodec_free_context(&encoderContext) }
            if let outCtx = outputContext {
                if outCtx.pointee.pb != nil { avio_closep(&outCtx.pointee.pb) }
                avformat_free_context(outCtx)
            }
            avformat_close_input(&inputContext)
        }
        
        // Open input
        var ret = avformat_open_input(&inputContext, inputPath, nil, nil)
        guard ret >= 0 else {
            throw FFmpegKitError.openInputFailed(inputPath, ret)
        }
        
        ret = avformat_find_stream_info(inputContext, nil)
        guard ret >= 0 else {
            throw FFmpegKitError.streamInfoNotFound(inputPath)
        }
        
        // Find video stream (images are treated as single-frame video)
        var videoStreamIndex: Int32 = -1
        for i in 0..<Int32(inputContext!.pointee.nb_streams) {
            if inputContext!.pointee.streams[Int(i)]!.pointee.codecpar?.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                videoStreamIndex = i
                break
            }
        }
        
        guard videoStreamIndex >= 0 else {
            throw FFmpegKitError.noVideoStream
        }
        
        let inputStream = inputContext!.pointee.streams[Int(videoStreamIndex)]!
        guard let codecpar = inputStream.pointee.codecpar else {
            throw FFmpegKitError.noVideoStream
        }
        
        // Setup decoder
        guard let decoder = avcodec_find_decoder(codecpar.pointee.codec_id) else {
            throw FFmpegKitError.codecNotFound("image decoder")
        }
        
        guard let decCtx = avcodec_alloc_context3(decoder) else {
            throw FFmpegKitError.allocationFailed("decoder context")
        }
        decoderContext = decCtx
        
        ret = avcodec_parameters_to_context(decCtx, codecpar)
        guard ret >= 0 else { throw FFmpegKitError.codecOpenFailed("decoder", ret) }
        
        ret = avcodec_open2(decCtx, decoder, nil)
        guard ret >= 0 else { throw FFmpegKitError.codecOpenFailed("decoder", ret) }
        
        // Determine output format and encoder
        let outputExt = (outputPath as NSString).pathExtension.lowercased()
        let (encoderName, codecID) = getImageEncoder(for: outputExt)
        
        guard let encoder = avcodec_find_encoder_by_name(encoderName) else {
            throw FFmpegKitError.codecNotFound(encoderName)
        }
        
        // Setup output
        ret = avformat_alloc_output_context2(&outputContext, nil, nil, outputPath)
        guard ret >= 0 else {
            throw FFmpegKitError.outputFormatNotFound(outputExt)
        }
        
        guard let outStream = avformat_new_stream(outputContext, encoder) else {
            throw FFmpegKitError.allocationFailed("output stream")
        }
        
        guard let encCtx = avcodec_alloc_context3(encoder) else {
            throw FFmpegKitError.allocationFailed("encoder context")
        }
        encoderContext = encCtx
        
        // Configure encoder
        let targetWidth = Int32(width ?? Int(codecpar.pointee.width))
        let targetHeight = Int32(height ?? Int(codecpar.pointee.height))
        
        encCtx.pointee.width = targetWidth
        encCtx.pointee.height = targetHeight
        encCtx.pointee.time_base = AVRational(num: 1, den: 1)
        encCtx.pointee.pix_fmt = encoder.pointee.pix_fmts?.pointee ?? AV_PIX_FMT_YUV420P
        
        // Quality settings
        if outputExt == "jpg" || outputExt == "jpeg" {
            // JPEG quality: 2-31 (lower is better)
            let qualityFactor = (100 - quality) * 31 / 100
            encCtx.pointee.global_quality = Int32(qualityFactor)
            encCtx.pointee.flags |= AV_CODEC_FLAG_QSCALE
        }
        
        ret = avcodec_open2(encCtx, encoder, nil)
        guard ret >= 0 else { throw FFmpegKitError.codecOpenFailed(encoderName, ret) }
        
        ret = avcodec_parameters_from_context(outStream.pointee.codecpar, encCtx)
        guard ret >= 0 else { throw FFmpegKitError.allocationFailed("codec params") }
        
        // Open output file
        if outputContext!.pointee.oformat.pointee.flags & AVFMT_NOFILE == 0 {
            ret = avio_open(&outputContext!.pointee.pb, outputPath, AVIO_FLAG_WRITE)
            guard ret >= 0 else { throw FFmpegKitError.outputOpenFailed(outputPath, ret) }
        }
        
        ret = avformat_write_header(outputContext, nil)
        guard ret >= 0 else { throw FFmpegKitError.writeHeaderFailed(ret) }
        
        // Decode single frame
        var packet = av_packet_alloc()
        var frame = av_frame_alloc()
        
        defer {
            av_packet_free(&packet)
            av_frame_free(&frame)
        }
        
        // Read and decode
        while av_read_frame(inputContext, packet) >= 0 {
            defer { av_packet_unref(packet) }
            
            if packet!.pointee.stream_index != videoStreamIndex { continue }
            
            ret = avcodec_send_packet(decCtx, packet)
            if ret < 0 { continue }
            
            ret = avcodec_receive_frame(decCtx, frame)
            if ret >= 0 {
                // Encode and write
                ret = avcodec_send_frame(encCtx, frame)
                if ret >= 0 {
                    var outPacket = av_packet_alloc()
                    defer { av_packet_free(&outPacket) }
                    
                    ret = avcodec_receive_packet(encCtx, outPacket)
                    if ret >= 0 {
                        av_interleaved_write_frame(outputContext, outPacket)
                    }
                }
                break  // Only need one frame for images
            }
        }
        
        av_write_trailer(outputContext)
    }
    
    private static func getImageEncoder(for ext: String) -> (String, AVCodecID) {
        switch ext {
        case "jpg", "jpeg":
            return ("mjpeg", AV_CODEC_ID_MJPEG)
        case "png":
            return ("png", AV_CODEC_ID_PNG)
        case "webp":
            return ("libwebp", AV_CODEC_ID_WEBP)
        case "bmp":
            return ("bmp", AV_CODEC_ID_BMP)
        case "tiff", "tif":
            return ("tiff", AV_CODEC_ID_TIFF)
        default:
            return ("png", AV_CODEC_ID_PNG)
        }
    }
}

