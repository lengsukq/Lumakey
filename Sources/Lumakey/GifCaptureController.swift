import AppKit
import CoreGraphics
import LumakeyCore
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

enum GifCapturePhase: Equatable {
    case idle
    case selectingRegion
    case recording(isPaused: Bool)
    case encoding
    case completed(GifFinalizeResult)
}

@MainActor
final class GifCaptureController: ObservableObject {
    static let shared = GifCaptureController()

    @Published private(set) var phase: GifCapturePhase = .idle
    @Published var options: GifRecordingOptions = GifRecordingOptions()
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var encodedFrameCount: Int = 0
    @Published private(set) var mergedFrameCount: Int = 0
    @Published private(set) var latestResult: GifFinalizeResult?

    var onRecordingCompleted: ((GifFinalizeResult) -> Void)?
    var onStatusMessage: ((String) -> Void)?
    var onDiagnostic: ((UserFacingDiagnostic) -> Void)?

    private var selectionPanel: CaptureOverlayPanel?
    private var hudPanel: GifHUDPanel?
    private var keyMonitor: Any?
    private var selectionSession: GifSelectionSession?
    private var captureTask: Task<Void, Never>?
    private var activeEncoder: GifStreamEncoder?
    private var pendingCompletionHandler: ((GifFinalizeResult) -> Void)?

    private init() {}

    var isActive: Bool { phase != .idle }

    func startInteractiveCapture(options overrideOptions: GifRecordingOptions? = nil, onComplete: ((GifFinalizeResult) -> Void)? = nil) {
        if case .recording = phase { hudPanel?.orderFrontRegardless(); return }
        if case .encoding = phase { return }
        cleanupAllResources(discardEncoder: true)
        if let overrideOptions { self.options = overrideOptions }
        self.pendingCompletionHandler = onComplete

        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            let err = LumakeyError.visionFailed("尚未授予“屏幕录制”权限，请在系统设置 -> 隐私与安全性 -> 屏幕录制 中勾选 Lumakey。")
            onDiagnostic?(err.diagnostic); onStatusMessage?(err.diagnostic.reason)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
            return
        }
        Task { [weak self] in await self?.prepareAndPresentSelection() }
    }

    func togglePauseResume() {
        guard case .recording(let isPaused) = phase else { return }
        phase = .recording(isPaused: !isPaused)
    }

    func finishRecording() {
        guard case .recording = phase, let encoder = activeEncoder else { return }
        captureTask?.cancel(); captureTask = nil; activeEncoder = nil; phase = .encoding

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await Task.detached(priority: .userInitiated) { try encoder.finalize() }.value
                _ = GifStreamEncoder.copyGifToPasteboard(at: result.fileURL)
                self.latestResult = result; self.phase = .completed(result)
                let sizeStr = FastFormatters.formatFileBytes(result.fileSizeBytes)
                self.onStatusMessage?("GIF 动图已复制 (\(sizeStr) · \(result.frameCount) 帧)，可直接 ⌘V 粘贴")
                self.onRecordingCompleted?(result); self.pendingCompletionHandler?(result); self.pendingCompletionHandler = nil
            } catch {
                self.cleanupAllResources(discardEncoder: false); self.phase = .idle
                self.onStatusMessage?(error.localizedDescription)
            }
        }
    }

    func cancelCapture() {
        cleanupAllResources(discardEncoder: true); phase = .idle
        onStatusMessage?("已取消 GIF 录制并清理临时缓冲")
    }

    func dismissCompletedHUD() { cleanupAllResources(discardEncoder: false); phase = .idle }

    func recordAgain() {
        let cb = pendingCompletionHandler; dismissCompletedHUD(); startInteractiveCapture(onComplete: cb)
    }

    func copyResultAgain(_ result: GifFinalizeResult) {
        if GifStreamEncoder.copyGifToPasteboard(at: result.fileURL) {
            onStatusMessage?("已重新复制 GIF 动图到剪贴板")
        }
    }

    func saveResultAs(_ result: GifFinalizeResult) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = "Lumakey-GIF-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).gif"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let dst = panel.url {
            try? FileManager.default.removeItem(at: dst); try? FileManager.default.copyItem(at: result.fileURL, to: dst)
            _ = GifStreamEncoder.copyGifToPasteboard(at: dst)
            onStatusMessage?("GIF 已另存为：\(dst.lastPathComponent)")
        }
    }

    func revealResultInFinder(_ result: GifFinalizeResult) { NSWorkspace.shared.activateFileViewerSelecting([result.fileURL]) }
    func previewResult(_ result: GifFinalizeResult) { NSWorkspace.shared.open(result.fileURL) }

    private func prepareAndPresentSelection() async {
        try? await Task.sleep(for: .milliseconds(100))
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let screenNum = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scDisplay = content.displays.first(where: { $0.displayID == CGDirectDisplayID(screenNum) }) ?? content.displays.first else {
                onStatusMessage?("未检测到可用显示器。"); return
            }
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let filter = SCContentFilter(display: scDisplay, excludingApplications: content.applications.filter { $0.processID == ownPID }, exceptingWindows: [])
            let scale = max(screen.backingScaleFactor, 1.0)
            let config = SCStreamConfiguration()
            config.width = max(2, Int(round(scDisplay.frame.width * scale)))
            config.height = max(2, Int(round(scDisplay.frame.height * scale)))
            config.showsCursor = false

            let preview = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let localBounds = CGRect(origin: .zero, size: scDisplay.frame.size)
            let windows: [DetectedScreenWindow] = content.windows.compactMap { win in
                guard win.isOnScreen, win.windowLayer == 0, win.owningApplication?.processID != ownPID, win.frame.width >= 36, win.frame.height >= 36 else { return nil }
                let local = CGRect(x: win.frame.minX - scDisplay.frame.minX, y: win.frame.minY - scDisplay.frame.minY, width: win.frame.width, height: win.frame.height).intersection(localBounds)
                guard !local.isNull, local.width >= 36, local.height >= 36 else { return nil }
                return DetectedScreenWindow(id: win.windowID, ownerName: win.owningApplication?.applicationName ?? "", title: win.title ?? "", frame: local)
            }
            let session = GifSelectionSession(baseImage: preview, screenBounds: localBounds, appKitScreenFrame: screen.frame, displayID: scDisplay.displayID, backingScale: scale, windows: windows, options: options)
            presentSelectionOverlay(session: session, on: screen)
        } catch {
            onStatusMessage?(error.localizedDescription)
        }
    }

    private func presentSelectionOverlay(session: GifSelectionSession, on screen: NSScreen) {
        selectionSession = session; phase = .selectingRegion
        selectionPanel = GifHUDPanel.presentSelection(
            session: session, on: screen,
            onStart: { [weak self] in self?.beginRecordingFromSelection() },
            onCancel: { [weak self] in self?.cancelCapture() }
        )
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .rightMouseDown]) { [weak self] event in
            guard let self, let current = self.selectionSession else { return event }
            if event.type == .rightMouseDown {
                if current.selectionRect != nil { current.selectionRect = nil } else { self.cancelCapture() }
                return nil
            }
            if event.keyCode == 53 { self.cancelCapture(); return nil }
            if (event.keyCode == 36 || event.keyCode == 76), current.selectionRect != nil {
                self.beginRecordingFromSelection(); return nil
            }
            return event
        }
    }

    private func beginRecordingFromSelection() {
        guard let session = selectionSession, let sel = session.selectionRect?.standardized, sel.width >= 12, sel.height >= 12 else { return }
        options = session.options
        let appKitRegion = session.appKitScreenRect(for: sel)
        let displayID = session.displayID, scale = session.backingScale, screenFrame = session.appKitScreenFrame

        closeSelectionPanel()
        elapsedSeconds = 0; encodedFrameCount = 0; mergedFrameCount = 0
        phase = .recording(isPaused: false)
        hudPanel = GifHUDPanel.present(near: appKitRegion, screenFrame: screenFrame, controller: self)

        let encoder = GifStreamEncoder(options: options)
        activeEncoder = encoder
        let hudWinID = hudPanel.map { CGWindowID($0.windowNumber) }
        captureTask = Task { [weak self] in
            await self?.runCaptureLoop(displayID: displayID, sourceRect: sel, scale: scale, hudWindowID: hudWinID, encoder: encoder)
        }
    }

    private func runCaptureLoop(displayID: CGDirectDisplayID, sourceRect: CGRect, scale: CGFloat, hudWindowID: CGWindowID?, encoder: GifStreamEncoder) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let scDisplay = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            cancelCapture(); return
        }
        let excluded = content.windows.filter { hudWindowID != nil && $0.windowID == hudWindowID }
        let filter = SCContentFilter(display: scDisplay, excludingWindows: excluded)
        let (capW, capH) = GifStreamEncoder.scaledDimensions(
            width: max(2, Int((sourceRect.width * scale).rounded())),
            height: max(2, Int((sourceRect.height * scale).rounded())),
            maxDimension: options.maxDimension
        )
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect; config.width = capW; config.height = capH
        config.showsCursor = options.showsCursor; config.scalesToFit = true

        let nominal = options.frameIntervalSeconds
        var lastUptime: TimeInterval?

        while !Task.isCancelled {
            guard case .recording(let isPaused) = phase else { break }
            if isPaused { lastUptime = nil; try? await Task.sleep(for: .milliseconds(80)); continue }
            let tickStart = ProcessInfo.processInfo.systemUptime
            guard let frame = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config), !Task.isCancelled else {
                try? await Task.sleep(for: .milliseconds(40)); continue
            }
            guard case .recording(let pausedAfter) = phase, !pausedAfter else { lastUptime = nil; continue }
            let now = ProcessInfo.processInfo.systemUptime
            let delta = lastUptime.map { min(max(now - $0, nominal * 0.4), 1.0) } ?? nominal
            lastUptime = now

            let stats = await Task.detached(priority: .userInitiated) {
                _ = encoder.appendFrame(frame, delaySeconds: delta)
                return (encoder.encodedFrameCount, encoder.mergedFrameCount, encoder.totalDurationSeconds)
            }.value
            encodedFrameCount = stats.0; mergedFrameCount = stats.1; elapsedSeconds = stats.2

            if elapsedSeconds >= Double(options.maxDurationSeconds) { finishRecording(); return }
            let waitMs = max(5, Int(((nominal - (ProcessInfo.processInfo.systemUptime - tickStart)) * 1000).rounded()))
            try? await Task.sleep(for: .milliseconds(waitMs))
        }
    }

    private func closeSelectionPanel() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
        selectionPanel?.orderOut(nil); selectionPanel?.contentView = nil; selectionPanel = nil
        selectionSession = nil
    }

    private func cleanupAllResources(discardEncoder: Bool) {
        captureTask?.cancel(); captureTask = nil
        closeSelectionPanel()
        if discardEncoder { activeEncoder?.discard() }
        activeEncoder = nil
        hudPanel?.orderOut(nil); hudPanel?.contentView = nil; hudPanel = nil
        elapsedSeconds = 0; encodedFrameCount = 0; mergedFrameCount = 0
        MemoryStats.reclaimFreeHeapPages()
    }
}
