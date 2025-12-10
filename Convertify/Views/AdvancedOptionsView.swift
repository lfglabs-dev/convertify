//
//  AdvancedOptionsView.swift
//  Convertify
//
//  Advanced encoding options
//

import SwiftUI

struct AdvancedOptionsView: View {
    @EnvironmentObject var manager: ConversionManager
    
    var body: some View {
        VStack(spacing: 20) {
            // Resolution
            ResolutionRow()
            
            Divider().opacity(0.5)
            
            // Audio (only for video/audio files)
            if manager.inputFile?.isImage != true {
                AudioRow()
                
                Divider().opacity(0.5)
                
                // Trimming
                TrimmingRow()
                
                Divider().opacity(0.5)
            }
            
            // Custom args
            CustomArgsRow()
        }
    }
}

// MARK: - Resolution Row

struct ResolutionRow: View {
    @EnvironmentObject var manager: ConversionManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Resolution")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ResolutionOverride.allCases) { option in
                        OptionChip(
                            text: option.rawValue,
                            isSelected: manager.advancedOptions.resolutionOverride == option
                        ) {
                            manager.advancedOptions.resolutionOverride = option
                        }
                    }
                }
            }
            
            if manager.advancedOptions.resolutionOverride == .custom {
                HStack(spacing: 12) {
                    CompactTextField(
                        label: "W",
                        value: Binding(
                            get: { manager.advancedOptions.customResolution?.width ?? 1920 },
                            set: {
                                let h = manager.advancedOptions.customResolution?.height ?? 1080
                                manager.advancedOptions.customResolution = Resolution(width: $0, height: h)
                            }
                        )
                    )
                    
                    Text("×")
                        .foregroundColor(.secondary)
                    
                    CompactTextField(
                        label: "H",
                        value: Binding(
                            get: { manager.advancedOptions.customResolution?.height ?? 1080 },
                            set: {
                                let w = manager.advancedOptions.customResolution?.width ?? 1920
                                manager.advancedOptions.customResolution = Resolution(width: w, height: $0)
                            }
                        )
                    )
                    
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3), value: manager.advancedOptions.resolutionOverride)
    }
}

// MARK: - Audio Row

struct AudioRow: View {
    @EnvironmentObject var manager: ConversionManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Audio")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                CompactPicker(label: "Codec", selection: $manager.advancedOptions.audioCodec, options: AudioCodecOption.allCases)
                CompactPicker(label: "Bitrate", selection: $manager.advancedOptions.audioBitrate, options: AudioBitrateOption.allCases)
            }
        }
    }
}

// MARK: - Trimming Row

struct TrimmingRow: View {
    @EnvironmentObject var manager: ConversionManager
    @State private var enableTrimming = false
    
    private var duration: TimeInterval {
        manager.inputFile?.duration ?? 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trim")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Toggle("", isOn: $enableTrimming)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
                    .labelsHidden()
                    .onChange(of: enableTrimming) { _, enabled in
                        if !enabled {
                            manager.advancedOptions.startTime = nil
                            manager.advancedOptions.endTime = nil
                        }
                    }
            }
            
            if enableTrimming {
                HStack(spacing: 12) {
                    TimeField(
                        label: "Start",
                        value: Binding(
                            get: { manager.advancedOptions.startTime ?? 0 },
                            set: { manager.advancedOptions.startTime = $0 > 0 ? $0 : nil }
                        )
                    )
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    TimeField(
                        label: "End",
                        value: Binding(
                            get: { manager.advancedOptions.endTime ?? duration },
                            set: { manager.advancedOptions.endTime = $0 < duration ? $0 : nil }
                        )
                    )
                    
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3), value: enableTrimming)
    }
}

// MARK: - Custom Args Row

struct CustomArgsRow: View {
    @EnvironmentObject var manager: ConversionManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom FFmpeg Arguments")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            TextField("e.g., -vf \"hue=s=0\"", text: $manager.advancedOptions.customFFmpegArgs)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.primary.opacity(0.04))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                        }
                }
        }
    }
}

// MARK: - Components

struct OptionChip: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? .white : .primary.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(isSelected ? Color(hex: "6366F1") : .primary.opacity(0.06))
                }
        }
        .buttonStyle(.plain)
    }
}

struct CompactTextField: View {
    let label: String
    @Binding var value: Int
    
    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            
            TextField("", value: $value, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 60)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.primary.opacity(0.04))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                        }
                }
        }
    }
}

struct CompactPicker<T: Hashable & Identifiable & RawRepresentable>: View where T.RawValue == String {
    let label: String
    @Binding var selection: T
    let options: [T]
    
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            
            Picker("", selection: $selection) {
                ForEach(options) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 80)
        }
    }
}

struct TimeField: View {
    let label: String
    @Binding var value: TimeInterval
    
    @State private var text: String = "00:00"
    
    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            
            TextField("00:00", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 50)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.primary.opacity(0.04))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                        }
                }
                .onAppear { text = formatTime(value) }
                .onChange(of: text) { _, newValue in
                    if let parsed = parseTime(newValue) { value = parsed }
                }
                .onChange(of: value) { _, newValue in
                    text = formatTime(newValue)
                }
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
    
    private func parseTime(_ string: String) -> TimeInterval? {
        let parts = string.split(separator: ":")
        guard parts.count == 2,
              let mins = Int(parts[0]),
              let secs = Int(parts[1]) else { return nil }
        return TimeInterval(mins * 60 + secs)
    }
}

#Preview {
    AdvancedOptionsView()
        .environmentObject(ConversionManager())
        .padding()
        .frame(width: 400)
}
