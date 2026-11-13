#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate-icon.swift <output-iconset-dir>\n", stderr)
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func renderIconPNG(pixelSize: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let s = CGFloat(pixelSize)
    let inset = s * 0.08
    let bodyRect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let outerPath = NSBezierPath(roundedRect: bodyRect, xRadius: bodyRect.width * 0.24, yRadius: bodyRect.width * 0.24)

    let baseGrad = NSGradient(colors: [
        NSColor(calibratedRed: 0.14, green: 0.58, blue: 0.99, alpha: 1.0),
        NSColor(calibratedRed: 0.22, green: 0.30, blue: 0.94, alpha: 1.0),
        NSColor(calibratedRed: 0.44, green: 0.18, blue: 0.88, alpha: 1.0)
    ])
    baseGrad?.draw(in: outerPath, angle: -55)

    NSGraphicsContext.current?.cgContext.saveGState()
    outerPath.addClip()
    let sheenRect = NSRect(x: bodyRect.minX, y: bodyRect.midY, width: bodyRect.width, height: bodyRect.height * 0.5)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.45), NSColor.white.withAlphaComponent(0.02)])?
        .draw(in: sheenRect, angle: -90)
    NSGraphicsContext.current?.cgContext.restoreGState()

    NSColor.white.withAlphaComponent(0.58).setStroke()
    outerPath.lineWidth = max(1.0, s * 0.018)
    outerPath.stroke()

    let glassRect = bodyRect.insetBy(dx: bodyRect.width * 0.19, dy: bodyRect.height * 0.19)
    let glassPath = NSBezierPath(roundedRect: glassRect, xRadius: glassRect.width * 0.28, yRadius: glassRect.width * 0.28)
    NSColor.white.withAlphaComponent(0.22).setFill()
    glassPath.fill()
    NSColor.white.withAlphaComponent(0.68).setStroke()
    glassPath.lineWidth = max(1.0, s * 0.014)
    glassPath.stroke()

    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.36, weight: .semibold)
    if let sym = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: sym.size, flipped: false) { rect in
            sym.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let drawSize = NSSize(width: s * 0.38, height: s * 0.38)
        let drawRect = NSRect(x: (s - drawSize.width) / 2, y: (s - drawSize.height) / 2, width: drawSize.width, height: drawSize.height)
        tinted.draw(in: drawRect)
    }

    return rep.representation(using: .png, properties: [:])!
}

let slots: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for slot in slots {
    try renderIconPNG(pixelSize: slot.px).write(to: outputDir.appendingPathComponent(slot.name))
}
