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
    private var onPurgeMemory: (() -> Void)?
    private var onMenuBarUpdate: ((String?) -> Void)?
    private var onOpenNetworkMonitor: (() -> Void)?

    private let compactSize = NSSize(width: 416, height: 38)
    private let expandedSize = NSSize(width: 354, height: 318)
    private let sideEdgeSize = NSSize(width: 58, height: 182)
    private let topEdgeSize = NSSize(width: 356, height: 34)

    func start(onPurgeMemory: @escaping () -> Void, onMenuBarUpdate: @escaping (String?) -> Void, onOpenNetworkMonitor: @escaping () -> Void) {
        self.onPurgeMemory = onPurgeMemory
        self.onMenuBarUpdate = onMenuBarUpdate
        self.onOpenNetworkMonitor = onOpenNetworkMonitor
        state.config = SystemMonitorConfig.load()
        state.isTuckedToEdge = (state.config.displayMode == .edgeAutoHide && state.config.dockedEdge != .none)
        syncSamplingLoop()
        if state.config.floatingEnabled { showPanel(animate: false) }
    }

    func toggleFloatingWidget() {
        state.config.floatingEnabled.toggle()
        state.config.save()
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
        onMenuBarUpdate?(enabled ? state.config.formatMenuBarText(from: state.snapshot) : nil)
        syncSamplingLoop()
    }

    func setFloatingEnabled(_ enabled: Bool) {
        if state.config.floatingEnabled != enabled { toggleFloatingWidget() }
    }

    func updateMenuMetrics(_ mutate: (inout SystemMonitorConfig) -> Void) {
        mutate(&state.config); state.config.save()
        if state.config.showInMenuBar { onMenuBarUpdate?(state.config.formatMenuBarText(from: state.snapshot)) }
    }

    func refreshOnceForSettings() {
        let localSampler = sampler ?? SystemMonitorSampler()
        Task {
            let snap = await Task.detached(priority: .utility) { localSampler.sample() }.value
            self.state.snapshot = snap
            if self.state.config.showInMenuBar { self.onMenuBarUpdate?(self.state.config.formatMenuBarText(from: snap)) }
        }
    }

    func setDisplayMode(_ mode: TelemetryDisplayMode) {
        state.config.displayMode = mode
        if mode == .edgeAutoHide {
            if state.config.dockedEdge == .none { state.config.dockedEdge = .right }
            state.isPinnedExpanded = false
        } else {
            state.config.dockedEdge = .none
            state.isPinnedExpanded = (mode == .alwaysExpanded)
        }
        presentWithSavedConfig()
    }

    func dockToEdge(_ edge: PulseDockEdge) {
        state.config.dockedEdge = (edge == .none) ? .right : edge
        state.config.displayMode = .edgeAutoHide
        state.isPinnedExpanded = false; state.isHovered = false
        presentWithSavedConfig()
    }

    func snapToSideEdge() {
        let vis = targetScreenVisibleFrame()
        let midX = panel?.frame.midX ?? vis.maxX
        dockToEdge(abs(midX - vis.minX) < abs(vis.maxX - midX) ? .left : .right)
    }

    func snapToNearestEdge() {
        let vis = targetScreenVisibleFrame()
        let refFrame = panel?.frame ?? NSRect(x: vis.maxX - 60, y: vis.midY, width: 58, height: 182)
        dockToEdge(PulseDockEdge.nearestEdge(for: refFrame, visibleFrame: vis))
    }

    private func presentWithSavedConfig() {
        state.config.save()
        if !state.config.floatingEnabled {
            state.config.floatingEnabled = true; state.config.save()
            syncSamplingLoop(); showPanel(animate: true)
        } else {
            reconcilePresentationState(animate: true)
        }
    }

    func setHovered(_ hovered: Bool) {
        hoverExitTask?.cancel(); hoverExitTask = nil
        if hovered { state.isHovered = true; reconcilePresentationState(animate: true); return }
        hoverExitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled, let self else { return }
            if let p = self.panel, p.isVisible, p.frame.insetBy(dx: -3, dy: -3).contains(NSEvent.mouseLocation) {
                self.state.isHovered = true; return
            }
            self.state.isHovered = false; self.reconcilePresentationState(animate: true)
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
        let frame = panel.frame, visible = targetScreenVisibleFrame()
        let snapped = PulseDockEdge.detectSnapEdge(frame: frame, visibleFrame: visible)
        if snapped != .none {
            state.config.dockedEdge = snapped; state.config.displayMode = .edgeAutoHide
            if snapped == .top { state.config.savedOriginX = Double(frame.midX) } else { state.config.savedOriginY = Double(frame.maxY) }
        } else {
            state.config.dockedEdge = .none
            if state.config.displayMode == .edgeAutoHide { state.config.displayMode = .compactHoverExpand }
            state.config.savedOriginX = Double(frame.origin.x); state.config.savedOriginY = Double(frame.maxY)
        }
        state.config.save()
        state.isHovered = panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
        reconcilePresentationState(animate: true)
    }

    func shutdown() {
        sampleTask?.cancel(); sampleTask = nil
        hoverExitTask?.cancel(); hoverExitTask = nil
        dragSettleTask?.cancel(); dragSettleTask = nil
        sampler = nil; hidePanel()
    }

    private func syncSamplingLoop() {
        let needed = state.config.floatingEnabled || state.config.showInMenuBar
        if !needed {
            sampleTask?.cancel(); sampleTask = nil
            sampler = nil; onMenuBarUpdate?(nil)
            return
        }
        if sampler == nil { sampler = SystemMonitorSampler() }
        if sampleTask != nil { return }
        sampleTask = Task { [weak self] in
            while !Task.isCancelled, let self, let sampler = self.sampler {
                let snap = await Task.detached(priority: .utility) { sampler.sample() }.value
                guard !Task.isCancelled else { break }
                self.state.snapshot = snap
                self.onMenuBarUpdate?(self.state.config.showInMenuBar ? self.state.config.formatMenuBarText(from: snap) : nil)
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
        panel = nil; glassView = nil
        MemoryStats.reclaimFreeHeapPages()
    }

    private func ensurePanel() -> KeyableFloatingPanel {
        if let panel { return panel }
        let created = KeyableFloatingPanel(
            contentRect: NSRect(origin: .zero, size: targetSize()),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        created.level = .statusBar
        created.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        created.isOpaque = false; created.backgroundColor = .clear; created.hasShadow = true
        created.isMovableByWindowBackground = true; created.hidesOnDeactivate = false; created.delegate = self

        let glass = RoundedGlassContainerView(cornerRadius: currentCornerRadius())
        self.glassView = glass
        let root = SystemPulseOverlayView(
            state: state,
            onPurgeMemory: { [weak self] in self?.onPurgeMemory?() },
            onTogglePin: { [weak self] in self?.togglePinExpanded() },
            onDockEdge: { [weak self] edge in self?.dockToEdge(edge) },
            onSnapSide: { [weak self] in self?.snapToSideEdge() },
            onSnapNearest: { [weak self] in self?.snapToNearestEdge() },
            onToggleMenuBar: { [weak self] in self?.toggleMenuBarReadout() },
            onOpenNetwork: { [weak self] in self?.onOpenNetworkMonitor?() },
            onHideWidget: { [weak self] in self?.toggleFloatingWidget() },
            onSelectMode: { [weak self] mode in self?.setDisplayMode(mode) },
            onHoverChanged: { [weak self] h in self?.setHovered(h) },
            onDragEnded: { [weak self] in self?.handleDragFinished() }
        )
        let hosting = UnconstrainedPulseHostingView(rootView: root)
        hosting.sizingOptions = []; hosting.wantsLayer = true; hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = glass.bounds
        hosting.autoresizingMask = [.width, .height]
        glass.addSubview(hosting)
        created.contentView = glass
        self.panel = created
        return created
    }

    private func reconcilePresentationState(animate: Bool) {
        if state.config.displayMode == .edgeAutoHide {
            if state.config.dockedEdge == .none {
                let vis = (panel?.screen ?? NSScreen.main)?.visibleFrame ?? targetScreenVisibleFrame()
                let ref = panel?.frame ?? NSRect(x: vis.maxX - 60, y: vis.midY, width: 58, height: 182)
                state.config.dockedEdge = PulseDockEdge.nearestEdge(for: ref, visibleFrame: vis)
            }
            state.isTuckedToEdge = !(state.isHovered || state.isPinnedExpanded)
        } else {
            state.isTuckedToEdge = false
            if state.config.displayMode == .alwaysExpanded { state.isPinnedExpanded = true }
        }
        relayoutPanel(animate: animate)
    }

    private func currentCornerRadius() -> CGFloat {
        if state.isTuckedToEdge { return state.config.dockedEdge == .top ? 17 : 18 }
        return state.showsFullDashboard ? 22 : 19
    }

    private func targetSize() -> NSSize {
        if state.isTuckedToEdge {
            return state.config.dockedEdge == .top ? topEdgeSize : sideEdgeSize
        }
        return state.showsFullDashboard ? expandedSize : compactSize
    }

    private func relayoutPanel(animate: Bool) {
        guard let panel else { return }
        isApplyingFrame = true
        defer { isApplyingFrame = false }
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? targetScreenVisibleFrame()
        let size = targetSize()
        let origin = state.config.dockedEdge.panelOrigin(
            size: size,
            currentFrame: panel.frame,
            visibleFrame: visible,
            savedX: state.config.savedOriginX,
            savedY: state.config.savedOriginY
        )
        glassView?.updateCornerRadius(currentCornerRadius())
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: animate)
        panel.invalidateShadow()
    }

    private func targetScreenVisibleFrame() -> NSRect {
        (panel?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
