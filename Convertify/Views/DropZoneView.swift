//
//  DropZoneView.swift
//  Convertify
//
//  Drag-and-drop area for media files
//

import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @Binding var isTargeted: Bool
    let onDrop: ([NSItemProvider]) -> Bool
    let onBrowse: () -> Void
    
    @State private var isHovered = false
    @State private var pulseAnimation = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Animated icon
            ZStack {
                // Pulse rings
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 80 + CGFloat(i * 20), height: 80 + CGFloat(i * 20))
                        .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.5)
                        .animation(
                            .easeInOut(duration: 2)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.3),
                            value: pulseAnimation
                        )
                }
                
                // Center icon
                ZStack {
                    Circle()
                        .fill(.linearGradient(
                            colors: isTargeted ? [.blue.opacity(0.3), .purple.opacity(0.3)] : [.primary.opacity(0.05), .primary.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.doc")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.linearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .scaleEffect(isTargeted ? 1.2 : 1.0)
                }
            }
            .animation(.spring(response: 0.3), value: isTargeted)
            
            // Text
            VStack(spacing: 8) {
                Text(isTargeted ? "Release to add file" : "Drop video or audio here")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.9))
                
                Text("or")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                
                Button(action: onBrowse) {
                    Text("Browse files")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            Capsule()
                                .fill(Color.blue.opacity(0.1))
                        }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            
            // Supported formats
            HStack(spacing: 6) {
                ForEach(["MP4", "MOV", "MKV", "MP3", "WAV"], id: \.self) { format in
                    Text(format)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(Color.primary.opacity(0.05))
                        }
                }
                Text("+ more")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            LinearGradient(
                                colors: isTargeted ? [.blue, .purple] : [.primary.opacity(0.1), .primary.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: isTargeted ? 3 : 2, dash: isTargeted ? [] : [8, 6])
                        )
                }
                .shadow(color: isTargeted ? .blue.opacity(0.2) : .clear, radius: 20)
        }
        .scaleEffect(isTargeted ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            onDrop(providers)
        }
        .onTapGesture {
            onBrowse()
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onAppear {
            pulseAnimation = true
        }
    }
}

// MARK: - Preview

#Preview {
    DropZoneView(
        isTargeted: .constant(false),
        onDrop: { _ in true },
        onBrowse: {}
    )
    .padding()
    .frame(width: 480, height: 350)
}

