//
//  ConversionPanelView.swift
//  Convertify
//
//  Format selection and quality presets with glass aesthetic
//

import SwiftUI

// MARK: - Format Picker Section

struct FormatPickerSection: View {
    @EnvironmentObject var manager: ConversionManager
    @State private var showingAllFormats = false
    
    private var isVideoInput: Bool {
        manager.inputFile?.isVideo ?? true
    }
    
    private var quickFormats: [OutputFormat] {
        if isVideoInput {
            return [.mp4, .mov, .mkv, .webm, .gif, .mp3]
        } else {
            return [.mp3, .aac, .wav, .flac, .m4a, .ogg]
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Output Format", systemImage: "doc.badge.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showingAllFormats.toggle()
                    }
                } label: {
                    Text(showingAllFormats ? "Less" : "All formats")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "3B82F6"))
                }
                .buttonStyle(.plain)
            }
            
            if showingAllFormats {
                VStack(alignment: .leading, spacing: 14) {
                    Text("VIDEO")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .tracking(1)
                    
                    formatGrid(formats: OutputFormat.videoFormats)
                    
                    Text("AUDIO")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .tracking(1)
                        .padding(.top, 6)
                    
                    formatGrid(formats: OutputFormat.audioFormats)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                formatGrid(formats: quickFormats)
            }
        }
    }
    
    private func formatGrid(formats: [OutputFormat]) -> some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 60, maximum: 75), spacing: 8)
        ], spacing: 8) {
            ForEach(formats) { format in
                GlassFormatPill(
                    format: format,
                    isSelected: manager.outputFormat == format,
                    action: {
                        withAnimation(.spring(response: 0.25)) {
                            manager.outputFormat = format
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Glass Format Pill

struct GlassFormatPill: View {
    let format: OutputFormat
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: format.icon)
                    .font(.system(size: 13))
                Text(format.rawValue)
                    .font(.system(size: 10, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundColor(isSelected ? .white : .primary.opacity(0.8))
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ?
                          AnyShapeStyle(.linearGradient(
                              colors: [Color(hex: "A855F7"), Color(hex: "3B82F6")],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing
                          )) :
                          AnyShapeStyle(.primary.opacity(isHovered ? 0.08 : 0.04))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? 
                                    .white.opacity(0.25) :
                                    .primary.opacity(isHovered ? 0.12 : 0.06),
                                lineWidth: 1
                            )
                    }
            }
            .shadow(color: isSelected ? Color(hex: "A855F7").opacity(0.25) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Quality Presets Section

struct QualityPresetsSection: View {
    @EnvironmentObject var manager: ConversionManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Quality", systemImage: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            HStack(spacing: 10) {
                ForEach(QualityPreset.allCases) { preset in
                    GlassQualityButton(
                        preset: preset,
                        isSelected: manager.qualityPreset == preset,
                        action: {
                            withAnimation(.spring(response: 0.25)) {
                                manager.qualityPreset = preset
                            }
                        }
                    )
                }
            }
            
            // Description with smooth transition
            Text(manager.qualityPreset.description)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))
                .animation(.easeInOut(duration: 0.2), value: manager.qualityPreset)
        }
    }
}

// MARK: - Glass Quality Button

struct GlassQualityButton: View {
    let preset: QualityPreset
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    private var gradientColors: [Color] {
        switch preset {
        case .fast: return [Color(hex: "22C55E"), Color(hex: "10B981")]
        case .balanced: return [Color(hex: "3B82F6"), Color(hex: "06B6D4")]
        case .quality: return [Color(hex: "A855F7"), Color(hex: "EC4899")]
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: preset.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        isSelected ? 
                            AnyShapeStyle(.linearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)) :
                            AnyShapeStyle(.secondary)
                    )
                
                Text(preset.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .primary.opacity(0.9) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.primary.opacity(isSelected ? 0.08 : (isHovered ? 0.05 : 0.02)))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: gradientColors.map { $0.opacity(0.5) },
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.2), value: isHovered)
        .animation(.spring(response: 0.2), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        FormatPickerSection()
        GlassDivider()
        QualityPresetsSection()
    }
    .padding(20)
    .background(Color.black.opacity(0.8))
    .environmentObject(ConversionManager())
    .frame(width: 440)
}
