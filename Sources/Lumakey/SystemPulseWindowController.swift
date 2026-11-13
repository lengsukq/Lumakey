import AppKit
import LumakeyCore
import SwiftUI

@MainActor
final class SystemPulseWindowController: NSObject, NSWindowDelegate {
    static let shared = SystemPulseWindowController()

    let state = SystemPulseState()
    private var panel: KeyableFloatingPanel?
    private var glassView: RoundedGlassContainerView?
    private var sampler: SystemMonitorSampler?
    private var sampleTask: Task<Void, Never>?
    private var hoverExitTask: Task<Void, Never>?
    private var dragSettleTask: Task<Void, Never>?
    private var isApplyingFrame = false
    private var lastAppliedCornerRadius: CGFloat = 0
    private var lastMenuBarText: String?
    private var onPurgeMemory: (() -> Void)?
    private var onMenuBarUpdate: ((String?) -> Void)?
    private var onOpenNetworkMonitor: (() -> Void)?

    func start(onPurgeMemory: @escaping () -> Void, onMenuBarUpdate: @escaping (String?) -> Void, onOpenNetworkMonitor: @escaping () -> Void) {
        self.onPurgeMemory = onPurgeMemory; self.onMenuBarUpdate = onMenuBarUpdate; self.onOpenNetworkMonitor = onOpenNetworkMonitor
        state.config = SystemMonitorConfig.load()
        state.isTuckedToEdge = (state.config.displayMode == .edgeAutoHide && state.config.dockedEdge != .none)
        syncSamplingLoop()
        if state.config.floatingEnabled { showPanel(animate: false) }
    }

    func toggleFloatingWidget() {
        state.config.floatingEnabled.toggle(); state.config.save()
        if state.config.floatingEnabled {
            state.isPinnedExpanded = false; state.isHovered = false
            syncSamplingLoop(); showPanel(animate: true)
        } else {
            hidePanel(); syncSamplingLoop()
        }
    }

    func toggleMenuBarReadout() { setMenuBarEnabled(!state.config.showInMenuBar) }

    func setMenuBarEnabled(_ enabled: Bool) {
        state.config.showInMenuBar = enabled; state.config.save()
        publishMenuBarText(enabled ? state.config.formatMenuBarText(from: state.snapshot) : nil)
        syncSamplingLoop()
    }

    func setFloatingEnabled(_ enabled: Bool) {
        if state.config.floatingEnabled != enabled { toggleFloatingWidget() }
    }

    func updateMenuMetrics(_ mutate: (inout SystemMonitorConfig) -> Void) {
        mutate(&state.config); state.config.save()
        if state.config.showInMenuBar { publishMenuBarText(state.config.formatMenuBarText(from: state.snapshot)) }
    }

    func refreshOnceForSettings() {
        let localSampler = sampler ?? SystemMonitorSampler()
        Task {
            let snap = await Task.detached(priority: .utility) { localSampler.sample() }.value
            if self.state.snapshot != snap { self.state.snapshot = snap }
            if self.state.config.showInMenuBar { self.publishMenuBarText(self.state.config.formatMenuBarText(from: snap)) }
        }
    }

    func setDisplayMode(_ mode: TelemetryDisplayMode) { state.applyDisplayMode(mode); presentWithSavedConfig() }
    func dockToEdge(_ edge: PulseDockEdge) { state.applyDockEdge(edge); presentWithSavedConfig() }

    func snapToSideEdge() {
        let vis = targetScreenVisibleFrame(), midX = panel?.frame.midX ?? vis.maxX
        dockToEdge(abs(midX - vis.minX) < abs(vis.maxX - midX) ? .left : .right)
    }

    func snapToNearestEdge() {
        let vis = targetScreenVisibleFrame()
        let ref = panel?.frame ?? NSRect(x: vis.maxX - 60, y: vis.midY, width: 58, height: 182)
        dockToEdge(PulseDockEdge.nearestEdge(for: ref, visibleFrame: vis))
    }

    private func presentWithSavedConfig() {
        if !state.config.floatingEnabled {
            state.config.floatingEnabled = true; state.config.save()
            syncSamplingLoop(); showPanel(animate: true)
        } else {
            state.config.save(); reconcilePresentationState(animate: true)
        }
    }

    func setHovered(_ hovered: Bool) {
        hoverExitTask?.cancel(); hoverExitTask = nil
        if hovered {
            guard !state.isHovered else { return }
            state.isHovered = true; reconcilePresentationState(animate: true); return
        }
        guard state.isHovered else { return }
        hoverExitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled, let self else { return }
            if let p = self.panel, p.isVisible, p.frame.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation) { return }
            if self.state.isHovered { self.state.isHovered = false; self.reconcilePresentationState(animate: true) }
        }
    }

    func togglePinExpanded() { state.isPinnedExpanded.toggle(); reconcilePresentationState(animate: true) }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingFrame, (notification.object as? NSWindow) === panel else { return }
        dragSettleTask?.cancel()
        dragSettleTask = Task { [weak self] in
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                if NSEvent.pressedMouseButtons == 0 { self?.handleDragFinished(); return }
            }
        }
    }

    func handleDragFinished() {
        dragSettleTask?.cancel(); dragSettleTask = nil
        guard let panel else { return }
        state.applyDragOutcome(
            frame: panel.frame, visibleFrame: targetScreenVisibleFrame(),
            mouseInside: panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
        )
        reconcilePresentationState(animate: true)
    }

    func shutdown() {
        sampleTask?.cancel(); sampleTask = nil; hoverExitTask?.cancel(); hoverExitTask = nil
        dragSettleTask?.cancel(); dragSettleTask = nil; sampler = nil; hidePanel()
    }

    private func publishMenuBarText(_ text: String?) {
        guard text != lastMenuBarText else { return }
        lastMenuBarText = text; onMenuBarUpdate?(text)
    }

    private func syncSamplingLoop() {
        guard state.config.floatingEnabled || state.config.showInMenuBar else {
            sampleTask?.cancel(); sampleTask = nil; sampler = nil; publishMenuBarText(nil); return
        }
        if sampler == nil { sampler = SystemMonitorSampler() }
        guard sampleTask == nil else { return }
        sampleTask = Task { [weak self] in
            while !Task.isCancelled, let self, let sampler = self.sampler {
                let snap = await Task.detached(priority: .utility) { sampler.sample() }.value
                guard !Task.isCancelled else { break }
                if self.state.snapshot != snap { self.state.snapshot = snap }
                self.publishMenuBarText(self.state.config.showInMenuBar ? self.state.config.formatMenuBarText(from: snap) : nil)
                try? await Task.sleep(for: .milliseconds(1400))
            }
        }
    }

    private func showPanel(animate: Bool) {
        let p = ensurePanel()
        reconcilePresentationState(animate: animate)
        p.orderFrontRegardless()
    }

    private func hidePanel() {
        dragSettleTask?.cancel(); dragSettleTask = nil
        panel?.orderOut(nil); panel?.contentView = nil; panel?.delegate = nil
        panel = nil; glassView = nil; lastAppliedCornerRadius = 0
        MemoryStats.reclaimFreeHeapPages()
    }

    private func ensurePanel() -> KeyableFloatingPanel {
        if let panel { return panel }
        let created = KeyableFloatingPanel(
            contentRect: NSRect(origin: .zero, size: state.targetPanelSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        created.level = .statusBar
        created.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        created.isOpaque = false; created.backgroundColor = .clear; created.hasShadow = true
        created.isMovableByWindowBackground = true; created.hidesOnDeactivate = false; created.delegate = self

        let radius = state.shellCornerRadius
        let glass = RoundedGlassContainerView(cornerRadius: radius)
        lastAppliedCornerRadius = radius; self.glassView = glass
        let root = SystemPulseOverlayView(
            state: state,
            onPurgeMemory: { [weak self] in self?.onPurgeMemory?() },
            onTogglePin: { [weak self] in self?.togglePinExpanded() },
            onDockEdge: { [weak self] e in self?.dockToEdge(e) },
            onSnapSide: { [weak self] in self?.snapToSideEdge() },
            onSnapNearest: { [weak self] in self?.snapToNearestEdge() },
            onToggleMenuBar: { [weak self] in self?.toggleMenuBarReadout() },
            onOpenNetwork: { [weak self] in self?.onOpenNetworkMonitor?() },
            onHideWidget: { [weak self] in self?.toggleFloatingWidget() },
            onSelectMode: { [weak self] m in self?.setDisplayMode(m) },
            onHoverChanged: { [weak self] h in self?.setHovered(h) },
            onDragEnded: { [weak self] in self?.handleDragFinished() }
        )
        let hosting = UnconstrainedPulseHostingView(rootView: root)
        hosting.sizingOptions = []; hosting.wantsLayer = true; hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.frame = glass.bounds; hosting.autoresizingMask = [.width, .height]
        glass.addSubview(hosting); created.contentView = glass; self.panel = created
        return created
    }

    private func reconcilePresentationState(animate: Bool) {
        state.syncPresentationFlags(panelFrame: panel?.frame, visibleFrame: targetScreenVisibleFrame())
        relayoutPanel(animate: animate)
    }

    private func relayoutPanel(animate: Bool) {
        guard let panel else { return }
        let size = state.targetPanelSize
        let origin = state.config.dockedEdge.panelOrigin(
            size: size, currentFrame: panel.frame, visibleFrame: targetScreenVisibleFrame(),
            savedX: state.config.savedOriginX, savedY: state.config.savedOriginY
        )
        let targetFrame = NSRect(origin: origin, size: size)
        let radius = state.shellCornerRadius
        if abs(radius - lastAppliedCornerRadius) > 0.1 {
            lastAppliedCornerRadius = radius; glassView?.updateCornerRadius(radius)
        }
        guard !NSEqualRects(panel.frame, targetFrame) else { return }
        isApplyingFrame = true; defer { isApplyingFrame = false }
        panel.setFrame(targetFrame, display: true, animate: animate)
        panel.invalidateShadow()
    }

    private func targetScreenVisibleFrame() -> NSRect {
        (panel?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
