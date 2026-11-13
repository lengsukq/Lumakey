import AppKit
import LumakeyCore
import SwiftUI

final class KeyableFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class RoundedGlassContainerView: NSVisualEffectView {
    private var currentCornerRadius: CGFloat
    private let outerRimLayer = CAGradientLayer()
    private let outerRimMask = CALayer()
    private let innerRimLayer = CAGradientLayer()
    private let innerRimMask = CALayer()

    init(cornerRadius: CGFloat = LiquidRadii.panel) {
        self.currentCornerRadius = cornerRadius
        super.init(frame: .zero)
        material = .popover; blendingMode = .behindWindow; state = .active
        isEmphasized = true; wantsLayer = true
        configureSpecularRimLayers()
        updateCornerRadius(cornerRadius, force: true)
        updateRimAppearance()
    }

    required init?(coder: NSCoder) { nil }
    override var mouseDownCanMoveWindow: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layoutRimLayers()
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateRimAppearance()
    }

    func updateCornerRadius(_ radius: CGFloat, force: Bool = false) {
        guard force || abs(radius - currentCornerRadius) > 0.4 else { return }
        currentCornerRadius = radius
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        maskImage = Self.makeRoundedMaskImage(cornerRadius: radius)
        layoutRimLayers()
    }

    private func configureSpecularRimLayers() {
        for (gradient, mask) in [(outerRimLayer, outerRimMask), (innerRimLayer, innerRimMask)] {
            gradient.isGeometryFlipped = true
            gradient.startPoint = CGPoint(x: 0.0, y: 0.0)
            gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
            gradient.zPosition = 999
            mask.backgroundColor = nil; mask.cornerCurve = .continuous; mask.borderColor = NSColor.black.cgColor
            gradient.mask = mask
            layer?.addSublayer(gradient)
        }
        outerRimMask.borderWidth = 1.1
        innerRimMask.borderWidth = 0.75
    }

    private func layoutRimLayers() {
        outerRimLayer.frame = bounds; outerRimMask.frame = bounds; outerRimMask.cornerRadius = currentCornerRadius
        let insetBounds = bounds.insetBy(dx: 1.2, dy: 1.2)
        innerRimLayer.frame = insetBounds
        innerRimMask.frame = CGRect(origin: .zero, size: insetBounds.size)
        innerRimMask.cornerRadius = max(0, currentCornerRadius - 1.2)
    }

    private func updateRimAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            let edge = (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.28).cgColor
            outerRimLayer.colors = [edge, edge]; outerRimLayer.locations = [0.0, 1.0]
            innerRimLayer.isHidden = true
            return
        }
        innerRimLayer.isHidden = false
        outerRimLayer.colors = [
            NSColor.white.withAlphaComponent(isDark ? 0.46 : 0.78).cgColor,
            NSColor.white.withAlphaComponent(isDark ? 0.08 : 0.16).cgColor,
            NSColor.white.withAlphaComponent(isDark ? 0.24 : 0.36).cgColor
        ]
        outerRimLayer.locations = [0.0, 0.48, 1.0]
        innerRimLayer.colors = [
            NSColor.white.withAlphaComponent(isDark ? 0.22 : 0.38).cgColor,
            NSColor.systemCyan.withAlphaComponent(isDark ? 0.14 : 0.10).cgColor,
            NSColor.clear.cgColor
        ]
        innerRimLayer.locations = [0.0, 0.5, 1.0]
    }

    private static func makeRoundedMaskImage(cornerRadius: CGFloat) -> NSImage {
        let safeRadius = max(2, cornerRadius)
        let inset = ceil(safeRadius * 1.6) + 1
        let edge = inset * 2 + 4
        let renderer = ImageRenderer(content: RoundedRectangle(cornerRadius: safeRadius, style: .continuous).fill(Color.black).frame(width: edge, height: edge))
        renderer.scale = 2.0
        let image: NSImage
        if let rendered = renderer.nsImage {
            rendered.size = NSSize(width: edge, height: edge); image = rendered
        } else {
            image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
                NSColor.black.setFill(); NSBezierPath(roundedRect: rect, xRadius: safeRadius, yRadius: safeRadius).fill(); return true
            }
        }
        image.capInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
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

    init(viewModel: AppViewModel) { self.viewModel = viewModel; super.init() }
    var isVisible: Bool { panel?.isVisible == true }

    func toggle(filter: OmniFilter) {
        if isVisible && viewModel.omniFilter == filter { hide() } else { show(filter: filter) }
    }

    func show(filter: OmniFilter) {
        idleTeardownTask?.cancel(); idleTeardownTask = nil
        viewModel.prepareOverlay(filter: filter)
        let panel = ensurePanel()
        let wasVisible = panel.isVisible
        positionPanel(panel, width: panelWidth, height: panelHeight)
        NSApp.activate(ignoringOtherApps: true)
        if !wasVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 0; panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18; ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1.0
            }
        } else {
            panel.alphaValue = 1.0; panel.makeKeyAndOrderFront(nil)
        }
        panel.invalidateShadow()
        viewModel.bumpFocusToken()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil); panel.alphaValue = 1.0
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
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        created.level = .floating; created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        created.isOpaque = false; created.backgroundColor = .clear; created.hasShadow = true
        created.isMovableByWindowBackground = true; created.hidesOnDeactivate = false; created.delegate = self

        let glassRoot = RoundedGlassContainerView(cornerRadius: LiquidRadii.panel)
        let hosting = NSHostingView(rootView: OverlayCommandView(viewModel: viewModel))
        hosting.sizingOptions = []; hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true; hosting.layer?.backgroundColor = NSColor.clear.cgColor
        glassRoot.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: glassRoot.leadingAnchor), hosting.trailingAnchor.constraint(equalTo: glassRoot.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: glassRoot.topAnchor), hosting.bottomAnchor.constraint(equalTo: glassRoot.bottomAnchor)
        ])
        created.contentView = glassRoot
        self.panel = created
        return created
    }

    private func positionPanel(_ panel: NSPanel, width: CGFloat, height: CGFloat) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let topCenter = (userDraggedTopCenter.flatMap { screen?.frame.contains($0) == true ? $0 : nil })
            ?? NSPoint(x: visible.midX, y: visible.maxY - 72)
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
            panel.contentView = nil; panel.delegate = nil; self.panel = nil
            MemoryStats.reclaimFreeHeapPages()
        }
    }
}
