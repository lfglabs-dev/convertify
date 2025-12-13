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
        .windowStyle(.hiddenTitleBar) // Use hiddenTitleBar to remove system titlebar/toolbar
        .defaultSize(width: 820, height: 700)
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let trafficLights = TrafficLightsPositioner(offsetX: 19, offsetY: -15)
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApplication.shared.windows {
                self.configureWindow(window)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        for window in NSApplication.shared.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    func configureWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = nil // Critical: removes glass titlebar
        
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.level = .normal
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true
        
        // Position traffic lights inside the floating sidebar
        trafficLights.attach(to: window)
    }
}

// MARK: - Traffic Lights Positioner

@MainActor
final class TrafficLightsPositioner {
    private let offsetX: CGFloat
    private let offsetY: CGFloat
    private var observers: [ObjectIdentifier: [NSObjectProtocol]] = [:]
    
    init(offsetX: CGFloat, offsetY: CGFloat) {
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
    
    func attach(to window: NSWindow) {
        let id = ObjectIdentifier(window)
        if observers[id] != nil { return }
        
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.apply(to: window)
        }
        
        let center = NotificationCenter.default
        var tokens: [NSObjectProtocol] = [
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window else { return }
                    self.apply(to: window)
                }
            },
            center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window else { return }
                    self.apply(to: window)
                }
            },
            center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window else { return }
                    self.apply(to: window)
                }
            }
        ]
        
        let closeObserver = center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] notification in
            guard let closingWindow = notification.object as? NSWindow else { return }
            let closingId = ObjectIdentifier(closingWindow)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let tokens = self.observers[closingId] {
                    tokens.forEach { NotificationCenter.default.removeObserver($0) }
                    self.observers.removeValue(forKey: closingId)
                }
            }
        }
        tokens.append(closeObserver)
        
        observers[id] = tokens
    }
    
    private func apply(to window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton) else { return }
        
        let baseline = Baseline.ensure(on: window, close: close.frame.origin, mini: mini.frame.origin, zoom: zoom.frame.origin)
        
        close.setFrameOrigin(NSPoint(x: baseline.close.x + offsetX, y: baseline.close.y + offsetY))
        mini.setFrameOrigin(NSPoint(x: baseline.mini.x + offsetX, y: baseline.mini.y + offsetY))
        zoom.setFrameOrigin(NSPoint(x: baseline.zoom.x + offsetX, y: baseline.zoom.y + offsetY))
    }
    
    private final class Baseline: NSObject {
        let close: NSPoint
        let mini: NSPoint
        let zoom: NSPoint
        
        init(close: NSPoint, mini: NSPoint, zoom: NSPoint) {
            self.close = close
            self.mini = mini
            self.zoom = zoom
        }
        
        static func ensure(on window: NSWindow, close: NSPoint, mini: NSPoint, zoom: NSPoint) -> Baseline {
            if let existing = objc_getAssociatedObject(window, &baselineKey) as? Baseline {
                return existing
            }
            let created = Baseline(close: close, mini: mini, zoom: zoom)
            objc_setAssociatedObject(window, &baselineKey, created, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return created
        }
    }
}

private var baselineKey: UInt8 = 0

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
        guard !isConverting else { return }
        
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
            // Calculate effective duration accounting for trimming
            let effectiveDuration: TimeInterval
            if advancedOptions.hasTrimming {
                let startTime = advancedOptions.startTime ?? 0
                let endTime = advancedOptions.endTime ?? inputFile.duration
                effectiveDuration = max(endTime - startTime, 1)
            } else {
                effectiveDuration = inputFile.duration > 0 ? inputFile.duration : 1
            }
            
            for try await progress in ffmpegService.execute(command: command, duration: effectiveDuration) {
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
