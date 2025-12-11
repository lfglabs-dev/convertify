//
//  ProgressOverlayView.swift
//  Convertify
//
//  Minimal conversion progress overlay
//

import SwiftUI

struct ProgressOverlayView: View {
    @EnvironmentObject var manager: ConversionManager
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            // Card
            VStack(spacing: 24) {
                // Progress indicator
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(.primary.opacity(0.1), lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    // Progress arc
                    Circle()
                        .trim(from: 0, to: manager.conversionJob?.progress ?? 0)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "818CF8"), Color(hex: "A78BFA")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.3), value: manager.conversionJob?.progress)
                    
                    // Percentage
                    Text("\(manager.conversionJob?.progressPercentage ?? 0)%")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                }
                
                // Status
                VStack(spacing: 6) {
                    Text(manager.conversionJob?.status.label ?? "Converting...")
                        .font(.system(size: 14, weight: .medium))
                    
                    if let job = manager.conversionJob {
                        HStack(spacing: 12) {
                            if let speed = job.formattedSpeed {
                                Label(speed, systemImage: "speedometer")
                            }
                            if let etr = job.formattedETR {
                                Label(etr, systemImage: "clock")
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }
                }
                
                // Cancel button
                Button("Cancel") {
                    manager.cancelConversion()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            }
            .padding(32)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            }
            .frame(width: 240)
        }
    }
}

#Preview {
    let manager = ConversionManager()
    return ProgressOverlayView()
        .environmentObject(manager)
        .onAppear {
            manager.isConverting = true
            manager.conversionJob = ConversionJob(
                id: UUID(),
                inputFile: MediaFile.basic(url: URL(fileURLWithPath: "/test/video.mp4")),
                outputURL: URL(fileURLWithPath: "/test/output.mp4"),
                outputFormat: .mp4,
                qualityPreset: .balanced,
                advancedOptions: AdvancedOptions(),
                status: .converting,
                progress: 0.65
            )
        }
        .frame(width: 500, height: 400)
}
