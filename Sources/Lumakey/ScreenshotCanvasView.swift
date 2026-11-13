import LumakeyCore
import SwiftUI

struct ScreenshotCanvasView: View {
    @ObservedObject var session: ScreenshotSessionState
    let onAction: (ScreenshotToolbarAction) -> Void

    private var imageScale: CGFloat {
        guard session.screenBounds.width > 0 else { return 1 }
        return CGFloat(session.baseImage.width) / session.screenBounds.width
    }

    private var toolbarPosition: CGPoint {
        guard let sel = session.selectionRect?.standardized else { return .zero }
        let toolbarW: CGFloat = 650
        let toolbarH: CGFloat = session.activeTool == .move ? 48 : 82
        let x = min(max(sel.maxX - toolbarW / 2, toolbarW / 2 + 16), session.screenBounds.width - toolbarW / 2 - 16)
        let belowY = sel.maxY + toolbarH / 2 + 10
        let aboveY = sel.minY - toolbarH / 2 - 10
        let y: CGFloat
        if belowY + toolbarH / 2 <= session.screenBounds.height - 10 {
            y = belowY
        } else if aboveY - toolbarH / 2 >= 10 {
            y = aboveY
        } else {
            y = min(sel.maxY - toolbarH / 2 - 12, session.screenBounds.height - toolbarH / 2 - 12)
        }
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: session.baseImage, scale: imageScale, orientation: .up)
                .resizable()
                .frame(width: session.screenBounds.width, height: session.screenBounds.height)

            dimmingOverlay

            if let sel = session.selectionRect?.standardized {
                mosaicOverlay(clippedTo: sel)
                annotationCanvas
                    .frame(width: session.screenBounds.width, height: session.screenBounds.height)
                    .mask(Rectangle().frame(width: sel.width, height: sel.height).position(x: sel.midX, y: sel.midY))

                ScreenshotSelectionChrome(rect: sel, mode: session.mode)
            } else if let hover = session.hoveredWindowRect {
                ScreenshotWindowSnapOverlay(rect: hover)
            }

            // Gesture catcher sits strictly below interactive UI (toolbar & inline text field)
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let pt) = phase {
                        session.updateHover(at: pt)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { handleDragChanged($0) }
                        .onEnded { handleDragEnded($0) }
                )

            if session.selectionRect == nil {
                ScreenshotModeGuidePill(mode: session.mode)
                    .position(x: session.screenBounds.midX, y: 34)
            }

            if let pt = session.pendingTextPoint {
                ScreenshotInlineTextEditor(session: session, point: pt)
            }

            if (session.selectionRect == nil || session.isDraggingSelection) && session.pendingTextPoint == nil {
                ScreenshotLoupeView(session: session, imageScale: imageScale)
            }

            if let sel = session.selectionRect?.standardized, sel.width >= 4, !session.isDraggingSelection {
                ScreenshotToolbarView(session: session, onAction: onAction)
                    .position(toolbarPosition)
            }

            if let banner = session.bannerMessage {
                Text(banner)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.75), in: Capsule())
                    .position(x: session.screenBounds.midX, y: 68)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: session.screenBounds.width, height: session.screenBounds.height)
        .clipped()
        .onChange(of: session.annotations.count) { _, _ in
            if session.mode == .interactiveAnnotate { onAction(.syncClipboard) }
        }
    }

    private var dimmingOverlay: some View {
        Path { path in
            path.addRect(session.screenBounds)
            if let hole = (session.selectionRect ?? session.hoveredWindowRect)?.standardized {
                path.addRect(hole)
            }
        }
        .fill(Color.black.opacity(0.42), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func mosaicOverlay(clippedTo sel: CGRect) -> some View {
        if let pix = session.pixelatedImage {
            Image(decorative: pix, scale: CGFloat(pix.width) / max(session.screenBounds.width, 1), orientation: .up)
                .interpolation(.none)
                .resizable()
                .frame(width: session.screenBounds.width, height: session.screenBounds.height)
                .mask(
                    Canvas { ctx, _ in
                        let items = session.annotations + (session.draftAnnotation.map { [$0] } ?? [])
                        for item in items where item.tool == .mosaic {
                            ScreenshotAnnotationRenderer.renderMosaicMask(item, in: &ctx)
                        }
                    }
                    .frame(width: session.screenBounds.width, height: session.screenBounds.height)
                    .mask(Rectangle().frame(width: sel.width, height: sel.height).position(x: sel.midX, y: sel.midY))
                )
                .allowsHitTesting(false)
        }
    }

    private var annotationCanvas: some View {
        Canvas { ctx, _ in
            let items = session.annotations + (session.draftAnnotation.map { [$0] } ?? [])
            for item in items {
                ScreenshotAnnotationRenderer.render(item, in: &ctx)
            }
        }
        .allowsHitTesting(false)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        session.cursorPoint = value.location
        session.cursorHex = ScreenshotCompositor.samplePixelColor(in: session.baseImage, point: value.location, screenBounds: session.screenBounds)
        if session.activeDragMode == nil {
            session.activeDragMode = resolveDragMode(start: value.startLocation)
        }
        guard let mode = session.activeDragMode else { return }
        let dist = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
        switch mode {
        case .noop:
            break
        case .creating(let origin):
            if dist >= 2 { session.isDraggingSelection = true }
            session.selectionRect = CGRect(
                x: min(origin.x, value.location.x), y: min(origin.y, value.location.y),
                width: abs(value.location.x - origin.x), height: abs(value.location.y - origin.y)
            ).intersection(session.screenBounds)
        case .resizing(let handle, let initial):
            if dist >= 2 { session.isDraggingSelection = true }
            session.selectionRect = resizedRect(initial, handle: handle, to: value.location).intersection(session.screenBounds)
        case .movingSelection(let initial, let start, let savedAnnotations):
            if dist >= 2 { session.isDraggingSelection = true }
            session.moveSelection(from: initial, initialAnnotations: savedAnnotations, dx: value.location.x - start.x, dy: value.location.y - start.y)
        case .annotating(let tool):
            if tool == .pen || tool == .highlighter || tool == .mosaic {
                var pts = session.draftAnnotation?.points ?? [value.startLocation]
                pts.append(value.location)
                session.draftAnnotation = ScreenshotAnnotation(tool: tool, color: session.selectedColor, strokeSize: session.strokeSize, points: pts)
            } else if tool == .rect || tool == .ellipse || tool == .arrow {
                session.draftAnnotation = ScreenshotAnnotation(tool: tool, color: session.selectedColor, strokeSize: session.strokeSize, points: [value.startLocation, value.location])
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let mode = session.activeDragMode
        session.activeDragMode = nil
        session.isDraggingSelection = false
        let dist = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
        if dist < 3 {
            session.draftAnnotation = nil
            handleSingleOrDoubleClick(at: value.location)
            return
        }
        if case .creating = mode {
            if let sel = session.selectionRect, sel.width < 6 || sel.height < 6 {
                session.selectionRect = session.hoveredWindowRect
            }
            if session.mode == .quickOCR, let sel = session.selectionRect?.standardized, sel.width >= 8, sel.height >= 8 {
                onAction(.ocr)
                return
            }
            if session.mode == .interactiveAnnotate { onAction(.syncClipboard) }
        } else if case .resizing = mode {
            if session.mode == .interactiveAnnotate { onAction(.syncClipboard) }
        } else if case .movingSelection = mode {
            if session.mode == .interactiveAnnotate { onAction(.syncClipboard) }
        }
        if let draft = session.draftAnnotation {
            session.annotations.append(draft)
            session.draftAnnotation = nil
        }
    }

    private func handleSingleOrDoubleClick(at point: CGPoint) {
        if session.selectionRect == nil, let hover = session.hoveredWindowRect {
            session.selectionRect = hover
            onAction(session.mode == .quickOCR ? .ocr : .syncClipboard)
            return
        }
        guard let sel = session.selectionRect, sel.contains(point) else { return }
        if session.activeTool == .counter {
            let idx = session.nextCounterIndex
            session.nextCounterIndex += 1
            session.annotations.append(ScreenshotAnnotation(
                tool: .counter, color: session.selectedColor, strokeSize: session.strokeSize, points: [point], counterIndex: idx
            ))
            return
        }
        if session.activeTool == .text {
            session.commitTextAnnotation()
            session.pendingTextPoint = point
            return
        }
        let now = Date().timeIntervalSinceReferenceDate
        if session.activeTool == .move && now - session.lastTapTimestamp < 0.32 && hypot(point.x - session.lastTapPoint.x, point.y - session.lastTapPoint.y) < 12 {
            onAction(session.mode == .quickOCR ? .ocr : .copy)
        }
        session.lastTapTimestamp = now
        session.lastTapPoint = point
    }

    private func resolveDragMode(start: CGPoint) -> ScreenshotDragMode {
        guard let sel = session.selectionRect?.standardized else { return .creating(start) }
        for handle in SelectionHandle.allCases {
            let p = handle.point(in: sel)
            if hypot(start.x - p.x, start.y - p.y) <= 12 { return .resizing(handle, sel) }
        }
        if sel.contains(start) {
            return session.activeTool == .move ? .movingSelection(sel, start, session.annotations) : .annotating(session.activeTool)
        }
        return session.annotations.isEmpty ? .creating(start) : .noop
    }

    private func resizedRect(_ initial: CGRect, handle: SelectionHandle, to pt: CGPoint) -> CGRect {
        var minX = initial.minX, maxX = initial.maxX, minY = initial.minY, maxY = initial.maxY
        switch handle {
        case .topLeft: minX = min(pt.x, maxX - 10); minY = min(pt.y, maxY - 10)
        case .top: minY = min(pt.y, maxY - 10)
        case .topRight: maxX = max(pt.x, minX + 10); minY = min(pt.y, maxY - 10)
        case .right: maxX = max(pt.x, minX + 10)
        case .bottomRight: maxX = max(pt.x, minX + 10); maxY = max(pt.y, minY + 10)
        case .bottom: maxY = max(pt.y, minY + 10)
        case .bottomLeft: minX = min(pt.x, maxX - 10); maxY = max(pt.y, minY + 10)
        case .left: minX = min(pt.x, maxX - 10)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
