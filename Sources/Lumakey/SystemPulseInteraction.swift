import AppKit
import LumakeyCore
import SwiftUI

@MainActor
final class SystemPulseState: ObservableObject {
    @Published var snapshot: SystemTelemetrySnapshot = .placeholder
    @Published var config: SystemMonitorConfig = SystemMonitorConfig.load()
    @Published var isHovered: Bool = false
    @Published var isPinnedExpanded: Bool = false
    @Published var isTuckedToEdge: Bool = false

    var showsFullDashboard: Bool {
        if isTuckedToEdge { return false }
        switch config.displayMode {
        case .alwaysExpanded: return true
        case .compactHoverExpand: return isHovered || isPinnedExpanded
        case .edgeAutoHide: return isHovered || isPinnedExpanded
        }
    }
}

struct SparklineView: View {
    let values: [Double]
    let accent: Color

    var body: some View {
        Canvas { ctx, size in
            let pts = values.isEmpty ? [0.1, 0.1] : (values.count == 1 ? [values[0], values[0]] : values)
            let w = size.width, h = size.height
            var line = Path()
            var fill = Path()
            for (idx, val) in pts.enumerated() {
                let x = w * CGFloat(idx) / CGFloat(max(1, pts.count - 1))
                let y = h - CGFloat(min(1, max(0.05, val))) * (h - 4) - 2
                if idx == 0 {
                    line.move(to: CGPoint(x: x, y: y))
                    fill.move(to: CGPoint(x: x, y: h))
                    fill.addLine(to: CGPoint(x: x, y: y))
                } else {
                    line.addLine(to: CGPoint(x: x, y: y))
                    fill.addLine(to: CGPoint(x: x, y: y))
                }
            }
            fill.addLine(to: CGPoint(x: w, y: h))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(accent.opacity(0.22)))
            ctx.stroke(line, with: .color(accent), lineWidth: 1.6)
        }
    }
}

final class UnconstrainedPulseHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

struct PulseInteractionLayer: NSViewRepresentable {
    let onTap: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onDragEnded: () -> Void
    let onSelectMode: (TelemetryDisplayMode) -> Void
    let onDockEdge: (PulseDockEdge) -> Void
    let onSnapNearest: () -> Void
    let onToggleMenuBar: () -> Void
    let onHide: () -> Void

    func makeNSView(context: Context) -> PulseInteractionNSView {
        let view = PulseInteractionNSView()
        sync(view)
        return view
    }

    func updateNSView(_ nsView: PulseInteractionNSView, context: Context) { sync(nsView) }

    private func sync(_ v: PulseInteractionNSView) {
        v.onTap = onTap; v.onHoverChanged = onHoverChanged; v.onDragEnded = onDragEnded
        v.onSelectMode = onSelectMode; v.onDockEdge = onDockEdge; v.onSnapNearest = onSnapNearest
        v.onToggleMenuBar = onToggleMenuBar; v.onHide = onHide
    }
}

final class PulseInteractionNSView: NSView {
    var onTap: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onDragEnded: (() -> Void)?
    var onSelectMode: ((TelemetryDisplayMode) -> Void)?
    var onDockEdge: ((PulseDockEdge) -> Void)?
    var onSnapNearest: (() -> Void)?
    var onToggleMenuBar: (() -> Void)?
    var onHide: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let startOrigin = window?.frame.origin ?? .zero
        window?.performDrag(with: event)
        let endOrigin = window?.frame.origin ?? .zero
        let dist = hypot(endOrigin.x - startOrigin.x, endOrigin.y - startOrigin.y)
        if dist < 3 { onTap?() } else { onDragEnded?() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for mode in TelemetryDisplayMode.allCases {
            menu.addItem(PulseMenuItem(title: mode.title) { [weak self] in self?.onSelectMode?(mode) })
        }
        menu.addItem(.separator())
        menu.addItem(PulseMenuItem(title: "贴靠顶部 · 横向排列") { [weak self] in self?.onDockEdge?(.top) })
        menu.addItem(PulseMenuItem(title: "贴靠左侧 · 竖行排列") { [weak self] in self?.onDockEdge?(.left) })
        menu.addItem(PulseMenuItem(title: "贴靠右侧 · 竖行排列") { [weak self] in self?.onDockEdge?(.right) })
        menu.addItem(PulseMenuItem(title: "自动贴靠最近边缘") { [weak self] in self?.onSnapNearest?() })
        menu.addItem(.separator())
        menu.addItem(PulseMenuItem(title: "切换顶部菜单栏实时显示") { [weak self] in self?.onToggleMenuBar?() })
        menu.addItem(PulseMenuItem(title: "隐藏悬浮监控窗 (⌥M)") { [weak self] in self?.onHide?() })
        return menu
    }
}

@MainActor
private final class PulseMenuItem: NSMenuItem {
    private let callback: () -> Void
    init(title: String, callback: @escaping () -> Void) {
        self.callback = callback
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        self.target = self
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func run() { callback() }
}