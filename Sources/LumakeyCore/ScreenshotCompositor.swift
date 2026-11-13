import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

public struct PasteboardSnapshot: Sendable {
    private struct ItemEntry: Sendable {
        let rawType: String
        let data: Data
    }

    private let items: [[ItemEntry]]

    @MainActor
    public static func capture(from pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        let captured: [[ItemEntry]] = (pasteboard.pasteboardItems ?? []).compactMap { item in
            let entries: [ItemEntry] = item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return ItemEntry(rawType: type.rawValue, data: data)
            }
            return entries.isEmpty ? nil : entries
        }
        return PasteboardSnapshot(items: captured)
    }

    @MainActor
    public func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let pbItems: [NSPasteboardItem] = items.map { entries in
            let pbItem = NSPasteboardItem()
            for entry in entries {
                pbItem.setData(entry.data, forType: NSPasteboard.PasteboardType(entry.rawType))
            }
            return pbItem
        }
        pasteboard.writeObjects(pbItems)
    }
}

public enum ScreenshotCompositor {
    @MainActor
    @discardableResult
    public static func copyImageToPasteboard(
        _ cgImage: CGImage,
        scale: CGFloat = 2.0,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        let safeScale = max(scale, 1.0)
        let logicalSize = NSSize(
            width: max(1, CGFloat(cgImage.width) / safeScale),
            height: max(1, CGFloat(cgImage.height) / safeScale)
        )
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = logicalSize
        let pngData = rep.representation(using: .png, properties: [:])
        let tiffData = rep.tiffRepresentation
        pasteboard.clearContents()
        if pngData != nil || tiffData != nil {
            let item = NSPasteboardItem()
            if let pngData { item.setData(pngData, forType: .png) }
            if let tiffData { item.setData(tiffData, forType: .tiff) }
            return pasteboard.writeObjects([item])
        }
        return pasteboard.writeObjects([NSImage(cgImage: cgImage, size: logicalSize)])
    }

    @MainActor
    @discardableResult
    public static func copyImageFileToPasteboard(at url: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        if let pngData = try? Data(contentsOf: url), !pngData.isEmpty,
           let rep = NSBitmapImageRep(data: pngData) {
            let item = NSPasteboardItem()
            item.setData(pngData, forType: .png)
            if let tiffData = rep.tiffRepresentation { item.setData(tiffData, forType: .tiff) }
            return pasteboard.writeObjects([item])
        }
        if let img = NSImage(contentsOf: url) {
            return pasteboard.writeObjects([img])
        }
        return false
    }
    public static func samplePixelColor(in cgImage: CGImage, point: CGPoint, screenBounds: CGRect) -> String {
        guard screenBounds.width > 0, screenBounds.height > 0, cgImage.width > 0, cgImage.height > 0 else {
            return "#000000"
        }
        let px = max(0, min(cgImage.width - 1, Int((point.x - screenBounds.minX) * CGFloat(cgImage.width) / screenBounds.width)))
        let py = max(0, min(cgImage.height - 1, Int((point.y - screenBounds.minY) * CGFloat(cgImage.height) / screenBounds.height)))
        var pixel: [UInt8] = [0, 0, 0, 0]
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return "#000000"
        }
        ctx.draw(cgImage, in: CGRect(x: -px, y: -(cgImage.height - 1 - py), width: cgImage.width, height: cgImage.height))
        return String(format: "#%02X%02X%02X", pixel[0], pixel[1], pixel[2])
    }

    public static func makePixelatedPreview(from cgImage: CGImage, cellPixelSize: Int = 16) -> CGImage? {
        let step = max(4, cellPixelSize)
        let smallW = max(2, cgImage.width / step)
        let smallH = max(2, cgImage.height / step)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: smallW,
            height: smallH,
            bitsPerComponent: 8,
            bytesPerRow: smallW * 4,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        return ctx.makeImage()
    }

    public static func renderCroppedImage(
        baseImage: CGImage,
        screenBounds: CGRect,
        selectionRect: CGRect,
        annotations: [ScreenshotAnnotation]
    ) throws -> CGImage {
        let clamped = selectionRect.intersection(screenBounds).standardized
        guard clamped.width >= 2, clamped.height >= 2 else {
            throw LumakeyError.visionFailed("截图选区尺寸过小。")
        }
        let scaleX = CGFloat(baseImage.width) / max(screenBounds.width, 1)
        let scaleY = CGFloat(baseImage.height) / max(screenBounds.height, 1)
        let pixelRect = CGRect(
            x: floor((clamped.minX - screenBounds.minX) * scaleX),
            y: floor((clamped.minY - screenBounds.minY) * scaleY),
            width: max(2, round(clamped.width * scaleX)),
            height: max(2, round(clamped.height * scaleY))
        )
        guard let cropped = baseImage.cropping(to: pixelRect) else {
            throw LumakeyError.visionFailed("无法裁剪选中区域图像。")
        }
        if annotations.isEmpty { return cropped }

        let w = cropped.width, h = cropped.height
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw LumakeyError.visionFailed("无法创建标注合成画布。")
        }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scaleX, y: -scaleY)
        ctx.translateBy(x: -clamped.minX, y: -clamped.minY)

        for item in annotations {
            draw(item, into: ctx, baseCropped: cropped, origin: clamped.origin, scaleX: scaleX, scaleY: scaleY)
        }
        ctx.restoreGState()
        guard let result = ctx.makeImage() else {
            throw LumakeyError.visionFailed("导出合成截图失败。")
        }
        return result
    }

    public static func saveTempCapture(_ cgImage: CGImage) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-captures", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("lumakey-pin-\(UUID().uuidString).png")
        try writePNG(cgImage, to: url)
        return url
    }

    public static func writePNG(_ cgImage: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw LumakeyError.visionFailed("无法写入 PNG 文件：\(url.lastPathComponent)")
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        if !CGImageDestinationFinalize(dest) {
            throw LumakeyError.visionFailed("PNG 编码失败：\(url.lastPathComponent)")
        }
    }

    private static func draw(
        _ item: ScreenshotAnnotation,
        into ctx: CGContext,
        baseCropped: CGImage,
        origin: CGPoint,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let color = item.color.cgColor
        switch item.tool {
        case .move: break
        case .rect:
            guard let a = item.points.first, let b = item.points.last else { break }
            ctx.setStrokeColor(color); ctx.setLineWidth(item.strokeSize.lineWidth)
            ctx.stroke(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)))
        case .ellipse:
            guard let a = item.points.first, let b = item.points.last else { break }
            ctx.setStrokeColor(color); ctx.setLineWidth(item.strokeSize.lineWidth)
            ctx.strokeEllipse(in: CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)))
        case .arrow:
            guard let a = item.points.first, let b = item.points.last else { break }
            drawArrow(from: a, to: b, color: color, lineWidth: item.strokeSize.lineWidth, in: ctx)
        case .pen, .highlighter:
            guard !item.points.isEmpty else { break }
            let alphaColor = item.tool == .highlighter ? (color.copy(alpha: 0.36) ?? color) : color
            ctx.setStrokeColor(alphaColor)
            ctx.setLineWidth(item.tool == .highlighter ? item.strokeSize.lineWidth * 3.0 : item.strokeSize.lineWidth)
            ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.beginPath(); ctx.move(to: item.points[0])
            for pt in item.points.dropFirst() { ctx.addLine(to: pt) }
            ctx.strokePath()
        case .mosaic:
            drawMosaic(points: item.points, brushRadius: item.strokeSize.mosaicBrushRadius, baseCropped: baseCropped, origin: origin, scaleX: scaleX, scaleY: scaleY, in: ctx)
        case .counter:
            guard let center = item.points.first else { break }
            let r: CGFloat = 12 + item.strokeSize.lineWidth * 0.4
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            drawText("\(item.counterIndex)", at: CGPoint(x: center.x - r, y: center.y - r * 0.68), fontSize: r * 1.15, color: .white, centeredWidth: r * 2, in: ctx)
        case .text:
            guard let pt = item.points.first, !item.text.isEmpty else { break }
            let nsColor = NSColor(cgColor: color) ?? .systemRed
            drawText(item.text, at: pt, fontSize: item.strokeSize.fontSize, color: nsColor, centeredWidth: nil, in: ctx)
        }
    }

    private static func drawArrow(from a: CGPoint, to b: CGPoint, color: CGColor, lineWidth: CGFloat, in ctx: CGContext) {
        let dx = b.x - a.x, dy = b.y - a.y, len = hypot(dx, dy)
        guard len > 1 else { return }
        let ux = dx / len, uy = dy / len, headLen = max(12, lineWidth * 3.2), headHalfW = headLen * 0.48
        let basePt = CGPoint(x: b.x - ux * headLen * 0.72, y: b.y - uy * headLen * 0.72)
        ctx.setStrokeColor(color); ctx.setLineWidth(lineWidth); ctx.setLineCap(.round)
        ctx.beginPath(); ctx.move(to: a); ctx.addLine(to: basePt); ctx.strokePath()
        let left = CGPoint(x: b.x - ux * headLen + uy * headHalfW, y: b.y - uy * headLen - ux * headHalfW)
        let right = CGPoint(x: b.x - ux * headLen - uy * headHalfW, y: b.y - uy * headLen + ux * headHalfW)
        ctx.setFillColor(color); ctx.beginPath(); ctx.move(to: b); ctx.addLine(to: left); ctx.addLine(to: right); ctx.closePath(); ctx.fillPath()
    }

    private static func drawMosaic(
        points: [CGPoint], brushRadius: CGFloat, baseCropped: CGImage, origin: CGPoint, scaleX: CGFloat, scaleY: CGFloat, in ctx: CGContext
    ) {
        let cellSize: CGFloat = max(8, brushRadius * 0.75)
        var visited = Set<String>()
        for pt in points {
            let minCol = Int(floor((pt.x - brushRadius) / cellSize)), maxCol = Int(floor((pt.x + brushRadius) / cellSize))
            let minRow = Int(floor((pt.y - brushRadius) / cellSize)), maxRow = Int(floor((pt.y + brushRadius) / cellSize))
            for row in minRow...maxRow {
                for col in minCol...maxCol {
                    let key = "\(col),\(row)"
                    guard visited.insert(key).inserted else { continue }
                    let cellRect = CGRect(x: CGFloat(col) * cellSize, y: CGFloat(row) * cellSize, width: cellSize, height: cellSize)
                    let samplePt = CGPoint(x: (cellRect.midX - origin.x) * scaleX, y: (cellRect.midY - origin.y) * scaleY)
                    let hex = samplePixelColor(in: baseCropped, point: samplePt, screenBounds: CGRect(x: 0, y: 0, width: baseCropped.width, height: baseCropped.height))
                    ctx.setFillColor(cgColorFromHex(hex))
                    ctx.fill(cellRect)
                }
            }
        }
    }

    private static func cgColorFromHex(_ hex: String) -> CGColor {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let val = Int(clean, radix: 16) else { return CGColor(gray: 0.5, alpha: 1) }
        return CGColor(srgbRed: CGFloat((val >> 16) & 0xFF) / 255, green: CGFloat((val >> 8) & 0xFF) / 255, blue: CGFloat(val & 0xFF) / 255, alpha: 1)
    }

    private static func drawText(_ text: String, at origin: CGPoint, fontSize: CGFloat, color: NSColor, centeredWidth: CGFloat?, in ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let para = NSMutableParagraphStyle()
        para.alignment = centeredWidth == nil ? .left : .center
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .bold), .foregroundColor: color, .paragraphStyle: para]
        let str = NSAttributedString(string: text, attributes: attrs)
        if let w = centeredWidth { str.draw(in: CGRect(x: origin.x, y: origin.y, width: w, height: fontSize * 1.4)) }
        else { str.draw(at: origin) }
        NSGraphicsContext.restoreGraphicsState()
    }
}
