import AppKit
import CoreGraphics
import LumakeyCore
import SwiftUI

enum GifSelectionDragMode {
    case creating(CGPoint)
    case resizing(SelectionHandle, CGRect)
    case moving(CGRect, CGPoint)
}

@MainActor
final class GifSelectionSession: ObservableObject {
    let baseImage: CGImage
    let screenBounds: CGRect
    let appKitScreenFrame: NSRect
    let displayID: CGDirectDisplayID
    let backingScale: CGFloat
    let windows: [DetectedScreenWindow]

    @Published var selectionRect: CGRect?
    @Published var hoveredWindow: DetectedScreenWindow?
    @Published var isDragging: Bool = false
    @Published var options: GifRecordingOptions

    var activeDrag: GifSelectionDragMode?
    var lastClickTime: TimeInterval = 0
    var lastClickPoint: CGPoint = .zero

    init(
        baseImage: CGImage, screenBounds: CGRect, appKitScreenFrame: NSRect,
        displayID: CGDirectDisplayID, backingScale: CGFloat,
        windows: [DetectedScreenWindow], options: GifRecordingOptions
    ) {
        self.baseImage = baseImage; self.screenBounds = screenBounds
        self.appKitScreenFrame = appKitScreenFrame; self.displayID = displayID
        self.backingScale = max(1.0, backingScale); self.windows = windows
        self.options = options
    }

    func updateHover(at point: CGPoint) {
        guard selectionRect == nil else { hoveredWindow = nil; return }
        hoveredWindow = windows.first(where: { $0.frame.contains(point) })
    }

    func outputDimensions(for rect: CGRect) -> (Int, Int) {
        let rawW = max(2, Int((rect.width * backingScale).rounded()))
        let rawH = max(2, Int((rect.height * backingScale).rounded()))
        return GifStreamEncoder.scaledDimensions(width: rawW, height: rawH, maxDimension: options.maxDimension)
    }

    func appKitScreenRect(for localRect: CGRect) -> NSRect {
        NSRect(x: appKitScreenFrame.minX + localRect.minX, y: appKitScreenFrame.maxY - localRect.maxY, width: localRect.width, height: localRect.height)
    }
}

struct GifSelectionOverlayView: View {
    @ObservedObject var session: GifSelectionSession
    let onStartRecording: () -> Void
    let onCancel: () -> Void

    private var controlBarPosition: CGPoint {
        guard let sel = session.selectionRect?.standardized else { return CGPoint(x: session.screenBounds.midX, y: 44) }
        let barW: CGFloat = 540, barH: CGFloat = 46
        let x = min(max(sel.midX, barW / 2 + 16), session.screenBounds.width - barW / 2 - 16)
        let belowY = sel.maxY + barH / 2 + 12, aboveY = sel.minY - barH / 2 - 12
        if belowY + barH / 2 <= session.screenBounds.height - 12 { return CGPoint(x: x, y: belowY) }
        if aboveY - barH / 2 >= 12 { return CGPoint(x: x, y: aboveY) }
        return CGPoint(x: x, y: min(sel.maxY - barH / 2 - 12, session.screenBounds.height - barH / 2 - 12))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: session.baseImage, scale: session.backingScale, orientation: .up)
                .resizable().frame(width: session.screenBounds.width, height: session.screenBounds.height)

            Path { path in
                path.addRect(session.screenBounds)
                if let hole = (session.selectionRect ?? session.hoveredWindow?.frame)?.standardized { path.addRect(hole) }
            }
            .fill(Color.black.opacity(0.46), style: FillStyle(eoFill: true)).allowsHitTesting(false)

            if let sel = session.selectionRect?.standardized { selectionChrome(for: sel) }
            else if let win = session.hoveredWindow { hoveredWindowChrome(for: win) }

            Color.clear.contentShape(Rectangle())
                .onContinuousHover { if case .active(let pt) = $0 { session.updateHover(at: pt) } }
                .gesture(DragGesture(minimumDistance: 0).onChanged(handleDragChanged).onEnded(handleDragEnded))

            if !session.isDragging { presetAndActionToolbar.position(controlBarPosition) }
        }
        .frame(width: session.screenBounds.width, height: session.screenBounds.height).clipped()
    }

    private func selectionChrome(for rect: CGRect) -> some View {
        let (outW, outH) = session.outputDimensions(for: rect)
        let accent = Color(red: 1.0, green: 0.30, blue: 0.28)
        return ZStack(alignment: .topLeading) {
            Rectangle().strokeBorder(accent, lineWidth: 1.8)
                .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            ForEach(SelectionHandle.allCases, id: \.self) { handle in
                Circle().fill(Color.white).overlay(Circle().strokeBorder(accent, lineWidth: 1.6))
                    .frame(width: 9, height: 9).position(handle.point(in: rect))
            }
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("GIF \(outW)×\(outH) px · \(session.options.fps) FPS")
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 4).background(.black.opacity(0.78), in: Capsule())
            .position(x: max(96, rect.minX + 88), y: rect.minY > 30 ? rect.minY - 15 : rect.minY + 16)
        }
        .allowsHitTesting(false)
    }

    private func hoveredWindowChrome(for win: DetectedScreenWindow) -> some View {
        let rect = win.frame
        let label = win.ownerName.isEmpty ? "单击框选此窗口" : "\(win.ownerName) · 单击选定窗口录制"
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.cyan.opacity(0.95), lineWidth: 2.2)
                .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4).background(.black.opacity(0.76), in: Capsule())
                .position(x: max(120, rect.minX + 108), y: max(20, rect.minY - 15))
        }
        .allowsHitTesting(false)
    }

    private var presetAndActionToolbar: some View {
        let hasSelection = (session.selectionRect?.standardized.width ?? 0) >= 12
        return HStack(spacing: 8) {
            if !hasSelection {
                Text("拖拽框选或单击窗口 · Esc 取消")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.92)).padding(.leading, 4)
            }
            HStack(spacing: 3) {
                ForEach(GifRecordingOptions.fpsPresets, id: \.self) { fps in
                    presetChip("\(fps)FPS", active: session.options.fps == fps) { session.options.fps = fps }
                }
            }
            .padding(3).background(.white.opacity(0.08), in: Capsule())

            HStack(spacing: 3) {
                ForEach(GifRecordingOptions.dimensionPresets, id: \.self) { dim in
                    presetChip(GifRecordingOptions.dimensionLabel(for: dim), active: session.options.maxDimension == dim) {
                        session.options.maxDimension = dim
                    }
                }
            }
            .padding(3).background(.white.opacity(0.08), in: Capsule())

            Button(action: onCancel) {
                Text("取消").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 10).padding(.vertical, 6).background(.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)

            if hasSelection {
                Button(action: onStartRecording) {
                    HStack(spacing: 5) {
                        Circle().fill(.white).frame(width: 7, height: 7)
                        Text("开始录制 ⏎").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white).padding(.horizontal, 13).padding(.vertical, 6)
                    .background(
                        LinearGradient(colors: [Color(red: 1.0, green: 0.27, blue: 0.25), Color(red: 0.90, green: 0.14, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule()).background(Color.black.opacity(0.58), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.9))
        .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
    }

    private func presetChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: active ? .bold : .medium, design: .rounded))
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.85))
                .padding(.horizontal, 8).padding(.vertical, 4).background(active ? Color.white : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        if session.activeDrag == nil { session.activeDrag = resolveDragMode(at: value.startLocation) }
        guard let mode = session.activeDrag else { return }
        if hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y) >= 2 { session.isDragging = true }
        switch mode {
        case .creating(let origin):
            session.selectionRect = CGRect(
                x: min(origin.x, value.location.x), y: min(origin.y, value.location.y),
                width: abs(value.location.x - origin.x), height: abs(value.location.y - origin.y)
            ).intersection(session.screenBounds)
        case .resizing(let handle, let initial):
            session.selectionRect = resized(initial, handle: handle, to: value.location).intersection(session.screenBounds)
        case .moving(let initial, let start):
            let x = min(max(0, initial.minX + value.location.x - start.x), session.screenBounds.width - initial.width)
            let y = min(max(0, initial.minY + value.location.y - start.y), session.screenBounds.height - initial.height)
            session.selectionRect = CGRect(origin: CGPoint(x: x, y: y), size: initial.size)
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        session.activeDrag = nil; session.isDragging = false
        if hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y) < 3 {
            if session.selectionRect == nil, let win = session.hoveredWindow { session.selectionRect = win.frame; return }
            let now = Date().timeIntervalSinceReferenceDate
            if let sel = session.selectionRect, sel.contains(value.location), now - session.lastClickTime < 0.32,
               hypot(value.location.x - session.lastClickPoint.x, value.location.y - session.lastClickPoint.y) < 12 {
                onStartRecording()
            }
            session.lastClickTime = now; session.lastClickPoint = value.location
            return
        }
        if let sel = session.selectionRect, sel.width < 12 || sel.height < 12 { session.selectionRect = session.hoveredWindow?.frame }
    }

    private func resolveDragMode(at pt: CGPoint) -> GifSelectionDragMode {
        guard let sel = session.selectionRect?.standardized else { return .creating(pt) }
        for h in SelectionHandle.allCases where hypot(pt.x - h.point(in: sel).x, pt.y - h.point(in: sel).y) <= 12 { return .resizing(h, sel) }
        return sel.contains(pt) ? .moving(sel, pt) : .creating(pt)
    }

    private func resized(_ r: CGRect, handle: SelectionHandle, to pt: CGPoint) -> CGRect {
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        switch handle {
        case .topLeft: minX = min(pt.x, maxX - 16); minY = min(pt.y, maxY - 16)
        case .top: minY = min(pt.y, maxY - 16)
        case .topRight: maxX = max(pt.x, minX + 16); minY = min(pt.y, maxY - 16)
        case .right: maxX = max(pt.x, minX + 16)
        case .bottomRight: maxX = max(pt.x, minX + 16); maxY = max(pt.y, minY + 16)
        case .bottom: maxY = max(pt.y, minY + 16)
        case .bottomLeft: minX = min(pt.x, maxX - 16); maxY = max(pt.y, minY + 16)
        case .left: minX = min(pt.x, maxX - 16)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
