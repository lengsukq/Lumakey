import AppKit
import LumakeyCore
import SwiftUI

final class KeyableFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class RoundedGlassContainerView: NSVisualEffectView {
    private var currentCornerRadius: CGFloat

    init(cornerRadius: CGFloat = LiquidRadii.panel) {
        self.currentCornerRadius = cornerRadius
        super.init(frame: .zero)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        isEmphasized = true
        wantsLayer = true
        updateCornerRadius(cornerRadius, force: true)
    }

    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { true }

    func updateCornerRadius(_ radius: CGFloat, force: Bool = false) {
        guard force || abs(radius - currentCornerRadius) > 0.4 else { return }
        currentCornerRadius = radius
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        maskImage = Self.makeRoundedMaskImage(cornerRadius: radius)
    }

    private static func makeRoundedMaskImage(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 2
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let panelWidth: CGFloat = 880
    private let panelHeight: CGFloat = 544
    private var panel: KeyableFloatingPanel?
    private unowned let viewModel: AppViewModel
    private var idleTeardownTask: Task<Void, Never>?
    private var userDraggedTopCenter: NSPoint?
    private var isAdjustingFrame = false

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle(filter: OmniFilter) {
        if isVisible && viewModel.omniFilter == filter {
            hide()
        } else {
            show(filter: filter)
        }
    }

    func show(filter: OmniFilter) {
        idleTeardownTask?.cancel()
        idleTeardownTask = nil
        viewModel.prepareOverlay(filter: filter)
        let panel = ensurePanel()
        positionPanel(panel, width: panelWidth, height: panelHeight)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        viewModel.bumpFocusToken()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        viewModel.handleOverlayHidden()
        scheduleIdlePanelTeardown()
    }

    func resetPositionToCenter() {
        userDraggedTopCenter = nil
        guard let panel, panel.isVisible else { return }
        positionPanel(panel, width: panelWidth, height: panelHeight)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !viewModel.isOverlayPinned && !viewModel.isCapturingScreen else { return }
        hide()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame, let panel, panel.isVisible else { return }
        userDraggedTopCenter = NSPoint(x: panel.frame.midX, y: panel.frame.maxY)
    }

    private func ensurePanel() -> KeyableFloatingPanel {
        if let panel { return panel }
        let created = KeyableFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.level = .floating
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        created.isMovableByWindowBackground = true
        created.hidesOnDeactivate = false
        created.delegate = self

        let glassRoot = RoundedGlassContainerView(cornerRadius: LiquidRadii.panel)
        let hosting = NSHostingView(rootView: OverlayCommandView(viewModel: viewModel))
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        glassRoot.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: glassRoot.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: glassRoot.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: glassRoot.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: glassRoot.bottomAnchor)
        ])
        created.contentView = glassRoot
        self.panel = created
        return created
    }

    private func positionPanel(_ panel: NSPanel, width: CGFloat, height: CGFloat) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let topCenter: NSPoint
        if let saved = userDraggedTopCenter, screen?.frame.contains(saved) == true {
            topCenter = saved
        } else {
            topCenter = NSPoint(x: visible.midX, y: visible.maxY - 72)
        }
        let x = min(max(visible.minX + 16, topCenter.x - width / 2.0), visible.maxX - width - 16)
        let y = min(max(visible.minY + 24, topCenter.y - height), visible.maxY - height - 12)
        isAdjustingFrame = true
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: false)
        isAdjustingFrame = false
    }

    private func scheduleIdlePanelTeardown() {
        idleTeardownTask?.cancel()
        idleTeardownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, let panel = self.panel, !panel.isVisible else { return }
            panel.contentView = nil
            panel.delegate = nil
            self.panel = nil
            MemoryStats.reclaimFreeHeapPages()
        }
    }
}
