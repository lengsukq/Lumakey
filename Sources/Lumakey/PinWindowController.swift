import AppKit
import LumakeyCore
import SwiftUI

final class KeyablePinPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class PinWindowController {
    static let shared = PinWindowController()
    private var panels: [NSPanel] = []

    func pinImage(at url: URL, screenRect: NSRect? = nil) {
        guard let nsImage = NSImage(contentsOf: url) else { return }
        let ratio = nsImage.size.height > 0 ? (nsImage.size.width / nsImage.size.height) : 1.0
        let rect: NSRect
        if let screenRect, screenRect.width >= 40, screenRect.height >= 40 {
            rect = screenRect
        } else {
            let width = min(max(nsImage.size.width, 260), 580)
            let height = min(max(width / max(ratio, 0.25), 180), 500)
            rect = NSRect(x: 180 + CGFloat(panels.count * 28), y: 260, width: width, height: height)
        }

        let panel = KeyablePinPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.minSize = NSSize(width: 96, height: 64)
        panel.contentAspectRatio = rect.size
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let closeAction: () -> Void = { [weak self, weak panel] in
            guard let panel else { return }
            panel.contentView = nil
            panel.close()
            self?.panels.removeAll { $0 === panel }
            let name = url.lastPathComponent
            if name.hasPrefix("lumakey-pin-") || name.hasPrefix("cutout-") {
                try? FileManager.default.removeItem(at: url)
            }
            MemoryStats.reclaimFreeHeapPages()
        }
        panel.onEscape = closeAction

        let view = PinnedImageOverlayView(
            image: nsImage,
            imageURL: url,
            aspectRatio: max(ratio, 0.1),
            onPinCutout: { [weak self] cutoutURL in self?.pinImage(at: cutoutURL) },
            onResetOriginalSize: { [weak panel] in
                guard let panel else { return }
                let screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
                let w = min(max(nsImage.size.width, 140), screen.width * 0.88)
                let h = w / max(ratio, 0.1)
                let next = NSRect(x: panel.frame.midX - w / 2, y: panel.frame.midY - h / 2, width: w, height: h)
                panel.setFrame(next, display: true, animate: true)
            },
            onCloseAll: { [weak self] in self?.closeAll() },
            onClose: closeAction
        )
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 16
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
        panel.orderFrontRegardless()
        panels.append(panel)
    }

    func closeAll() {
        for panel in panels {
            panel.contentView = nil
            panel.close()
        }
        panels.removeAll()
        MemoryStats.reclaimFreeHeapPages()
    }
}

struct PinMenuCallbacks {
    let copyImage: () -> Void
    let runOCR: () -> Void
    let runCutout: () -> Void
    let resetSize: () -> Void
    let toggleOpacity: () -> Void
    let savePNG: () -> Void
    let closeThis: () -> Void
    let closeAll: () -> Void
}

struct PinInteractionLayer: NSViewRepresentable {
    let aspectRatio: CGFloat
    let onDoubleClick: () -> Void
    let onAdjustOpacity: (Double) -> Void
    let onHoverChanged: (Bool) -> Void
    let menuCallbacks: PinMenuCallbacks

    func makeNSView(context: Context) -> PinInteractionNSView {
        let view = PinInteractionNSView()
        sync(view)
        return view
    }

    func updateNSView(_ nsView: PinInteractionNSView, context: Context) {
        sync(nsView)
    }

    private func sync(_ view: PinInteractionNSView) {
        view.aspectRatio = aspectRatio
        view.onDoubleClick = onDoubleClick
        view.onAdjustOpacity = onAdjustOpacity
        view.onHoverChanged = onHoverChanged
        view.menuCallbacks = menuCallbacks
    }
}

final class PinInteractionNSView: NSView {
    var aspectRatio: CGFloat = 1.0
    var onDoubleClick: (() -> Void)?
    var onAdjustOpacity: ((Double) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var menuCallbacks: PinMenuCallbacks?
    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY * 10
        guard abs(delta) > 0.05 else { return }
        if event.modifierFlags.contains(.option) {
            onAdjustOpacity?(delta > 0 ? 0.05 : -0.05)
            return
        }
        guard let win = window else { return }
        let factor: CGFloat = delta > 0 ? 1.06 : 0.94
        let visible = win.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let cur = win.frame
        let newW = min(max(96, cur.width * factor), visible.width * 0.92)
        let newH = max(64, newW / max(aspectRatio, 0.1))
        let next = NSRect(x: cur.midX - newW / 2, y: cur.midY - newH / 2, width: newW, height: newH)
        win.setFrame(next, display: true, animate: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let cb = menuCallbacks else { return nil }
        let menu = NSMenu()
        menu.addItem(PinMenuActionItem(title: "复制图片", action: cb.copyImage))
        menu.addItem(PinMenuActionItem(title: "离线识字 (OCR)", action: cb.runOCR))
        menu.addItem(PinMenuActionItem(title: "主体抠图", action: cb.runCutout))
        menu.addItem(.separator())
        menu.addItem(PinMenuActionItem(title: "100% 原始大小", action: cb.resetSize))
        menu.addItem(PinMenuActionItem(title: "切换半透明对比 (⌥滚轮)", action: cb.toggleOpacity))
        menu.addItem(PinMenuActionItem(title: "另存为 PNG…", action: cb.savePNG))
        menu.addItem(.separator())
        menu.addItem(PinMenuActionItem(title: "关闭此钉图 (Esc)", action: cb.closeThis))
        menu.addItem(PinMenuActionItem(title: "关闭全部钉图", action: cb.closeAll))
        return menu
    }
}

@MainActor
private final class PinMenuActionItem: NSMenuItem {
    private let callback: () -> Void
    init(title: String, action: @escaping () -> Void) {
        self.callback = action
        super.init(title: title, action: #selector(handleTap), keyEquivalent: "")
        self.target = self
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func handleTap() { callback() }
}
