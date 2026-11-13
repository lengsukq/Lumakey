import AppKit
import CoreGraphics
import LumakeyCore
import ScreenCaptureKit
import SwiftUI

final class CaptureOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ScreenCaptureCoordinator {
    static let shared = ScreenCaptureCoordinator()

    private var overlayPanel: CaptureOverlayPanel?
    private var keyMonitor: Any?
    private var activeSession: ScreenshotSessionState?
    private var continuation: CheckedContinuation<ScreenshotResult, Error>?
    private var pasteboardSnapshot: PasteboardSnapshot?
    private var didModifyPasteboard = false

    private init() {}

    func capture(mode: ScreenshotMode) async throws -> ScreenshotResult {
        if overlayPanel != nil {
            finish(with: .cancelled)
        }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw LumakeyError.visionFailed("尚未授予“屏幕录制”权限，请在系统设置 -> 隐私与安全性 -> 屏幕录制 中勾选 Lumakey。")
        }

        try? await Task.sleep(for: .milliseconds(120))
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let screenNumber = (targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scDisplay = content.displays.first(where: { $0.displayID == CGDirectDisplayID(screenNumber) }) ?? content.displays.first else {
            throw LumakeyError.visionFailed("未检测到可用显示器。")
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }
        let filter = SCContentFilter(display: scDisplay, excludingApplications: ownApps, exceptingWindows: [])

        let config = SCStreamConfiguration()
        let scale = max(targetScreen.backingScaleFactor, 1.0)
        config.width = max(2, Int(round(scDisplay.frame.width * scale)))
        config.height = max(2, Int(round(scDisplay.frame.height * scale)))
        config.showsCursor = false

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let localBounds = CGRect(origin: .zero, size: scDisplay.frame.size)
        let detectedWindows: [DetectedScreenWindow] = content.windows.compactMap { win in
            guard win.isOnScreen, win.windowLayer == 0,
                  win.owningApplication?.processID != ownPID,
                  win.frame.width >= 36, win.frame.height >= 36 else { return nil }
            let local = CGRect(
                x: win.frame.minX - scDisplay.frame.minX,
                y: win.frame.minY - scDisplay.frame.minY,
                width: win.frame.width,
                height: win.frame.height
            ).intersection(localBounds)
            guard !local.isNull, local.width >= 36, local.height >= 36 else { return nil }
            return DetectedScreenWindow(
                id: win.windowID,
                ownerName: win.owningApplication?.applicationName ?? "",
                title: win.title ?? "",
                frame: local
            )
        }

        let session = ScreenshotSessionState(
            baseImage: cgImage,
            screenBounds: localBounds,
            appKitScreenFrame: targetScreen.frame,
            windows: detectedWindows,
            mode: mode
        )
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.presentOverlay(with: session, on: targetScreen)
        }
    }

    private func presentOverlay(with session: ScreenshotSessionState, on screen: NSScreen) {
        pasteboardSnapshot = PasteboardSnapshot.capture()
        didModifyPasteboard = false
        activeSession = session
        let panel = CaptureOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(rootView: ScreenshotCanvasView(
            session: session,
            onAction: { [weak self] action in self?.handleAction(action) }
        ))
        panel.setFrame(screen.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        overlayPanel = panel

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .rightMouseDown]) { [weak self] event in
            guard let self, let current = self.activeSession else { return event }
            if event.type == .rightMouseDown {
                if current.pendingTextPoint != nil {
                    current.pendingTextPoint = nil
                    current.pendingTextValue = ""
                } else if current.selectionRect != nil {
                    current.selectionRect = nil
                    current.clearAnnotations()
                    current.activeTool = .move
                } else {
                    self.finish(with: .cancelled)
                }
                return nil
            }
            if event.keyCode == 53 { // Esc
                if current.pendingTextPoint != nil {
                    current.pendingTextPoint = nil
                    current.pendingTextValue = ""
                } else {
                    self.finish(with: .cancelled)
                }
                return nil
            }
            if event.keyCode == 6, event.modifierFlags.contains(.command) { // Cmd+Z
                current.undoAnnotation()
                return nil
            }
            if current.pendingTextPoint == nil && (event.keyCode == 36 || event.keyCode == 76) { // Enter
                if current.selectionRect != nil {
                    self.handleAction(current.mode == .quickOCR ? .ocr : .copy)
                    return nil
                }
            }
            if current.pendingTextPoint == nil && event.keyCode == 8 && event.modifierFlags.contains(.command) { // Cmd+C
                if current.selectionRect != nil {
                    self.handleAction(.copy)
                    return nil
                }
            }
            if current.pendingTextPoint == nil && event.keyCode == 8 && !event.modifierFlags.contains(.command) { // C key
                self.didModifyPasteboard = false
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(current.cursorHex, forType: .string)
                current.bannerMessage = "已复制色值 \(current.cursorHex)"
                return nil
            }
            return event
        }
    }

    func handleAction(_ action: ScreenshotToolbarAction) {
        guard let session = activeSession else { return }
        session.commitTextAnnotation()
        switch action {
        case .cancel:
            finish(with: .cancelled)
        case .undo:
            session.undoAnnotation()
        case .clear:
            session.clearAnnotations()
        case .syncClipboard:
            syncSelectionIfPossible(session: session)
        case .copy, .pin, .ocr, .cutout, .save:
            guard let sel = session.selectionRect?.standardized, sel.width >= 4, sel.height >= 4 else { return }
            do {
                let composed = try ScreenshotCompositor.renderCroppedImage(
                    baseImage: session.baseImage,
                    screenBounds: session.screenBounds,
                    selectionRect: sel,
                    annotations: session.annotations
                )
                performExport(action: action, image: composed, session: session)
            } catch {
                session.bannerMessage = error.localizedDescription
            }
        }
    }

    private func syncSelectionIfPossible(session: ScreenshotSessionState) {
        guard session.mode == .interactiveAnnotate,
              let sel = session.selectionRect?.standardized,
              sel.width >= 4, sel.height >= 4 else { return }
        if let composed = try? ScreenshotCompositor.renderCroppedImage(
            baseImage: session.baseImage, screenBounds: session.screenBounds,
            selectionRect: sel, annotations: session.annotations
        ) {
            copyComposedToPasteboard(composed, session: session)
            session.bannerMessage = "✓ 已自动放入剪贴板 · 可直接粘贴、标注或按回车完成"
        }
    }

    private func copyComposedToPasteboard(_ image: CGImage, session: ScreenshotSessionState) {
        ScreenshotCompositor.copyImageToPasteboard(image, scale: session.backingScale)
        didModifyPasteboard = true
        session.hasAutoCopied = true
    }

    private func performExport(action: ScreenshotToolbarAction, image: CGImage, session: ScreenshotSessionState) {
        do {
            switch action {
            case .copy:
                let url = try ScreenshotCompositor.saveTempCapture(image)
                copyComposedToPasteboard(image, session: session)
                finish(with: .copied(url))
            case .pin:
                let url = try ScreenshotCompositor.saveTempCapture(image)
                copyComposedToPasteboard(image, session: session)
                let rect = session.screenRectForSelection() ?? NSRect(x: 200, y: 260, width: 360, height: 240)
                finish(with: .pinned(url, rect))
            case .ocr:
                let url = try ScreenshotCompositor.saveTempCapture(image)
                finish(with: .ocrRequested(url))
            case .cutout:
                let url = try ScreenshotCompositor.saveTempCapture(image)
                copyComposedToPasteboard(image, session: session)
                finish(with: .cutoutRequested(url))
            case .save:
                overlayPanel?.level = .normal
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.png]
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                panel.nameFieldStringValue = "Lumakey-\(stamp).png"
                if panel.runModal() == .OK, let url = panel.url {
                    try ScreenshotCompositor.writePNG(image, to: url)
                    copyComposedToPasteboard(image, session: session)
                    finish(with: .saved(url))
                } else {
                    overlayPanel?.level = .screenSaver
                }
            default:
                break
            }
        } catch {
            session.bannerMessage = error.localizedDescription
        }
    }

    private func finish(with result: ScreenshotResult) {
        if case .cancelled = result, didModifyPasteboard {
            pasteboardSnapshot?.restore()
        }
        pasteboardSnapshot = nil
        didModifyPasteboard = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        overlayPanel?.orderOut(nil)
        overlayPanel?.contentView = nil
        overlayPanel = nil
        activeSession = nil
        let cont = continuation
        continuation = nil
        cont?.resume(returning: result)
        MemoryStats.reclaimFreeHeapPages()
    }
}
