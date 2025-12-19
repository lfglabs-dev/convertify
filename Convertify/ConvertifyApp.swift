//
//  ConvertifyApp.swift
//  Convertify
//
//  A beautiful native macOS FFmpeg wrapper
//

import SwiftUI
import AppKit
import os.log

// Debug logger that writes to both console and file
private let logger = Logger(subsystem: "md.thomas.convertify", category: "conversion")

func debugLog(_ message: String) {
    logger.info("\(message)")
    
    // Print to stderr
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] \(message)\n"
    fputs(logMessage, stderr)
    fflush(stderr)
    
    // Also try NSLog which should always work
    NSLog("[Convertify] %@", message)
}

@main
struct ConvertifyApp: App {
    @StateObject private var conversionManager = ConversionManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        let args = CommandLine.arguments
        
        // Enable extra internal diagnostics when requested
        if args.contains("--debug") {
            ConvertifyDiagnostics.enabled = true
        }
        
        // Headless mode (skip UI entirely)
        if args.contains("--headless") || args.contains("--cli") {
            HeadlessCLI.run(args: args)
        }
        
        // Legacy/basic CLI test mode
        if args.contains("--test") {
            runCLITest(args: args)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(conversionManager)
        }
        .windowStyle(.hiddenTitleBar) // Use hiddenTitleBar to remove system titlebar/toolbar
        .defaultSize(width: 820, height: 700)
    }
}

// MARK: - CLI Test Mode
private func promptForInputFile(initialURL: URL?) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true
    
    if let initialURL {
        panel.directoryURL = initialURL.deletingLastPathComponent()
        panel.nameFieldStringValue = initialURL.lastPathComponent
    }
    
    NSApp.activate(ignoringOtherApps: true)
    return panel.runModal() == .OK ? panel.url : nil
}

func runCLITest(args: [String]) {
    print("=== Convertify CLI Test Mode ===")
    print("")
    
    // Find input file argument
    var inputPath: String? = nil
    var outputPath: String? = nil
    
    for i in 0..<args.count {
        if args[i] == "--input" && i + 1 < args.count {
            inputPath = args[i + 1]
        }
        if args[i] == "--output" && i + 1 < args.count {
            outputPath = args[i + 1]
        }
    }
    
    guard let input = inputPath else {
        print("Usage: Convertify --test --input <path> [--output <path>]")
        print("")
        print("Example:")
        print("  ./Convertify.app/Contents/MacOS/Convertify --test --input /path/to/video.mov --output /tmp/output.mp4")
        exit(1)
    }
    
    var inputURL = URL(fileURLWithPath: input)
    let outputURL: URL
    if let output = outputPath {
        outputURL = URL(fileURLWithPath: output)
    } else {
        outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("convertify_test_output.mp4")
    }
    
    // If sandbox blocks direct path access (e.g. Downloads), ask the user to re-select
    // the file via Open Panel to grant security-scoped access.
    if !FileManager.default.isReadableFile(atPath: inputURL.path) {
        print("Input path is not readable (likely sandbox).")
        print("An Open Panel will appear — please select the same file to grant access.")
        print("")
        
        guard let selected = promptForInputFile(initialURL: inputURL) else {
            print("Cancelled.")
            exit(1)
        }
        inputURL = selected
    }
    
    print("Input:  \(inputURL.path)")
    print("Output: \(outputURL.path)")
    print("")
    
    // Test 1: Check if file exists
    print("[Test 1] Checking if input file exists...")
    if FileManager.default.fileExists(atPath: inputURL.path) {
        print("  ✓ File exists")
    } else {
        print("  ✗ File does NOT exist!")
        exit(1)
    }
    
    // Test 2: Check file attributes
    print("[Test 2] Checking file attributes...")
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: inputURL.path)
        let size = (attrs[.size] as? Int64) ?? 0
        print("  ✓ File size: \(size) bytes")
    } catch {
        print("  ✗ Cannot read attributes: \(error)")
    }
    
    // Test 3: Try to read file data
    print("[Test 3] Checking file readability...")
    do {
        let handle = try FileHandle(forReadingFrom: inputURL)
        let data = handle.readData(ofLength: 1024)
        handle.closeFile()
        print("  ✓ Can read file data (\(data.count) bytes read)")
    } catch {
        print("  ✗ Cannot read file: \(error)")
    }
    
    // Test 4: Try security-scoped access
    print("[Test 4] Testing security-scoped access...")
    let didStart = inputURL.startAccessingSecurityScopedResource()
    print("  startAccessingSecurityScopedResource returned: \(didStart)")
    if didStart {
        inputURL.stopAccessingSecurityScopedResource()
    }
    
    // Test 5: Try creating a bookmark
    print("[Test 5] Testing bookmark creation...")
    do {
        let bookmark = try inputURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        print("  ✓ Bookmark created (\(bookmark.count) bytes)")
        
        // Try to resolve it
        var isStale = false
        if let resolved = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            print("  ✓ Bookmark resolved to: \(resolved.path)")
            print("  Bookmark is stale: \(isStale)")
        } else {
            print("  ✗ Could not resolve bookmark")
        }
    } catch {
        print("  ✗ Cannot create bookmark: \(error)")
    }
    
    // Test 6: Try FFmpeg/libav probe
    print("[Test 6] Testing FFmpeg input opening...")
    testFFmpegOpen(path: inputURL.path)
    
    // Test 7: Try full conversion
    print("[Test 7] Testing full conversion pipeline...")
    testConversion(inputURL: inputURL, outputURL: outputURL)
    
    print("")
    print("=== CLI Test Complete ===")
    exit(0)
}

func testFFmpegOpen(path: String) {
    print("  Probing file with MediaProbeService...")
    let probeService = MediaProbeService()
    let url = URL(fileURLWithPath: path)
    
    // Run probe synchronously for CLI test
    let semaphore = DispatchSemaphore(value: 0)
    var probeResult: MediaFile?
    var probeError: Error?
    
    Task {
        do {
            probeResult = try await probeService.probe(url: url, bookmarkData: nil)
        } catch {
            probeError = error
        }
        semaphore.signal()
    }
    
    _ = semaphore.wait(timeout: .now() + 10)
    
    if let file = probeResult {
        print("  ✓ Probe succeeded:")
        print("    Duration: \(file.duration)s (\(formatTimeForTest(file.duration)))")
        print("    Resolution: \(file.resolution?.description ?? "N/A")")
        print("    Video codec: \(file.videoCodec ?? "N/A")")
        print("    Audio codec: \(file.audioCodec ?? "N/A")")
        print("    Frame rate: \(file.frameRate.map { String(format: "%.2f fps", $0) } ?? "N/A")")
    } else if let error = probeError {
        print("  ✗ Probe failed: \(error)")
    } else {
        print("  ✗ Probe timed out")
    }
}

private func formatTimeForTest(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds) / 60
    let secs = Int(seconds) % 60
    let fraction = Int((seconds - Double(Int(seconds))) * 10)
    return String(format: "%d:%02d.%d", minutes, secs, fraction)
}

func testConversion(inputURL: URL, outputURL: URL) {
    print("  Starting conversion...")
    
    // Delete output if exists
    try? FileManager.default.removeItem(at: outputURL)
    
    let outExt = outputURL.pathExtension.lowercased()
    let outFormat = outExt.isEmpty ? "mp4" : outExt
    
    // Exercise the GIF pipeline (uses dedicated GifTranscoder)
    // Note: GIF muxer is not available in bundled FFmpegKit, so this will fail
    if outFormat == "gif" {
        do {
            let transcoder = GifTranscoder(
                inputPath: inputURL.path,
                outputPath: outputURL.path,
                fps: 15,
                width: 480,
                crop: nil,
                startTime: nil,
                endTime: nil
            )
            try transcoder.transcode { progress in
                let pct = Int(progress.percentage * 100)
                print("  Progress: \(pct)% (frame \(progress.frame), fps: \(Int(progress.fps)))")
            }
            print("  ✓ GIF completed!")
            
            if FileManager.default.fileExists(atPath: outputURL.path) {
                let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
                let size = (attrs?[.size] as? Int64) ?? 0
                print("  ✓ Output file created: \(size) bytes")
            } else {
                print("  ✗ Output file was not created")
            }
        } catch {
            print("  ✗ GIF failed: \(error)")
        }
        return
    }
    
    var config = TranscodingConfig(
        inputPath: inputURL.path,
        outputPath: outputURL.path,
        outputFormat: outFormat
    )
    
    // If output is audio-only, disable video and set a sane audio encoder.
    let audioOnlyFormats: Set<String> = ["mp3", "aac", "wav", "flac", "m4a", "ogg"]
    if audioOnlyFormats.contains(outFormat) {
        config.stripVideo = true
        switch outFormat {
        case "mp3":
            config.audioCodec = "mp3"
        case "aac", "m4a":
            config.audioCodec = "aac"
        case "wav":
            config.audioCodec = "pcm_s16le"
        case "flac":
            config.audioCodec = "flac"
        case "ogg":
            config.audioCodec = "libopus"
        default:
            break
        }
    } else {
        // Force a filter graph path (this is where the app was crashing).
        // `null` is a no-op filter, but still exercises graph creation/config.
        config.videoFilters = ["null"]
        
        // Match the app's default behavior on macOS: prefer VideoToolbox for H.264.
        config.videoCodec = "h264_videotoolbox"
        config.audioCodec = "aac"
    }
    
    let pipeline = TranscodingPipeline(config: config)
    
    do {
        try pipeline.transcode { progress in
            let pct = Int(progress.percentage * 100)
            print("  Progress: \(pct)% (frame \(progress.frame), speed: \(String(format: "%.1fx", progress.speed)))")
        }
        print("  ✓ Conversion completed!")
        
        // Check output
        if FileManager.default.fileExists(atPath: outputURL.path) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
            let size = (attrs?[.size] as? Int64) ?? 0
            print("  ✓ Output file created: \(size) bytes")
        } else {
            print("  ✗ Output file was not created")
        }
    } catch {
        print("  ✗ Conversion failed: \(error)")
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let trafficLights = TrafficLightsPositioner(offsetX: 19, offsetY: -15)
    
    /// URLs to open when the app launches (passed via command line or Finder)
    static var pendingURLs: [URL] = []
    
    /// Callback to notify ContentView of files to open
    static var onOpenURLs: (([URL]) -> Void)?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApplication.shared.windows {
                self.configureWindow(window)
                window.makeKeyAndOrderFront(nil)
            }
            
            // Process any pending URLs after UI is ready
            if !AppDelegate.pendingURLs.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    AppDelegate.onOpenURLs?(AppDelegate.pendingURLs)
                    AppDelegate.pendingURLs.removeAll()
                }
            }
        }
    }
    
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        debugLog("Open file request: \(filename)")
        
        if AppDelegate.onOpenURLs != nil {
            AppDelegate.onOpenURLs?([url])
        } else {
            // App not fully initialized yet, queue the URL
            AppDelegate.pendingURLs.append(url)
        }
        return true
    }
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        debugLog("Open files request: \(filenames)")
        
        if AppDelegate.onOpenURLs != nil {
            AppDelegate.onOpenURLs?(urls)
        } else {
            // App not fully initialized yet, queue the URLs
            AppDelegate.pendingURLs.append(contentsOf: urls)
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
        // NOTE: Making the whole background draggable conflicts with drag-based controls
        // (Trim range handles, sliders, crop controls). Keep window movement to the
        // titlebar region so gestures work reliably.
        window.isMovableByWindowBackground = false
        
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
    
    // Temp copy of input file (for sandbox compatibility)
    private var tempInputURL: URL?
    
    // Original user-selected URL (used to default save panel location)
    private var originalInputURL: URL?
    
    let ffmpegService = FFmpegService()
    let probeService = MediaProbeService()
    let hardwareDetector = HardwareDetector()
    
    var hardwareAcceleration: HardwareAcceleration {
        hardwareDetector.detectCapabilities()
    }
    
    func loadFile(from url: URL) async {
        // Reset file-specific options (trim times, cropping, etc.)
        advancedOptions = AdvancedOptions()
        originalInputURL = url
        
        // Clean up previous temp file if any
        if let oldTemp = tempInputURL {
            try? FileManager.default.removeItem(at: oldTemp)
            tempInputURL = nil
        }
        
        debugLog("=== LOAD FILE ===")
        debugLog("URL received: \(url.path)")
        debugLog("URL filename: \(url.lastPathComponent)")
        
        // Start security-scoped access
        let didStartAccess = url.startAccessingSecurityScopedResource()
        debugLog("Started access for loading: \(didStartAccess)")
        
        // Check file attributes while we have access
        var fileSize: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            fileSize = (attrs[.size] as? Int64) ?? 0
            debugLog("File size during load: \(fileSize) bytes")
        } else {
            debugLog("WARNING: Could not read file attributes!")
        }
        
        // STEP 1: Copy file to temp location FIRST (synchronous, while we have access)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
        
        var copySucceeded = false
        do {
            try FileManager.default.copyItem(at: url, to: tempURL)
            tempInputURL = tempURL
            copySucceeded = true
            debugLog("Copied input to temp: \(tempURL.path)")
            
            // Verify temp file size matches
            if let tempAttrs = try? FileManager.default.attributesOfItem(atPath: tempURL.path),
               let tempSize = tempAttrs[.size] as? Int64 {
                debugLog("Temp file size: \(tempSize) bytes (original: \(fileSize))")
                print("[GUI] Temp copy: \(tempSize) bytes")
                if tempSize != fileSize {
                    debugLog("WARNING: Temp file size mismatch!")
                }
            }
        } catch {
            debugLog("FAILED to copy to temp: \(error)")
            print("[GUI] Copy to temp FAILED: \(error)")
        }
        
        // STEP 2: Stop security-scoped access - we're done reading the original
        if didStartAccess {
            url.stopAccessingSecurityScopedResource()
            debugLog("Stopped security-scoped access")
        }
        
        // STEP 3: Probe the TEMP file (no security scope needed)
        let probeURL = copySucceeded ? tempURL : url
        var probedFile: MediaFile?
        
        do {
            let mediaFile = try await probeService.probe(url: probeURL, bookmarkData: nil)
            debugLog("Probe succeeded. File size: \(mediaFile.fileSize), duration: \(mediaFile.duration)s")
            print("[GUI] Probe succeeded - duration: \(mediaFile.duration)s")
            probedFile = mediaFile
        } catch {
            debugLog("Probe failed: \(error)")
            print("[GUI] Probe FAILED: \(error)")
        }
        
        // STEP 4: Create MediaFile with probed metadata
        let workingURL = tempInputURL ?? url
        
        if let probed = probedFile {
            let file = MediaFile(
                id: probed.id,
                url: workingURL,
                filename: url.lastPathComponent,  // Keep original name for display
                fileExtension: url.pathExtension,
                fileSize: probed.fileSize,
                duration: probed.duration,
                videoCodec: probed.videoCodec,
                audioCodec: probed.audioCodec,
                resolution: probed.resolution,
                frameRate: probed.frameRate,
                bitrate: probed.bitrate,
                audioSampleRate: probed.audioSampleRate,
                audioChannels: probed.audioChannels,
                bookmarkData: nil
            )
            self.inputFile = file
            print("[GUI] inputFile set with duration: \(file.duration)s")
            selectDefaultFormat(for: file)
        } else {
            // Probe failed, use basic info
            let basic = MediaFile.basic(url: workingURL, bookmarkData: nil)
            let file = MediaFile(
                id: basic.id,
                url: workingURL,
                filename: url.lastPathComponent,
                fileExtension: url.pathExtension,
                fileSize: fileSize > 0 ? fileSize : basic.fileSize,
                duration: basic.duration,
                videoCodec: basic.videoCodec,
                audioCodec: basic.audioCodec,
                resolution: basic.resolution,
                frameRate: basic.frameRate,
                bitrate: basic.bitrate,
                audioSampleRate: basic.audioSampleRate,
                audioChannels: basic.audioChannels,
                bookmarkData: nil
            )
            self.inputFile = file
            selectDefaultFormat(for: file)
        }
        
        debugLog("=== LOAD FILE COMPLETE ===")
    }
    
    private func selectDefaultFormat(for file: MediaFile) {
        switch file.mediaType {
        case .video:
            outputFormat = .mp4
        case .audio:
            outputFormat = .m4a
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
        guard let inputFile = inputFile else { 
            debugLog("No input file")
            return 
        }
        guard !isConverting else { 
            debugLog("Already converting")
            return 
        }
        
        debugLog("=== START CONVERSION ===")
        debugLog("Input file URL: \(inputFile.url.path)")
        debugLog("Input file size: \(inputFile.fileSize) bytes")
        debugLog("Input filename: \(inputFile.filename)")
        
        // Show save panel to get user-selected output location (required for sandbox)
        guard let outputURL = await showSavePanel(for: inputFile) else {
            debugLog("Save panel cancelled")
            return // User cancelled
        }
        
        debugLog("Output URL: \(outputURL.path)")
        
        // Note: inputFile.url already points to temp copy (created in loadFile)
        // This is necessary because FFmpeg can't use security-scoped bookmarks
        
        isConverting = true
        
        let job = ConversionJob(
            id: UUID(),
            inputFile: inputFile,  // Already using temp copy from loadFile
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
        
        debugLog("FFmpeg command built, starting transcode...")
        debugLog("Input (temp copy): \(inputFile.url.path)")
        debugLog("Output: \(outputURL.path)")
        
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
            
            debugLog("Effective duration: \(effectiveDuration)s")
            debugLog("About to start ffmpegService.execute loop")
            
            let stream = ffmpegService.execute(command: command, duration: effectiveDuration)
            debugLog("Got AsyncThrowingStream, starting iteration")
            
            for try await progress in stream {
                debugLog("Received progress update: \(Int(progress.percentage * 100))%")
                conversionJob?.progress = progress.percentage
                conversionJob?.status = .converting
                conversionJob?.currentTime = progress.currentTime
                conversionJob?.speed = progress.speed
            }
            
            debugLog("Loop finished, marking as completed")
            conversionJob?.status = .completed
            conversionJob?.progress = 1.0
            
            debugLog("Conversion completed!")
            NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: "")
        } catch {
            debugLog("Conversion error: \(error)")
            // Don't overwrite .cancelled status (already set by cancelConversion())
            if conversionJob?.status != .cancelled {
                conversionJob?.status = .failed(error.localizedDescription)
                
                // Show error alert for debugging
                let alert = NSAlert()
                alert.messageText = "Conversion Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
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
        // Clean up temp input copy if any
        if let oldTemp = tempInputURL {
            try? FileManager.default.removeItem(at: oldTemp)
            tempInputURL = nil
        }
        originalInputURL = nil
        inputFile = nil
        conversionJob = nil
        isConverting = false
        advancedOptions = AdvancedOptions()
    }
    
    /// Resets only tool-specific options while keeping the loaded file
    func resetToolOptions() {
        conversionJob = nil
        isConverting = false
        advancedOptions = AdvancedOptions()
        // Re-select default format based on current file
        if let file = inputFile {
            selectDefaultFormat(for: file)
        }
    }
    
    /// Shows a save panel for the user to select output location (required for sandbox permissions)
    private func showSavePanel(for inputFile: MediaFile) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSSavePanel()
            panel.title = "Save Converted File"
            panel.message = "Choose where to save the converted file"
            panel.nameFieldLabel = "Save As:"
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.allowsOtherFileTypes = false
            panel.allowedContentTypes = [outputFormat.utType]
            
            // Suggest a filename based on input
            let baseName = (inputFile.filename as NSString).deletingPathExtension
            panel.nameFieldStringValue = "\(baseName)_converted.\(outputFormat.fileExtension)"
            
            // Try to start in the same directory as the input file
            if let originalInputURL {
                panel.directoryURL = originalInputURL.deletingLastPathComponent()
            } else {
                panel.directoryURL = inputFile.url.deletingLastPathComponent()
            }
            
            // Try to get the main window for sheet presentation
            if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
                panel.beginSheetModal(for: window) { response in
                    if response == .OK {
                        continuation.resume(returning: panel.url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            } else {
                // Fallback to modal dialog if no window available
                panel.begin { response in
                    if response == .OK {
                        continuation.resume(returning: panel.url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}
