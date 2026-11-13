import AppKit
import LumakeyCore
import SwiftUI

struct ScreenshotModeGuidePill: View {
    let mode: ScreenshotMode

    var body: some View {
        let text = mode == .quickOCR
            ? "⚡ 离线识字模式：框选文字松手即识字 · 单击窗口识别整窗 · 右键/Esc 取消"
            : "拖拽框选或单击窗口 · C 复制色值 · 右键/Esc 取消"
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.black.opacity(0.72), in: Capsule())
            .allowsHitTesting(false)
    }
}

struct ScreenshotWindowSnapOverlay: View {
    let rect: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(Color.cyan.opacity(0.95), lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            Text("点击框选窗口 · 拖拽自由选区")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.72), in: Capsule())
                .position(x: max(110, rect.minX + 95), y: max(18, rect.minY - 14))
        }
        .allowsHitTesting(false)
    }
}

struct ScreenshotSelectionChrome: View {
    let rect: CGRect
    let mode: ScreenshotMode

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            ForEach(SelectionHandle.allCases, id: \.self) { handle in
                let pt = handle.point(in: rect)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                    .frame(width: 9, height: 9)
                    .position(pt)
            }

            HStack(spacing: 6) {
                Text("\(Int(round(rect.width))) × \(Int(round(rect.height))) px")
                if mode == .quickOCR {
                    Text("OCR")
                        .foregroundStyle(.purple)
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 6))
            .position(x: max(76, rect.minX + 66), y: rect.minY > 28 ? rect.minY - 14 : rect.minY + 14)
        }
        .allowsHitTesting(false)
    }
}

struct ScreenshotLoupeView: View {
    @ObservedObject var session: ScreenshotSessionState
    let imageScale: CGFloat

    var body: some View {
        let pt = session.cursorPoint
        let offsetX: CGFloat = pt.x + 150 > session.screenBounds.width ? -86 : 86
        let offsetY: CGFloat = pt.y + 150 > session.screenBounds.height ? -86 : 86
        let cropSize: CGFloat = 28
        let pixelRect = CGRect(
            x: max(0, (pt.x - cropSize / 2) * imageScale),
            y: max(0, (pt.y - cropSize / 2) * imageScale),
            width: cropSize * imageScale,
            height: cropSize * imageScale
        )
        let zoomedCG = session.baseImage.cropping(to: pixelRect)
        VStack(spacing: 4) {
            ZStack {
                if let zoomedCG {
                    Image(decorative: zoomedCG, scale: 1, orientation: .up)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 96, height: 96)
                }
                Rectangle().fill(Color.accentColor.opacity(0.65)).frame(width: 96, height: 1)
                Rectangle().fill(Color.accentColor.opacity(0.65)).frame(width: 1, height: 96)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.75), lineWidth: 1.5))

            VStack(spacing: 1) {
                Text("\(session.cursorHex) · \(Int(pt.x)),\(Int(pt.y))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text("C 复制色值 · ESC 取消")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 6))
        }
        .position(x: pt.x + offsetX, y: pt.y + offsetY)
        .allowsHitTesting(false)
    }
}

struct ScreenshotInlineTextEditor: View {
    @ObservedObject var session: ScreenshotSessionState
    let point: CGPoint

    var body: some View {
        AutoFocusAnnotationTextField(
            text: $session.pendingTextValue,
            fontSize: session.strokeSize.fontSize,
            color: NSColor(cgColor: session.selectedColor.cgColor) ?? .systemRed,
            onCommit: { session.commitTextAnnotation() },
            onCancel: {
                session.pendingTextPoint = nil
                session.pendingTextValue = ""
            }
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(width: 240, height: max(30, session.strokeSize.fontSize + 14))
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(cgColor: session.selectedColor.cgColor), lineWidth: 1.2))
        .position(x: min(max(130, point.x + 120), session.screenBounds.width - 130), y: min(max(24, point.y + 16), session.screenBounds.height - 24))
    }
}

struct AutoFocusAnnotationTextField: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let color: NSColor
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = "输入文字，回车确认"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize, weight: .bold)
        field.textColor = color
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text { nsView.stringValue = text }
        nsView.font = .systemFont(ofSize: fontSize, weight: .bold)
        nsView.textColor = color
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AutoFocusAnnotationTextField
        init(parent: AutoFocusAnnotationTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField, parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) { parent.onCommit(); return true }
            if selector == #selector(NSResponder.cancelOperation(_:)) { parent.onCancel(); return true }
            return false
        }
    }
}

enum ScreenshotAnnotationRenderer {
    static func renderMosaicMask(_ item: ScreenshotAnnotation, in ctx: inout GraphicsContext) {
        guard item.tool == .mosaic, let first = item.points.first else { return }
        var p = Path(); p.move(to: first)
        for pt in item.points.dropFirst() { p.addLine(to: pt) }
        ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: item.strokeSize.mosaicBrushRadius * 1.6, lineCap: .round, lineJoin: .round))
    }

    static func render(_ item: ScreenshotAnnotation, in ctx: inout GraphicsContext) {
        let color = Color(cgColor: item.color.cgColor)
        switch item.tool {
        case .move, .mosaic: break
        case .rect:
            guard let a = item.points.first, let b = item.points.last else { break }
            ctx.stroke(Path(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))), with: .color(color), lineWidth: item.strokeSize.lineWidth)
        case .ellipse:
            guard let a = item.points.first, let b = item.points.last else { break }
            ctx.stroke(Path(ellipseIn: CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))), with: .color(color), lineWidth: item.strokeSize.lineWidth)
        case .arrow:
            guard let a = item.points.first, let b = item.points.last else { break }
            let dx = b.x - a.x, dy = b.y - a.y, len = hypot(dx, dy)
            guard len > 1 else { break }
            let ux = dx / len, uy = dy / len, headLen = max(12, item.strokeSize.lineWidth * 3.2), headHalfW = headLen * 0.48
            var line = Path(); line.move(to: a); line.addLine(to: CGPoint(x: b.x - ux * headLen * 0.72, y: b.y - uy * headLen * 0.72))
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: item.strokeSize.lineWidth, lineCap: .round))
            var head = Path(); head.move(to: b)
            head.addLine(to: CGPoint(x: b.x - ux * headLen + uy * headHalfW, y: b.y - uy * headLen - ux * headHalfW))
            head.addLine(to: CGPoint(x: b.x - ux * headLen - uy * headHalfW, y: b.y - uy * headLen + ux * headHalfW))
            head.closeSubpath(); ctx.fill(head, with: .color(color))
        case .pen, .highlighter:
            guard let first = item.points.first else { break }
            var p = Path(); p.move(to: first)
            for pt in item.points.dropFirst() { p.addLine(to: pt) }
            let strokeW = item.tool == .highlighter ? item.strokeSize.lineWidth * 3.0 : item.strokeSize.lineWidth
            let strokeColor = item.tool == .highlighter ? color.opacity(0.36) : color
            ctx.stroke(p, with: .color(strokeColor), style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round))
        case .counter:
            guard let c = item.points.first else { break }
            let r: CGFloat = 12 + item.strokeSize.lineWidth * 0.4
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
            ctx.draw(Text("\(item.counterIndex)").font(.system(size: r * 1.15, weight: .bold)).foregroundStyle(.white), at: c)
        case .text:
            guard let pt = item.points.first, !item.text.isEmpty else { break }
            ctx.draw(Text(item.text).font(.system(size: item.strokeSize.fontSize, weight: .bold)).foregroundStyle(color), at: pt, anchor: .topLeading)
        }
    }
}
