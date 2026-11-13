import AppKit
import CoreGraphics
import LumakeyCore
import UniformTypeIdentifiers

@MainActor
final class IconCache {
    static let shared = IconCache()

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 384
        c.totalCostLimit = 12 * 1024 * 1024
        return c
    }()

    private init() {}

    func icon(for entry: FileEntry) -> NSImage {
        if entry.isPackage, entry.extensionLowercased == "app" {
            return appIcon(for: entry.url)
        }
        return fileIcon(
            isDirectory: entry.isDirectory && !entry.isPackage,
            extensionLowercased: entry.extensionLowercased
        )
    }

    func appIcon(for url: URL) -> NSImage {
        let key = "app:\(url.path)" as NSString
        if let hit = cache.object(forKey: key) {
            return hit
        }
        let rendered = autoreleasepool { () -> (image: NSImage, costBytes: Int) in
            let raw = NSWorkspace.shared.icon(forFile: url.path)
            return Self.rasterize(raw, pointSize: 38)
        }
        cache.setObject(rendered.image, forKey: key, cost: rendered.costBytes)
        return rendered.image
    }

    func fileIcon(isDirectory: Bool, extensionLowercased ext: String) -> NSImage {
        let keyString = isDirectory ? "dir" : "ext:\(ext)"
        let key = keyString as NSString
        if let hit = cache.object(forKey: key) {
            return hit
        }
        let rendered = autoreleasepool { () -> (image: NSImage, costBytes: Int) in
            let type: UTType = isDirectory ? .folder : (UTType(filenameExtension: ext) ?? .data)
            let raw = NSWorkspace.shared.icon(for: type)
            return Self.rasterize(raw, pointSize: 32)
        }
        cache.setObject(rendered.image, forKey: key, cost: rendered.costBytes)
        return rendered.image
    }

    func prewarmDockIcons(_ apps: [InstalledAppItem]) {
        for app in apps.prefix(8) {
            _ = appIcon(for: app.url)
        }
    }

    func clearAll() {
        cache.removeAllObjects()
    }

    private static func rasterize(_ source: NSImage, pointSize: CGFloat) -> (image: NSImage, costBytes: Int) {
        let px = max(16, Int((pointSize * 2.0).rounded()))
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: px,
            height: px,
            bitsPerComponent: 8,
            bytesPerRow: px * 4,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            source.size = NSSize(width: pointSize, height: pointSize)
            return (source, px * px * 4)
        }

        let rect = CGRect(x: 0, y: 0, width: px, height: px)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        if let cg = ctx.makeImage() {
            let compact = NSImage(cgImage: cg, size: NSSize(width: pointSize, height: pointSize))
            return (compact, px * px * 4)
        }
        source.size = NSSize(width: pointSize, height: pointSize)
        return (source, px * px * 4)
    }
}
