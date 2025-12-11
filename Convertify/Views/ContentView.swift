//
//  ContentView.swift
//  Convertify
//
//  Elegant native macOS FFmpeg wrapper with sidebar layout
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var manager: ConversionManager
    @State private var showFilePicker = false
    @State private var dragOver = false
    @State private var selectedTool: ConversionTool = .convert
    
    var body: some View {
        ZStack {
            // MARK: Window Background
            // Using .sidebar material for a more opaque dark glass effect.
            // This provides consistent transparency across the entire window,
            // including the title bar area (which uses fullSizeContentView).
            // The title bar and main content area intentionally share the same
            // opacity to create a unified, seamless appearance.
            // NOTE: .sidebar is more opaque than .hudWindow for better readability
            VisualEffectBackground(material: .sidebar)
                .ignoresSafeArea(.all)
            
            HStack(spacing: 0) {
                // Floating Sidebar
                sidebar
                    .frame(width: 220)
                    .background {
                        ZStack {
                            VisualEffectBackground(material: .sidebar)
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 5)
                    .padding(.leading, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 14)
                
                // Main content
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.trailing, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 14)
            }
        }
        // Minimum size ensures sidebar content is always fully visible
        .frame(minWidth: 820, minHeight: 680)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: supportedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await manager.loadFile(from: url) }
            }
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App branding
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "6366F1"), Color(hex: "8B5CF6")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text("Convertify")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
            
            // Tools section
            VStack(alignment: .leading, spacing: 4) {
                SidebarSectionHeader(title: "TOOLS")
                
                ForEach(ConversionTool.allCases) { tool in
                    SidebarToolButton(
                        tool: tool,
                        isSelected: selectedTool == tool
                    ) {
                        guard selectedTool != tool else { return }
                        withAnimation(.spring(response: 0.25)) {
                            selectedTool = tool
                            if manager.inputFile != nil {
                                manager.reset()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            
            // Presets section
            VStack(alignment: .leading, spacing: 4) {
                SidebarSectionHeader(title: "QUICK PRESETS")
                    .padding(.top, 20)
                
                ForEach(QuickPreset.allCases) { preset in
                    SidebarPresetButton(preset: preset) {
                        applyPreset(preset)
                    }
                }
            }
            .padding(.horizontal, 12)
            
            Spacer()
            
            // System info
            VStack(alignment: .leading, spacing: 8) {
                Divider().padding(.horizontal, 4)
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(manager.hardwareAcceleration.hasVideoToolbox ? Color(hex: "22C55E") : Color(hex: "F97316"))
                        .frame(width: 8, height: 8)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(manager.hardwareAcceleration.hasVideoToolbox ? "GPU Accelerated" : "Software Encoding")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary.opacity(0.8))
                        
                        if let gpu = manager.hardwareAcceleration.gpuName {
                            Text(gpu)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        ZStack {
            if let inputFile = manager.inputFile {
                conversionInterface(for: inputFile)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                dropZone
                    .transition(.opacity)
            }
            
            if manager.isConverting {
                ProgressOverlayView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: manager.inputFile != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: manager.isConverting)
    }
    
    // MARK: - Drop Zone
    
    private var dropZone: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 28) {
                // Tool-specific icon
                ZStack {
                    Circle()
                        .fill(selectedTool.color.opacity(0.1))
                        .frame(width: 88, height: 88)
                    
                    Circle()
                        .strokeBorder(selectedTool.color.opacity(0.2), lineWidth: 1)
                        .frame(width: 88, height: 88)
                    
                    Image(systemName: dragOver ? "arrow.down" : selectedTool.icon)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(selectedTool.color)
                        .scaleEffect(dragOver ? 1.1 : 1.0)
                }
                .animation(.spring(response: 0.3), value: dragOver)
                
                VStack(spacing: 8) {
                    Text(selectedTool.dropTitle)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(selectedTool.dropSubtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Button(action: { showFilePicker = true }) {
                    Text("Choose File")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background {
                            Capsule().fill(selectedTool.color)
                        }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 380)
            .padding(48)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.primary.opacity(dragOver ? 0.04 : 0.02))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                dragOver ? selectedTool.color.opacity(0.5) : .primary.opacity(0.08),
                                style: StrokeStyle(lineWidth: dragOver ? 2 : 1, dash: dragOver ? [] : [8, 6])
                            )
                    }
            }
            .scaleEffect(dragOver ? 1.01 : 1.0)
            .animation(.spring(response: 0.3), value: dragOver)
            .onDrop(of: [.fileURL], isTargeted: $dragOver) { providers in
                handleDrop(providers: providers)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { showFilePicker = true }
    }
    
    // MARK: - Conversion Interface
    
    private func conversionInterface(for file: MediaFile) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // File header
                InputFileHeader(file: file) {
                    withAnimation { manager.reset() }
                }
                
                // Tool-specific options
                toolSpecificOptions(for: file)
                
                // Advanced options toggle (for Convert and Trim tools)
                if selectedTool == .convert || selectedTool == .trim || selectedTool == .compress {
                    AdvancedOptionsToggle()
                }
                
                // Convert button
                ConvertAction(tool: selectedTool) {
                    Task { await manager.startConversion() }
                }
            }
            .padding(32)
        }
    }
    
    @ViewBuilder
    private func toolSpecificOptions(for file: MediaFile) -> some View {
        switch selectedTool {
        case .convert:
            OutputSection(detectedType: file.mediaType)
            if !file.isImage {
                QualityPickerSection()
            }
            
        case .compress:
            // Compression needs output format + compression settings
            VideoOutputFormatSection()
            CompressOptionsSection()
            
        case .extractAudio:
            AudioExtractionSection()
            
        case .trim:
            // Trim needs output format + trim settings
            VideoOutputFormatSection()
            TrimSection(duration: file.duration)
            QualityPickerSection()
            
        case .toGif:
            GifOptionsSection(duration: file.duration)
            
        case .resize:
            // Order: Crop → Format → Size
            Group {
                // 1. Crop preview first
                CropPreviewSection(originalResolution: file.resolution, imageURL: file.url)
                
                // 2. Then output format
            if file.isImage {
                OutputSection(detectedType: .image)
            } else {
                VideoOutputFormatSection()
            }
                
                // 3. Finally output size (based on cropped dimensions)
                OutputSizeSection(originalResolution: file.resolution)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func applyPreset(_ preset: QuickPreset) {
        // Apply preset settings
        switch preset {
        case .youtube:
            selectedTool = .convert
            manager.outputFormat = .mp4
            manager.qualityPreset = .quality
        case .instagram:
            selectedTool = .convert
            manager.outputFormat = .mp4
            manager.qualityPreset = .balanced
        case .twitter:
            selectedTool = .compress
            manager.outputFormat = .mp4
            manager.qualityPreset = .fast
        case .discord:
            selectedTool = .compress
            manager.qualityPreset = .fast
        case .web:
            selectedTool = .convert
            manager.outputFormat = .webm
            manager.qualityPreset = .balanced
        }
        
        if manager.inputFile == nil {
            showFilePicker = true
        }
    }
    
    private var supportedContentTypes: [UTType] {
        [.movie, .audio, .image, .mpeg4Movie, .quickTimeMovie, .avi, .mpeg,
         .wav, .mp3, .aiff, .png, .jpeg, .gif, .heic, .webP, .tiff, .bmp]
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in await manager.loadFile(from: url) }
            }
            return true
        }
        return false
    }
}

// MARK: - Conversion Tools

enum ConversionTool: String, CaseIterable, Identifiable {
    case convert = "Convert"
    case compress = "Compress"
    case extractAudio = "Extract Audio"
    case trim = "Trim & Cut"
    case toGif = "Make GIF"
    case resize = "Resize & Crop"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .convert: return "arrow.triangle.2.circlepath"
        case .compress: return "archivebox"
        case .extractAudio: return "waveform"
        case .trim: return "scissors"
        case .toGif: return "photo.stack"
        case .resize: return "crop"
        }
    }
    
    var color: Color {
        switch self {
        case .convert: return Color(hex: "6366F1")
        case .compress: return Color(hex: "F59E0B")
        case .extractAudio: return Color(hex: "EC4899")
        case .trim: return Color(hex: "10B981")
        case .toGif: return Color(hex: "8B5CF6")
        case .resize: return Color(hex: "3B82F6")
        }
    }
    
    var dropTitle: String {
        switch self {
        case .convert: return "Drop a file to convert"
        case .compress: return "Drop a file to compress"
        case .extractAudio: return "Drop a video to extract audio"
        case .trim: return "Drop a file to trim"
        case .toGif: return "Drop a video to make GIF"
        case .resize: return "Drop a file to resize or crop"
        }
    }
    
    var dropSubtitle: String {
        switch self {
        case .convert: return "Video, audio, or image files"
        case .compress: return "Reduce file size while keeping quality"
        case .extractAudio: return "Get audio track from any video"
        case .trim: return "Cut out a specific part"
        case .toGif: return "Create animated GIF from video"
        case .resize: return "Change dimensions or crop to aspect ratio"
        }
    }
}

// MARK: - Quick Presets

enum QuickPreset: String, CaseIterable, Identifiable {
    case youtube = "YouTube"
    case instagram = "Instagram"
    case twitter = "Twitter/X"
    case discord = "Discord"
    case web = "Web"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .instagram: return "camera.fill"
        case .twitter: return "at"
        case .discord: return "bubble.left.fill"
        case .web: return "globe"
        }
    }
}

// MARK: - Sidebar Components

struct SidebarSectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
    }
}

struct SidebarToolButton: View {
    let tool: ConversionTool
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tool.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? tool.color : .secondary)
                    .frame(width: 20)
                
                Text(tool.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? tool.color.opacity(0.12) : (isHovered ? .primary.opacity(0.05) : .clear))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct SidebarPresetButton: View {
    let preset: QuickPreset
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: preset.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                
                Text(preset.rawValue)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.primary.opacity(isHovered ? 0.05 : 0))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Input File Header

struct InputFileHeader: View {
    let file: MediaFile
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(file.mediaType.color.opacity(0.12))
                    .frame(width: 48, height: 48)
                
                Image(systemName: file.mediaType.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(file.mediaType.color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(file.filename)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                
                HStack(spacing: 10) {
                    Text(file.formattedFileSize)
                    if file.duration > 0 {
                        Text("•")
                        Text(file.formattedDuration)
                    }
                    if let res = file.resolution {
                        Text("•")
                        Text(res.description)
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Circle().fill(.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.primary.opacity(0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
                }
        }
    }
}

// MARK: - Output Section

struct OutputSection: View {
    @EnvironmentObject var manager: ConversionManager
    let detectedType: MediaType
    
    private var formats: [OutputFormat] {
        switch detectedType {
        case .video: return OutputFormat.videoFormats
        case .audio: return OutputFormat.audioFormats
        case .image: return OutputFormat.imageFormats
        case .unknown: return OutputFormat.videoFormats
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            OptionCard(title: "Output Format") {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 8)], spacing: 8) {
                        ForEach(formats) { format in
                            FormatCell(format: format, isSelected: manager.outputFormat == format) {
                                withAnimation(.spring(response: 0.2)) {
                                    manager.outputFormat = format
                                }
                            }
                        }
                    }
                    
                    // Format description
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                        Text(manager.outputFormat.description)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                }
            }
            
            // Quality slider for supported formats
            if manager.outputFormat.supportsQualitySlider {
                ImageQualitySection()
            }
            
            // File size estimation
            if let inputFile = manager.inputFile {
                FileSizeEstimation(inputFile: inputFile)
            }
        }
        .onAppear {
            if !formats.contains(manager.outputFormat) {
                manager.outputFormat = formats.first ?? .mp4
            }
        }
    }
}

// MARK: - Advanced Options Toggle

struct AdvancedOptionsToggle: View {
    @EnvironmentObject var manager: ConversionManager
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Toggle button
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                    
                    Text("Advanced Options")
                        .font(.system(size: 12, weight: .medium))
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.primary.opacity(0.8))
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.primary.opacity(0.03))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
                        }
                }
            }
            .buttonStyle(.plain)
            
            // Expandable content
            if isExpanded {
                VStack(spacing: 16) {
                    AdvancedOptionsView()
                }
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.primary.opacity(0.02))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.primary.opacity(0.04), lineWidth: 1)
                        }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Video Output Format Section (for Trim, Compress, Resize tools)

struct VideoOutputFormatSection: View {
    @EnvironmentObject var manager: ConversionManager
    
    private let videoFormats: [OutputFormat] = [.mp4, .mov, .mkv, .webm, .avi]
    
    var body: some View {
        OptionCard(title: "Output Format") {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 8)], spacing: 8) {
                    ForEach(videoFormats) { format in
                        FormatCell(format: format, isSelected: manager.outputFormat == format) {
                            withAnimation(.spring(response: 0.2)) {
                                manager.outputFormat = format
                            }
                        }
                    }
                }
                
                // Format description
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text(manager.outputFormat.description)
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
                .padding(.top, 2)
            }
        }
        .onAppear {
            // Default to MP4 if current format isn't a video format
            if !videoFormats.contains(manager.outputFormat) {
                manager.outputFormat = .mp4
            }
        }
    }
}

// MARK: - Image Quality Section

struct ImageQualitySection: View {
    @EnvironmentObject var manager: ConversionManager
    @State private var quality: Double = 85
    
    var body: some View {
        OptionCard(title: "Quality") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Compression")
                        .font(.system(size: 12, weight: .medium))
                    
                    Spacer()
                    
                    Text("\(Int(quality))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(qualityColor)
                }
                
                // Native slider with custom styling
                Slider(value: $quality, in: 1...100, step: 1)
                    .tint(qualityColor)
                    .onChange(of: quality) { _, newValue in
                        manager.advancedOptions.imageQuality = Int(newValue)
                    }
                
                // Labels
                HStack {
                    Text("Smaller file")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Better quality")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            quality = Double(manager.advancedOptions.imageQuality)
        }
    }
    
    private var qualityColor: Color {
        if quality >= 80 {
            return Color(hex: "22C55E")
        } else if quality >= 50 {
            return Color(hex: "EAB308")
        } else {
            return Color(hex: "EF4444")
        }
    }
}

// MARK: - File Size Estimation

struct FileSizeEstimation: View {
    @EnvironmentObject var manager: ConversionManager
    let inputFile: MediaFile
    
    private var estimatedSize: String {
        let inputSize = Double(inputFile.fileSize)
        var ratio: Double = 1.0
        
        // Estimate based on format and quality
        switch manager.outputFormat {
        case .jpg:
            let quality = Double(manager.advancedOptions.imageQuality) / 100
            ratio = 0.1 + (quality * 0.4) // JPEG typically 10-50% of raw
        case .png:
            ratio = 0.8 // PNG is lossless but compressed
        case .webp:
            let quality = Double(manager.advancedOptions.imageQuality) / 100
            ratio = 0.05 + (quality * 0.25) // WebP is very efficient
        case .heic:
            let quality = Double(manager.advancedOptions.imageQuality) / 100
            ratio = 0.05 + (quality * 0.2) // HEIC is very efficient
        case .tiff:
            ratio = 2.5 // TIFF is usually larger (uncompressed)
        case .bmp:
            ratio = 3.0 // BMP is uncompressed
        case .mp4:
            ratio = manager.qualityPreset == .fast ? 0.3 : (manager.qualityPreset == .balanced ? 0.5 : 0.8)
        case .webm:
            ratio = manager.qualityPreset == .fast ? 0.25 : (manager.qualityPreset == .balanced ? 0.4 : 0.6)
        case .mp3:
            ratio = 0.1
        case .aac:
            ratio = 0.08
        case .wav:
            ratio = 1.5
        case .flac:
            ratio = 0.6
        default:
            ratio = 0.7
        }
        
        let estimated = inputSize * ratio
        return formatFileSize(Int64(estimated))
    }
    
    private var compressionIndicator: (text: String, color: Color) {
        let quality = manager.advancedOptions.imageQuality
        
        switch manager.outputFormat {
        case .jpg, .webp, .heic:
            if quality >= 95 {
                return ("Best quality", Color(hex: "22C55E"))
            } else if quality >= 80 {
                return ("High quality", Color(hex: "22C55E"))
            } else if quality >= 50 {
                return ("Balanced", Color(hex: "EAB308"))
            } else {
                return ("High compression", Color(hex: "F97316"))
            }
        case .png:
            return ("Lossless", Color(hex: "22C55E"))
        case .tiff:
            return ("Lossless (large)", Color(hex: "EAB308"))
        case .bmp:
            return ("Uncompressed", Color(hex: "F97316"))
        case .ico:
            return ("Icon format", Color(hex: "3B82F6"))
        default:
            return ("Standard", Color(hex: "3B82F6"))
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Input size
            VStack(alignment: .leading, spacing: 2) {
                Text("Current")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(inputFile.formattedFileSize)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            
            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            // Estimated output
            VStack(alignment: .leading, spacing: 2) {
                Text("Estimated")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("~\(estimatedSize)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(compressionIndicator.color)
            }
            
            Spacer()
            
            // Compression badge
            Text(compressionIndicator.text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(compressionIndicator.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(compressionIndicator.color.opacity(0.15))
                }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.primary.opacity(0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
                }
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Quality Picker Section

struct QualityPickerSection: View {
    @EnvironmentObject var manager: ConversionManager
    
    var body: some View {
        OptionCard(title: "Quality") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(QualityPreset.allCases) { preset in
                        QualityCell(preset: preset, isSelected: manager.qualityPreset == preset) {
                            withAnimation(.spring(response: 0.2)) {
                                manager.qualityPreset = preset
                            }
                        }
                    }
                }
                
                Text(manager.qualityPreset.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Compress Options Section

struct CompressOptionsSection: View {
    @EnvironmentObject var manager: ConversionManager
    @State private var targetSize: Double = 50 // MB
    
    private var estimatedBitrate: Int {
        // Calculate bitrate from target size and duration
        guard let duration = manager.inputFile?.duration, duration > 0 else { return 2000 }
        // targetSize in MB, duration in seconds
        // bitrate (kbps) = (size_MB * 8 * 1024) / duration_seconds
        let audioBitrate = 128 // Assume ~128kbps for audio
        let totalBitrate = Int((targetSize * 8 * 1024) / duration)
        return max(100, totalBitrate - audioBitrate)
    }
    
    private var compressionRatio: Double {
        guard let inputSize = manager.inputFile?.fileSize, inputSize > 0 else { return 1.0 }
        return (targetSize * 1024 * 1024) / Double(inputSize)
    }
    
    var body: some View {
        OptionCard(title: "Compression") {
            VStack(alignment: .leading, spacing: 16) {
                // Target size slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Target Size")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(Int(targetSize)) MB")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "F59E0B"))
                    }
                    
                    Slider(value: $targetSize, in: 1...500, step: 1)
                        .tint(Color(hex: "F59E0B"))
                        .onChange(of: targetSize) { _, newValue in
                            manager.advancedOptions.targetSizeMB = newValue
                            manager.advancedOptions.videoBitrate = .custom
                            manager.advancedOptions.customVideoBitrate = estimatedBitrate
                        }
                }
                
                // Estimated info
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Video Bitrate")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("\(estimatedBitrate) kbps")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Reduction")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("\(Int((1 - compressionRatio) * 100))%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(compressionRatio < 1 ? Color(hex: "22C55E") : .secondary)
                    }
                }
                
                Text("Lower target = more compression, lower quality")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            // Initialize from input file size if available
            if let fileSize = manager.inputFile?.fileSize {
                let sizeMB = Double(fileSize) / (1024 * 1024)
                targetSize = min(max(1, sizeMB * 0.5), 500) // Start at 50% of original
            }
            manager.advancedOptions.targetSizeMB = targetSize
            manager.advancedOptions.videoBitrate = .custom
            manager.advancedOptions.customVideoBitrate = estimatedBitrate
        }
    }
}

// MARK: - Audio Extraction Section

struct AudioExtractionSection: View {
    @EnvironmentObject var manager: ConversionManager
    
    private let audioFormats: [OutputFormat] = [.mp3, .aac, .wav, .flac, .m4a]
    
    var body: some View {
        OptionCard(title: "Audio Format") {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 8)], spacing: 8) {
                    ForEach(audioFormats) { format in
                        FormatCell(format: format, isSelected: manager.outputFormat == format) {
                            withAnimation(.spring(response: 0.2)) {
                                manager.outputFormat = format
                            }
                        }
                    }
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text(manager.outputFormat.description)
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
                .padding(.top, 2)
            }
        }
        .onAppear {
            if !audioFormats.contains(manager.outputFormat) {
                manager.outputFormat = .mp3
            }
        }
    }
}

// MARK: - Trim Section

struct TrimSection: View {
    @EnvironmentObject var manager: ConversionManager
    let duration: TimeInterval
    
    @State private var startPercent: Double = 0
    @State private var endPercent: Double = 100
    @State private var dragStartStart: Double = 0
    @State private var dragStartEnd: Double = 100
    
    private var startSeconds: TimeInterval {
        startPercent / 100 * duration
    }
    
    private var endSeconds: TimeInterval {
        endPercent / 100 * duration
    }
    
    var body: some View {
        OptionCard(title: "Trim Range") {
            VStack(spacing: 16) {
                // Time display
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(formatTime(startSeconds))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .center, spacing: 4) {
                        Text("Duration")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(formatTime(endSeconds - startSeconds))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(hex: "10B981"))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("End")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(formatTime(endSeconds))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    }
                }
                
                // Interactive dual slider
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track background
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.primary.opacity(0.1))
                            .frame(height: 6)
                        
                        // Selected range
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: "10B981"))
                            .frame(width: max(0, (endPercent - startPercent) / 100 * geo.size.width), height: 6)
                            .offset(x: startPercent / 100 * geo.size.width)
                        
                        // Start handle
                        Circle()
                            .fill(Color.white)
                            .frame(width: 18, height: 18)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            .position(x: startPercent / 100 * geo.size.width, y: 12)
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        let newPercent = (value.location.x / geo.size.width) * 100
                                        startPercent = min(max(0, newPercent), endPercent - 5)
                                        updateManager()
                                    }
                            )
                        
                        // End handle
                        Circle()
                            .fill(Color.white)
                            .frame(width: 18, height: 18)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            .position(x: endPercent / 100 * geo.size.width, y: 12)
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        let newPercent = (value.location.x / geo.size.width) * 100
                                        endPercent = max(min(100, newPercent), startPercent + 5)
                                        updateManager()
                                    }
                            )
                    }
                }
                .frame(height: 24)
                
                Text("Drag handles to select the portion to keep")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            // Initialize from manager if already set
            if let start = manager.advancedOptions.startTime, duration > 0 {
                startPercent = (start / duration) * 100
            }
            if let end = manager.advancedOptions.endTime, duration > 0 {
                endPercent = (end / duration) * 100
            } else {
                endPercent = 100
                manager.advancedOptions.endTime = duration
            }
        }
    }
    
    private func updateManager() {
        manager.advancedOptions.startTime = startSeconds > 0 ? startSeconds : nil
        manager.advancedOptions.endTime = endSeconds < duration ? endSeconds : nil
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, ms)
    }
}

// MARK: - GIF Options Section

struct GifOptionsSection: View {
    @EnvironmentObject var manager: ConversionManager
    let duration: TimeInterval
    
    @State private var fps: Double = 15
    @State private var width: Double = 480
    
    private var estimatedFrames: Int {
        Int(duration * fps)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            OptionCard(title: "GIF Settings") {
                VStack(spacing: 16) {
                    // FPS slider
                    VStack(spacing: 8) {
                        HStack {
                            Text("Frame Rate")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(Int(fps)) fps")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "8B5CF6"))
                        }
                        Slider(value: $fps, in: 5...30, step: 1)
                            .tint(Color(hex: "8B5CF6"))
                            .onChange(of: fps) { _, newValue in
                                manager.advancedOptions.gifFps = Int(newValue)
                            }
                    }
                    
                    // Width slider
                    VStack(spacing: 8) {
                        HStack {
                            Text("Width")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(Int(width))px")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "8B5CF6"))
                        }
                        Slider(value: $width, in: 240...1280, step: 10)
                            .tint(Color(hex: "8B5CF6"))
                            .onChange(of: width) { _, newValue in
                                manager.advancedOptions.gifWidth = Int(newValue)
                            }
                    }
                    
                    // Info
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total Frames")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("\(estimatedFrames)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Duration")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(formatDuration(duration))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                    }
                    
                    Text("Lower values = smaller file size")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            // Also show trim if video is long
            if duration > 10 {
                TrimSection(duration: duration)
            }
        }
        .onAppear {
            manager.outputFormat = .gif
            manager.advancedOptions.gifFps = Int(fps)
            manager.advancedOptions.gifWidth = Int(width)
            
            // Set default width from input resolution
            if let res = manager.inputFile?.resolution {
                width = min(Double(res.width), 720)
                manager.advancedOptions.gifWidth = Int(width)
            }
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Crop Preview Section

struct CropPreviewSection: View {
    @EnvironmentObject var manager: ConversionManager
    let originalResolution: Resolution?
    let imageURL: URL?
    
    @State private var selectedAspect: AspectRatio = .original
    @State private var loadedImage: NSImage?
    @State private var containerWidth: CGFloat = 300
    
    // Interactive crop controls (0-100 percentage)
    @State private var cropLeft: Double = 0
    @State private var cropRight: Double = 100
    @State private var cropTop: Double = 0
    @State private var cropBottom: Double = 100
    
    // Track drag start values
    @State private var dragStartLeft: Double = 0
    @State private var dragStartRight: Double = 100
    @State private var dragStartTop: Double = 0
    @State private var dragStartBottom: Double = 100
    
    // Modifier keys state (live tracking for visual feedback)
    @State private var isShiftPressed: Bool = false
    @State private var isCommandPressed: Bool = false
    
    // Toggle states for modifier behaviors (clickable buttons)
    @State private var lockRatioEnabled: Bool = false
    @State private var fromCenterEnabled: Bool = false
    
    // Aspect ratio at drag start (for ratio-lock)
    @State private var dragStartAspectRatio: CGFloat = 1.0
    
    // Track if we've synced drag start values for the current drag gesture
    @State private var hasSyncedForCurrentDrag: Bool = false
    
    // Key monitor for tracking modifier keys
    @State private var keyMonitor: Any?
    
    // Handle padding to prevent clipping
    private let handlePadding: CGFloat = 10
    
    // Calculate the ideal preview height based on image aspect ratio
    private var previewHeight: CGFloat {
        guard originalAspectRatio > 0 else { return containerWidth }
        let heightForAspect = containerWidth / originalAspectRatio
        return min(heightForAspect, containerWidth)
    }
    
    // Current crop aspect ratio
    private var currentCropAspectRatio: CGFloat {
        let width = cropRight - cropLeft
        let height = cropBottom - cropTop
        guard height > 0 else { return 1 }
        return (width / height) * originalAspectRatio
    }
    
    // Effective modifier states (keyboard OR toggle button)
    private var effectiveLockRatio: Bool { isShiftPressed || lockRatioEnabled }
    private var effectiveFromCenter: Bool { isCommandPressed || fromCenterEnabled }
    
    var body: some View {
            OptionCard(title: "Crop Preview — Drag edges to adjust") {
            VStack(spacing: 12) {
                    // Visual preview with actual image and draggable edges
                    if let image = loadedImage {
                    GeometryReader { outerGeo in
                        let insetSize = CGSize(
                            width: outerGeo.size.width - handlePadding * 2,
                            height: outerGeo.size.height - handlePadding * 2
                        )
                        let cropRect = calculateInteractiveCropRect(in: insetSize)
                        
                        ZStack {
                            // Image container (inset)
                            ZStack {
                                // Full image (dimmed)
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: insetSize.width, height: insetSize.height)
                                    .clipped()
                                    .opacity(0.35)
                                
                                // Cropped region (full brightness)
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: insetSize.width, height: insetSize.height)
                                    .clipped()
                                    .mask {
                                        Rectangle()
                                            .frame(width: cropRect.width, height: cropRect.height)
                                            .position(x: cropRect.midX, y: cropRect.midY)
                                    }
                                
                                // Crop frame border
                                Rectangle()
                                    .strokeBorder(Color.white, lineWidth: 2)
                                    .frame(width: cropRect.width, height: cropRect.height)
                                    .position(x: cropRect.midX, y: cropRect.midY)
                                
                                // Grid lines (rule of thirds)
                                Path { path in
                                    let thirdW = cropRect.width / 3
                                    let thirdH = cropRect.height / 3
                                    let startX = cropRect.minX
                                    let startY = cropRect.minY
                                    
                                    path.move(to: CGPoint(x: startX + thirdW, y: startY))
                                    path.addLine(to: CGPoint(x: startX + thirdW, y: startY + cropRect.height))
                                    path.move(to: CGPoint(x: startX + thirdW * 2, y: startY))
                                    path.addLine(to: CGPoint(x: startX + thirdW * 2, y: startY + cropRect.height))
                                    path.move(to: CGPoint(x: startX, y: startY + thirdH))
                                    path.addLine(to: CGPoint(x: startX + cropRect.width, y: startY + thirdH))
                                    path.move(to: CGPoint(x: startX, y: startY + thirdH * 2))
                                    path.addLine(to: CGPoint(x: startX + cropRect.width, y: startY + thirdH * 2))
                                }
                                .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                            }
                            .frame(width: insetSize.width, height: insetSize.height)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .position(x: outerGeo.size.width / 2, y: outerGeo.size.height / 2)
                                
                            // Edge handles
                                edgeHandle(width: 16, height: max(40, cropRect.height * 0.4))
                                .position(x: handlePadding + cropRect.minX, y: handlePadding + cropRect.midY)
                                .gesture(makeDragGesture(edge: .left, size: insetSize))
                                    .onHover { h in updateCursor(h, .resizeLeftRight) }
                                
                                edgeHandle(width: 16, height: max(40, cropRect.height * 0.4))
                                .position(x: handlePadding + cropRect.maxX, y: handlePadding + cropRect.midY)
                                .gesture(makeDragGesture(edge: .right, size: insetSize))
                                    .onHover { h in updateCursor(h, .resizeLeftRight) }
                                
                                edgeHandle(width: max(40, cropRect.width * 0.4), height: 16)
                                .position(x: handlePadding + cropRect.midX, y: handlePadding + cropRect.minY)
                                .gesture(makeDragGesture(edge: .top, size: insetSize))
                                    .onHover { h in updateCursor(h, .resizeUpDown) }
                                
                                edgeHandle(width: max(40, cropRect.width * 0.4), height: 16)
                                .position(x: handlePadding + cropRect.midX, y: handlePadding + cropRect.maxY)
                                .gesture(makeDragGesture(edge: .bottom, size: insetSize))
                                    .onHover { h in updateCursor(h, .resizeUpDown) }
                                
                                // Corner handles
                                cornerHandle()
                                .position(x: handlePadding + cropRect.minX, y: handlePadding + cropRect.minY)
                                .gesture(makeDragGesture(edge: .topLeft, size: insetSize))
                                
                                cornerHandle()
                                .position(x: handlePadding + cropRect.maxX, y: handlePadding + cropRect.minY)
                                .gesture(makeDragGesture(edge: .topRight, size: insetSize))
                                
                                cornerHandle()
                                .position(x: handlePadding + cropRect.minX, y: handlePadding + cropRect.maxY)
                                .gesture(makeDragGesture(edge: .bottomLeft, size: insetSize))
                                
                                cornerHandle()
                                .position(x: handlePadding + cropRect.maxX, y: handlePadding + cropRect.maxY)
                                .gesture(makeDragGesture(edge: .bottomRight, size: insetSize))
                            }
                        }
                        .aspectRatio(originalAspectRatio, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    .frame(height: previewHeight + handlePadding * 2)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                            .padding(handlePadding)
                    }
                    .background {
                        GeometryReader { geo in
                            Color.clear.onAppear {
                                containerWidth = geo.size.width - handlePadding * 2
                            }
                            .onChange(of: geo.size.width) { _, newWidth in
                                containerWidth = newWidth - handlePadding * 2
                            }
                        }
                    }
                    .onAppear {
                        setupKeyMonitor()
                        // Initialize aspect ratio for ratio-lock feature
                        syncDragStartValues()
                    }
                    .onDisappear { removeKeyMonitor() }
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.primary.opacity(0.1))
                        .frame(height: previewHeight)
                            .overlay {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        .background {
                            GeometryReader { geo in
                                Color.clear.onAppear {
                                    containerWidth = geo.size.width
                                }
                            }
                        }
                }
                
                // Modifier toggle buttons (below canvas)
                HStack(spacing: 12) {
                    // Lock Ratio toggle
                    Button {
                        withAnimation(.spring(response: 0.2)) {
                            lockRatioEnabled.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("⇧")
                                .font(.system(size: 11, weight: .medium))
                            Text("Lock Ratio")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(effectiveLockRatio ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(effectiveLockRatio ? Color(hex: "3B82F6") : .primary.opacity(0.05))
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // From Center toggle
                    Button {
                        withAnimation(.spring(response: 0.2)) {
                            fromCenterEnabled.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("⌘")
                                .font(.system(size: 11, weight: .medium))
                            Text("From Center")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(effectiveFromCenter ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(effectiveFromCenter ? Color(hex: "3B82F6") : .primary.opacity(0.05))
                        }
                    }
                    .buttonStyle(.plain)
                    }
                    
                    // Aspect ratio selector
                    HStack(spacing: 6) {
                        ForEach(AspectRatio.allCases) { aspect in
                            Button {
                                withAnimation(.spring(response: 0.25)) {
                                    selectedAspect = aspect
                                    applyAspectRatio(aspect)
                                }
                            } label: {
                                Text(aspect.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(selectedAspect == aspect ? .white : .secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background {
                                        Capsule()
                                            .fill(selectedAspect == aspect ? Color(hex: "3B82F6") : .primary.opacity(0.05))
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                // Editable crop values inline
                    if let res = originalResolution {
                    cropValuesRow(resolution: res)
                    }
                }
            }
            .onAppear {
                loadImage()
            }
            .onChange(of: imageURL) { _, _ in
                loadImage()
        }
    }
    
    // MARK: - Inline Crop Values Row
    
    @ViewBuilder
    private func cropValuesRow(resolution: Resolution) -> some View {
        HStack(spacing: 8) {
            // X offset
            HStack(spacing: 3) {
                Text("X")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("", value: Binding(
                    get: { Int(Double(resolution.width) * cropLeft / 100) },
                    set: { newVal in
                        cropLeft = clamp(Double(newVal) / Double(resolution.width) * 100, min: 0, max: cropRight - 10)
                        syncDragStartValues()
                        syncCropToManager()
                    }
                ), format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 40)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(3)
            }
            
            // Y offset
            HStack(spacing: 3) {
                Text("Y")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("", value: Binding(
                    get: { Int(Double(resolution.height) * cropTop / 100) },
                    set: { newVal in
                        cropTop = clamp(Double(newVal) / Double(resolution.height) * 100, min: 0, max: cropBottom - 10)
                        syncDragStartValues()
                        syncCropToManager()
                    }
                ), format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 40)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(3)
            }
            
            Text("→")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.5))
            
            // Width
            HStack(spacing: 3) {
                Text("W")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("", value: Binding(
                    get: { Int(Double(resolution.width) * (cropRight - cropLeft) / 100) },
                    set: { newVal in
                        let newWidth = clamp(Double(newVal) / Double(resolution.width) * 100, min: 10, max: 100 - cropLeft)
                        cropRight = cropLeft + newWidth
                        syncDragStartValues()
                        syncCropToManager()
                    }
                ), format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 44)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(3)
            }
            
            Text("×")
                                .font(.system(size: 10))
                        .foregroundColor(.secondary)
            
            // Height
            HStack(spacing: 3) {
                Text("H")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("", value: Binding(
                    get: { Int(Double(resolution.height) * (cropBottom - cropTop) / 100) },
                    set: { newVal in
                        let newHeight = clamp(Double(newVal) / Double(resolution.height) * 100, min: 10, max: 100 - cropTop)
                        cropBottom = cropTop + newHeight
                        syncDragStartValues()
                        syncCropToManager()
                    }
                ), format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 44)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(3)
            }
        }
    }
    
    // MARK: - Key Monitor
    
    private func setupKeyMonitor() {
        // Only add if not already monitoring
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            isShiftPressed = event.modifierFlags.contains(.shift)
            isCommandPressed = event.modifierFlags.contains(.command)
            return event
        }
    }
    
    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
    
    private func loadImage() {
        guard let url = imageURL else { return }
        
        // Check if this is a video file by extension
        let videoExtensions = ["mp4", "mov", "mkv", "avi", "webm", "m4v", "wmv", "flv", "3gp", "ogv"]
        let ext = url.pathExtension.lowercased()
        let isVideo = videoExtensions.contains(ext)
        
        DispatchQueue.global(qos: .userInitiated).async {
            var image: NSImage?
            
            if isVideo {
                // Generate thumbnail from video using AVFoundation
                let asset = AVAsset(url: url)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                imageGenerator.maximumSize = CGSize(width: 1280, height: 1280) // Reasonable preview size
                
                let time = CMTime(seconds: 0, preferredTimescale: 600)
                
                do {
                    let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                    image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                } catch {
                    // If thumbnail generation fails at 0s, try a slightly later time
                    let laterTime = CMTime(seconds: 1, preferredTimescale: 600)
                    if let cgImage = try? imageGenerator.copyCGImage(at: laterTime, actualTime: nil) {
                        image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    }
                }
            } else {
                // Load image directly
                image = NSImage(contentsOf: url)
            }
            
            if let finalImage = image {
                DispatchQueue.main.async {
                    self.loadedImage = finalImage
                }
            }
        }
    }
    
    private var originalAspectRatio: CGFloat {
        guard let res = originalResolution else { return 16/9 }
        return CGFloat(res.width) / CGFloat(res.height)
    }
    
    private func calculateInteractiveCropRect(in size: CGSize) -> CGRect {
        let x = size.width * cropLeft / 100
        let y = size.height * cropTop / 100
        let width = size.width * (cropRight - cropLeft) / 100
        let height = size.height * (cropBottom - cropTop) / 100
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    // Edge types for drag handling
    private enum CropEdge {
        case left, right, top, bottom
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    // Create edge handle view
    @ViewBuilder
    private func edgeHandle(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.9))
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .contentShape(Rectangle().size(width: width + 20, height: height + 20))
    }
    
    // Create corner handle view
    @ViewBuilder
    private func cornerHandle() -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 14, height: 14)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .contentShape(Circle().size(width: 30, height: 30))
    }
    
    // Update cursor helper
    private func updateCursor(_ hovering: Bool, _ cursor: NSCursor) {
        if hovering {
            cursor.push()
        } else {
            NSCursor.pop()
        }
    }
    
    // Create drag gesture for each edge
    private func makeDragGesture(edge: CropEdge, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                // Sync drag start values at the beginning of each new drag
                // This captures the current aspect ratio for the ratio-lock feature
                if !hasSyncedForCurrentDrag {
                    syncDragStartValues()
                    hasSyncedForCurrentDrag = true
                }
                
                let dx = value.translation.width / size.width * 100
                let dy = value.translation.height / size.height * 100
                
                // Apply drag based on edge type
                applyDrag(edge: edge, dx: dx, dy: dy)
                
                syncCropToManager()
            }
            .onEnded { _ in
                hasSyncedForCurrentDrag = false
                syncCropToManager()
            }
    }
    
    private func applyDrag(edge: CropEdge, dx: Double, dy: Double) {
        let fromCenter = effectiveFromCenter
        let lockRatio = effectiveLockRatio
        
        // Calculate center of current crop
        let centerX = (dragStartLeft + dragStartRight) / 2
        let centerY = (dragStartTop + dragStartBottom) / 2
        
        // When both modifiers are active, handle them together properly
        if fromCenter && lockRatio {
            applyDragCenteredWithRatio(edge: edge, dx: dx, dy: dy, centerX: centerX, centerY: centerY)
            return
        }
                
                switch edge {
                case .left:
            if fromCenter {
                cropLeft = clamp(dragStartLeft + dx, min: 0, max: centerX - 5)
                cropRight = clamp(dragStartRight - dx, min: centerX + 5, max: 100)
            } else {
                    cropLeft = clamp(dragStartLeft + dx, min: 0, max: cropRight - 10)
            }
            if lockRatio { adjustHeightForRatio(fromCenter: fromCenter) }
            
                case .right:
            if fromCenter {
                cropRight = clamp(dragStartRight + dx, min: centerX + 5, max: 100)
                cropLeft = clamp(dragStartLeft - dx, min: 0, max: centerX - 5)
            } else {
                    cropRight = clamp(dragStartRight + dx, min: cropLeft + 10, max: 100)
            }
            if lockRatio { adjustHeightForRatio(fromCenter: fromCenter) }
            
                case .top:
            if fromCenter {
                cropTop = clamp(dragStartTop + dy, min: 0, max: centerY - 5)
                cropBottom = clamp(dragStartBottom - dy, min: centerY + 5, max: 100)
            } else {
                    cropTop = clamp(dragStartTop + dy, min: 0, max: cropBottom - 10)
            }
            if lockRatio { adjustWidthForRatio(fromCenter: fromCenter) }
            
                case .bottom:
            if fromCenter {
                cropBottom = clamp(dragStartBottom + dy, min: centerY + 5, max: 100)
                cropTop = clamp(dragStartTop - dy, min: 0, max: centerY - 5)
            } else {
                    cropBottom = clamp(dragStartBottom + dy, min: cropTop + 10, max: 100)
            }
            if lockRatio { adjustWidthForRatio(fromCenter: fromCenter) }
            
                case .topLeft:
            if fromCenter {
                cropLeft = clamp(dragStartLeft + dx, min: 0, max: centerX - 5)
                cropRight = clamp(dragStartRight - dx, min: centerX + 5, max: 100)
                cropTop = clamp(dragStartTop + dy, min: 0, max: centerY - 5)
                cropBottom = clamp(dragStartBottom - dy, min: centerY + 5, max: 100)
            } else {
                    cropLeft = clamp(dragStartLeft + dx, min: 0, max: cropRight - 10)
                    cropTop = clamp(dragStartTop + dy, min: 0, max: cropBottom - 10)
            }
            if lockRatio { adjustForCornerRatio(dx: dx, dy: dy, anchorRight: !fromCenter, anchorBottom: !fromCenter) }
            
                case .topRight:
            if fromCenter {
                cropRight = clamp(dragStartRight + dx, min: centerX + 5, max: 100)
                cropLeft = clamp(dragStartLeft - dx, min: 0, max: centerX - 5)
                cropTop = clamp(dragStartTop + dy, min: 0, max: centerY - 5)
                cropBottom = clamp(dragStartBottom - dy, min: centerY + 5, max: 100)
            } else {
                    cropRight = clamp(dragStartRight + dx, min: cropLeft + 10, max: 100)
                    cropTop = clamp(dragStartTop + dy, min: 0, max: cropBottom - 10)
            }
            if lockRatio { adjustForCornerRatio(dx: dx, dy: dy, anchorRight: fromCenter, anchorBottom: !fromCenter) }
            
                case .bottomLeft:
            if fromCenter {
                cropLeft = clamp(dragStartLeft + dx, min: 0, max: centerX - 5)
                cropRight = clamp(dragStartRight - dx, min: centerX + 5, max: 100)
                cropBottom = clamp(dragStartBottom + dy, min: centerY + 5, max: 100)
                cropTop = clamp(dragStartTop - dy, min: 0, max: centerY - 5)
            } else {
                    cropLeft = clamp(dragStartLeft + dx, min: 0, max: cropRight - 10)
                    cropBottom = clamp(dragStartBottom + dy, min: cropTop + 10, max: 100)
            }
            if lockRatio { adjustForCornerRatio(dx: dx, dy: dy, anchorRight: !fromCenter, anchorBottom: fromCenter) }
            
                case .bottomRight:
            if fromCenter {
                cropRight = clamp(dragStartRight + dx, min: centerX + 5, max: 100)
                cropLeft = clamp(dragStartLeft - dx, min: 0, max: centerX - 5)
                cropBottom = clamp(dragStartBottom + dy, min: centerY + 5, max: 100)
                cropTop = clamp(dragStartTop - dy, min: 0, max: centerY - 5)
            } else {
                    cropRight = clamp(dragStartRight + dx, min: cropLeft + 10, max: 100)
                    cropBottom = clamp(dragStartBottom + dy, min: cropTop + 10, max: 100)
                }
            if lockRatio { adjustForCornerRatio(dx: dx, dy: dy, anchorRight: fromCenter, anchorBottom: fromCenter) }
        }
    }
    
    // Handle both modifiers together - resize from center while maintaining ratio
    private func applyDragCenteredWithRatio(edge: CropEdge, dx: Double, dy: Double, centerX: Double, centerY: Double) {
        // Determine the dominant axis movement
        let absDx = abs(dx)
        let absDy = abs(dy)
        
        // For corners and edges, use the dominant direction
        let useHorizontal: Bool
        switch edge {
        case .left, .right: useHorizontal = true
        case .top, .bottom: useHorizontal = false
        case .topLeft, .topRight, .bottomLeft, .bottomRight: useHorizontal = absDx >= absDy
        }
        
        if useHorizontal {
            // Calculate new width from horizontal movement
            let delta: Double
            switch edge {
            case .left, .topLeft, .bottomLeft: delta = -dx
            default: delta = dx
            }
            
            let halfWidth = (dragStartRight - dragStartLeft) / 2 + delta
            let newLeft = clamp(centerX - halfWidth, min: 0, max: centerX - 5)
            let newRight = clamp(centerX + halfWidth, min: centerX + 5, max: 100)
            
            cropLeft = newLeft
            cropRight = newRight
            
            // Adjust height to maintain ratio, centered
            let currentWidth = cropRight - cropLeft
            let targetHeight = currentWidth * originalAspectRatio / dragStartAspectRatio
            let halfHeight = targetHeight / 2
            
            cropTop = clamp(centerY - halfHeight, min: 0, max: centerY - 5)
            cropBottom = clamp(centerY + halfHeight, min: centerY + 5, max: 100)
        } else {
            // Calculate new height from vertical movement
            let delta: Double
            switch edge {
            case .top, .topLeft, .topRight: delta = -dy
            default: delta = dy
            }
            
            let halfHeight = (dragStartBottom - dragStartTop) / 2 + delta
            let newTop = clamp(centerY - halfHeight, min: 0, max: centerY - 5)
            let newBottom = clamp(centerY + halfHeight, min: centerY + 5, max: 100)
            
            cropTop = newTop
            cropBottom = newBottom
            
            // Adjust width to maintain ratio, centered
            let currentHeight = cropBottom - cropTop
            let targetWidth = currentHeight * dragStartAspectRatio / originalAspectRatio
            let halfWidth = targetWidth / 2
            
            cropLeft = clamp(centerX - halfWidth, min: 0, max: centerX - 5)
            cropRight = clamp(centerX + halfWidth, min: centerX + 5, max: 100)
        }
    }
    
    // Adjust height to maintain aspect ratio (when width changed)
    private func adjustHeightForRatio(fromCenter: Bool) {
        let currentWidth = cropRight - cropLeft
        let targetHeight = currentWidth * originalAspectRatio / dragStartAspectRatio
        
        if fromCenter {
            let centerY = (dragStartTop + dragStartBottom) / 2
            let halfHeight = targetHeight / 2
            cropTop = clamp(centerY - halfHeight, min: 0, max: 90)
            cropBottom = clamp(centerY + halfHeight, min: 10, max: 100)
        } else {
            let centerY = (cropTop + cropBottom) / 2
            let halfHeight = targetHeight / 2
            cropTop = clamp(centerY - halfHeight, min: 0, max: 90)
            cropBottom = clamp(centerY + halfHeight, min: 10, max: 100)
        }
    }
    
    // Adjust width to maintain aspect ratio (when height changed)
    private func adjustWidthForRatio(fromCenter: Bool) {
        let currentHeight = cropBottom - cropTop
        let targetWidth = currentHeight * dragStartAspectRatio / originalAspectRatio
        
        if fromCenter {
            let centerX = (dragStartLeft + dragStartRight) / 2
            let halfWidth = targetWidth / 2
            cropLeft = clamp(centerX - halfWidth, min: 0, max: 90)
            cropRight = clamp(centerX + halfWidth, min: 10, max: 100)
        } else {
            let centerX = (cropLeft + cropRight) / 2
            let halfWidth = targetWidth / 2
            cropLeft = clamp(centerX - halfWidth, min: 0, max: 90)
            cropRight = clamp(centerX + halfWidth, min: 10, max: 100)
        }
    }
    
    // Adjust for corner drag with ratio lock
    private func adjustForCornerRatio(dx: Double, dy: Double, anchorRight: Bool, anchorBottom: Bool) {
        let absDx = abs(dx)
        let absDy = abs(dy)
        
        if absDx > absDy {
            let currentWidth = cropRight - cropLeft
            let targetHeight = currentWidth * originalAspectRatio / dragStartAspectRatio
            
            if anchorBottom {
                cropTop = clamp(cropBottom - targetHeight, min: 0, max: cropBottom - 10)
            } else {
                cropBottom = clamp(cropTop + targetHeight, min: cropTop + 10, max: 100)
            }
        } else {
            let currentHeight = cropBottom - cropTop
            let targetWidth = currentHeight * dragStartAspectRatio / originalAspectRatio
            
            if anchorRight {
                cropLeft = clamp(cropRight - targetWidth, min: 0, max: cropRight - 10)
            } else {
                cropRight = clamp(cropLeft + targetWidth, min: cropLeft + 10, max: 100)
            }
            }
    }
    
    private func clamp(_ value: Double, min minVal: Double, max maxVal: Double) -> Double {
        return Swift.min(Swift.max(value, minVal), maxVal)
    }
    
    // Sync crop values to the manager's advancedOptions
    private func syncCropToManager() {
        manager.advancedOptions.cropLeft = cropLeft
        manager.advancedOptions.cropRight = cropRight
        manager.advancedOptions.cropTop = cropTop
        manager.advancedOptions.cropBottom = cropBottom
    }
    
    private func applyAspectRatio(_ aspect: AspectRatio) {
        guard let ratio = aspect.ratio else {
            // Original - reset to full
            cropLeft = 0
            cropRight = 100
            cropTop = 0
            cropBottom = 100
            syncDragStartValues()
            syncCropToManager()
            return
        }
        
        let currentWidth = cropRight - cropLeft
        let currentHeight = cropBottom - cropTop
        let currentAspect = (currentWidth / currentHeight) * originalAspectRatio
        
        if ratio > currentAspect {
            let newHeight = currentWidth * originalAspectRatio / ratio
            let diff = currentHeight - newHeight
            cropTop += diff / 2
            cropBottom -= diff / 2
        } else {
            let newWidth = currentHeight * ratio / originalAspectRatio
            let diff = currentWidth - newWidth
            cropLeft += diff / 2
            cropRight -= diff / 2
        }
        syncDragStartValues()
        syncCropToManager()
    }
    
    private func syncDragStartValues() {
        dragStartLeft = cropLeft
        dragStartRight = cropRight
        dragStartTop = cropTop
        dragStartBottom = cropBottom
        dragStartAspectRatio = currentCropAspectRatio
    }
}

// MARK: - Output Size Section

struct OutputSizeSection: View {
    @EnvironmentObject var manager: ConversionManager
    let originalResolution: Resolution?
    
    @State private var selectedPreset: ResolutionOverride = .original
    
    // Computed cropped dimensions based on manager's crop settings
    private var croppedWidth: Int {
        guard let res = originalResolution else { return 0 }
        return Int(Double(res.width) * (manager.advancedOptions.cropRight - manager.advancedOptions.cropLeft) / 100)
    }
    
    private var croppedHeight: Int {
        guard let res = originalResolution else { return 0 }
        return Int(Double(res.height) * (manager.advancedOptions.cropBottom - manager.advancedOptions.cropTop) / 100)
    }
    
    var body: some View {
        OptionCard(title: "Output Size") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 75, maximum: 95), spacing: 8)], spacing: 8) {
                    ForEach(ResolutionOverride.allCases) { preset in
                        Button {
                            withAnimation(.spring(response: 0.2)) {
                                selectedPreset = preset
                                manager.advancedOptions.resolutionOverride = preset
                            }
                        } label: {
                            Text(preset.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(selectedPreset == preset ? .white : .primary.opacity(0.8))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedPreset == preset ? Color(hex: "3B82F6") : .primary.opacity(0.05))
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Show cropped dimensions (or original if no cropping)
                if originalResolution != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                        if manager.advancedOptions.hasCropping {
                            Text("Original: \(croppedWidth.formatted())×\(croppedHeight.formatted()) (cropped)")
                                .font(.system(size: 11))
                        } else if let res = originalResolution {
                            Text("Original: \(res.description)")
                                .font(.system(size: 11))
                        }
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
    }
}


// MARK: - Aspect Ratio

enum AspectRatio: String, CaseIterable, Identifiable {
    case original = "Original"
    case square = "1:1"
    case portrait = "4:5"
    case landscape = "16:9"
    case cinematic = "21:9"
    case story = "9:16"
    
    var id: String { rawValue }
    
    var label: String { rawValue }
    
    var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .square: return 1
        case .portrait: return 4/5
        case .landscape: return 16/9
        case .cinematic: return 21/9
        case .story: return 9/16
        }
    }
    
    var description: String {
        switch self {
        case .original: return "Keep original aspect ratio"
        case .square: return "Perfect for Instagram posts"
        case .portrait: return "Instagram & Facebook posts"
        case .landscape: return "YouTube & widescreen displays"
        case .cinematic: return "Ultra-wide cinematic look"
        case .story: return "Instagram & TikTok stories"
        }
    }
}

// MARK: - Option Card

struct OptionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.primary.opacity(0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
                }
        }
    }
}

// MARK: - Format Cell

struct FormatCell: View {
    let format: OutputFormat
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Text(format.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isSelected ? .white : .primary.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? format.color : .primary.opacity(isHovered ? 0.06 : 0.03))
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Quality Cell

struct QualityCell: View {
    let preset: QualityPreset
    let isSelected: Bool
    let action: () -> Void
    
    private var color: Color {
        switch preset {
        case .fast: return Color(hex: "22C55E")
        case .balanced: return Color(hex: "3B82F6")
        case .quality: return Color(hex: "A855F7")
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: preset.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isSelected ? color : .secondary)
                
                Text(preset.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color.opacity(0.1) : .primary.opacity(0.02))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? color.opacity(0.3) : .clear, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Convert Action

struct ConvertAction: View {
    let tool: ConversionTool
    let action: () -> Void
    @State private var isHovered = false
    
    private var buttonLabel: String {
        switch tool {
        case .convert: return "Convert"
        case .compress: return "Compress"
        case .extractAudio: return "Extract Audio"
        case .trim: return "Trim Video"
        case .toGif: return "Create GIF"
        case .resize: return "Apply Changes"
        }
    }
    
    private var buttonIcon: String {
        switch tool {
        case .convert: return "arrow.triangle.2.circlepath"
        case .compress: return "archivebox"
        case .extractAudio: return "waveform"
        case .trim: return "scissors"
        case .toGif: return "photo.stack"
        case .resize: return "crop"
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: buttonIcon)
                    .font(.system(size: 14, weight: .semibold))
                Text(buttonLabel)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tool.color)
            }
            .shadow(color: tool.color.opacity(isHovered ? 0.4 : 0.25), radius: isHovered ? 16 : 10, y: 4)
            .scaleEffect(isHovered ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25)) { isHovered = hovering }
        }
    }
}

// MARK: - Supporting Types

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

struct WindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .windowBackground
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

extension MediaType {
    var color: Color {
        switch self {
        case .video: return Color(hex: "3B82F6")
        case .audio: return Color(hex: "F97316")
        case .image: return Color(hex: "22C55E")
        case .unknown: return .secondary
        }
    }
}

extension MediaType: RawRepresentable {
    public init?(rawValue: String) {
        switch rawValue {
        case "Video": self = .video
        case "Audio": self = .audio
        case "Image": self = .image
        default: self = .unknown
        }
    }
    
    public var rawValue: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .image: return "Image"
        case .unknown: return "File"
        }
    }
}

struct GlassDivider: View {
    var body: some View {
        Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
    }
}

#Preview {
    ContentView()
        .environmentObject(ConversionManager())
        .frame(width: 800, height: 600)
}
