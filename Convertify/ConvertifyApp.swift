//
//  ConvertifyApp.swift
//  Convertify
//
//  A beautiful native macOS FFmpeg wrapper
//

import SwiftUI
import AppKit

@main
struct ConvertifyApp: App {
    @StateObject private var conversionManager = ConversionManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(conversionManager)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        // Default size is taller to ensure the full sidebar/navbar is visible without scrolling
        .defaultSize(width: 820, height: 700)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Activate the app and bring to front
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApplication.shared.windows {
                self.configureWindow(window)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Bring window to front when clicking dock icon
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // Ensure windows come to front when app becomes active
        for window in NSApplication.shared.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    func configureWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = nil
        
        // Ensure proper style mask for resizing
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        
        // Set proper window level and behavior
        window.level = .normal
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.isReleasedWhenClosed = false
        
        // Accept mouse events
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false
    }
}

// MARK: - Conversion Manager (Global State)

@MainActor
class ConversionManager: ObservableObject {
    @Published var inputFile: MediaFile?
    @Published var outputFormat: OutputFormat = .mp4
    @Published var qualityPreset: QualityPreset = .balanced
    @Published var conversionJob: ConversionJob?
    @Published var isConverting: Bool = false
    @Published var showAdvancedOptions: Bool = false
    @Published var advancedOptions: AdvancedOptions = AdvancedOptions()
    
    let ffmpegService = FFmpegService()
    let probeService = MediaProbeService()
    let hardwareDetector = HardwareDetector()
    
    var hardwareAcceleration: HardwareAcceleration {
        hardwareDetector.detectCapabilities()
    }
    
    func loadFile(from url: URL) async {
        // Reset file-specific options (trim times, cropping, etc.)
        advancedOptions = AdvancedOptions()
        
        do {
            let mediaFile = try await probeService.probe(url: url)
            self.inputFile = mediaFile
            selectDefaultFormat(for: mediaFile)
        } catch {
            let basicFile = MediaFile.basic(url: url)
            self.inputFile = basicFile
            selectDefaultFormat(for: basicFile)
        }
    }
    
    private func selectDefaultFormat(for file: MediaFile) {
        switch file.mediaType {
        case .video:
            outputFormat = .mp4
        case .audio:
            outputFormat = .mp3
        case .image:
            if let sameFormat = OutputFormat.imageFormats.first(where: { 
                $0.fileExtension == file.fileExtension 
            }) {
                outputFormat = sameFormat
            } else {
                outputFormat = .jpg
            }
        case .unknown:
            outputFormat = .mp4
        }
    }
    
    func startConversion() async {
        guard let inputFile = inputFile else { return }
        
        isConverting = true
        
        let outputURL = generateOutputURL(for: inputFile)
        
        let job = ConversionJob(
            id: UUID(),
            inputFile: inputFile,
            outputURL: outputURL,
            outputFormat: outputFormat,
            qualityPreset: qualityPreset,
            advancedOptions: advancedOptions,
            status: .preparing,
            progress: 0
        )
        
        conversionJob = job
        
        let command = FFmpegCommandBuilder.build(
            job: job,
            hardwareAcceleration: hardwareAcceleration
        )
        
        do {
            let duration = inputFile.duration > 0 ? inputFile.duration : 1
            
            for try await progress in ffmpegService.execute(command: command, duration: duration) {
                conversionJob?.progress = progress.percentage
                conversionJob?.status = .converting
                conversionJob?.currentTime = progress.currentTime
                conversionJob?.speed = progress.speed
            }
            
            conversionJob?.status = .completed
            conversionJob?.progress = 1.0
            
            NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: "")
        } catch {
            // Don't overwrite .cancelled status (already set by cancelConversion())
            if conversionJob?.status != .cancelled {
                conversionJob?.status = .failed(error.localizedDescription)
            }
        }
        
        isConverting = false
    }
    
    func cancelConversion() {
        ffmpegService.cancel()
        conversionJob?.status = .cancelled
        isConverting = false
    }
    
    func reset() {
        inputFile = nil
        conversionJob = nil
        isConverting = false
        advancedOptions = AdvancedOptions()
    }
    
    private func generateOutputURL(for inputFile: MediaFile) -> URL {
        let inputURL = inputFile.url
        let directory = inputURL.deletingLastPathComponent()
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let newName = "\(baseName)_converted.\(outputFormat.fileExtension)"
        
        var outputURL = directory.appendingPathComponent(newName)
        
        var counter = 1
        while FileManager.default.fileExists(atPath: outputURL.path) {
            let numberedName = "\(baseName)_converted_\(counter).\(outputFormat.fileExtension)"
            outputURL = directory.appendingPathComponent(numberedName)
            counter += 1
        }
        
        return outputURL
    }
}
