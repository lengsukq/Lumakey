import AppKit
import CoreGraphics
import Foundation
import ImageIO
import LumakeyCore

private func makeSyntheticGifFrame(
    width: Int,
    height: Int,
    topColor: (CGFloat, CGFloat, CGFloat),
    bottomColor: (CGFloat, CGFloat, CGFloat),
    title: String
) -> CGImage? {
    let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    let colors = [
        CGColor(srgbRed: topColor.0, green: topColor.1, blue: topColor.2, alpha: 1.0),
        CGColor(srgbRed: bottomColor.0, green: bottomColor.1, blue: bottomColor.2, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: srgb, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: CGFloat(height)),
            end: CGPoint(x: CGFloat(width), y: 0),
            options: []
        )
    }
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.20))
    ctx.fill(CGRect(x: CGFloat(width) * 0.08, y: CGFloat(height) * 0.30, width: CGFloat(width) * 0.84, height: CGFloat(height) * 0.40))

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: CGFloat(height) * 0.11, weight: .bold),
        .foregroundColor: NSColor.white
    ]
    NSAttributedString(string: title, attributes: attrs).draw(at: NSPoint(x: CGFloat(width) * 0.14, y: CGFloat(height) * 0.43))
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()
}

func testV070GifRecorder() throws {
    let options = GifRecordingOptions(fps: 15, maxDimension: 640, maxDurationSeconds: 45, loopCount: 0)
    check(options.fps == 15 && options.maxDimension == 640 && options.loopCount == 0, "GifRecordingOptions defaults and init")
    check(GifRecordingOptions.dimensionLabel(for: 640) == "640p" && GifRecordingOptions.dimensionLabel(for: 1280) == "HD", "GifRecordingOptions labels")

    let emptyEncoder = GifStreamEncoder(options: options)
    do {
        _ = try emptyEncoder.finalize()
        check(false, "empty GifStreamEncoder finalize should throw")
    } catch let err as GifEncoderError {
        check(err == .emptyRecording, "empty finalize throws .emptyRecording")
    }

    guard let frameA = makeSyntheticGifFrame(width: 1600, height: 1000, topColor: (0.07, 0.52, 0.96), bottomColor: (0.14, 0.18, 0.62), title: "LUMAKEY GIF 01"),
          let frameB = makeSyntheticGifFrame(width: 1600, height: 1000, topColor: (0.96, 0.34, 0.24), bottomColor: (0.64, 0.11, 0.36), title: "LUMAKEY GIF 02"),
          let frameC = makeSyntheticGifFrame(width: 1600, height: 1000, topColor: (0.10, 0.76, 0.52), bottomColor: (0.06, 0.38, 0.44), title: "LUMAKEY GIF 03") else {
        check(false, "synthesize Retina CGImage test frames")
        return
    }

    let encoder = GifStreamEncoder(options: options)
    check(encoder.outputURL.deletingLastPathComponent().lastPathComponent == "lumakey-gifs", "default output bucket is lumakey-gifs")

    check(encoder.appendFrame(frameA, delaySeconds: 0.08) == true, "first frame A stored")
    check(encoder.appendFrame(frameA, delaySeconds: 0.08) == false, "duplicate frame A #2 merged")
    check(encoder.appendFrame(frameA, delaySeconds: 0.08) == false, "duplicate frame A #3 merged")
    check(encoder.appendFrame(frameB, delaySeconds: 0.10) == true, "changed frame B stored")
    check(encoder.appendFrame(frameC, delaySeconds: 0.08) == true, "changed frame C stored")
    check(encoder.appendFrame(frameC, delaySeconds: 0.08) == false, "duplicate frame C #2 merged")

    check(encoder.encodedFrameCount == 3 && encoder.mergedFrameCount == 3 && encoder.capturedFrameCount == 6, "encoder tracks unique & merged frame counts")

    let result = try encoder.finalize()
    defer { try? FileManager.default.removeItem(at: result.fileURL) }

    check(encoder.encodedFrameCount == 0, "finalize immediately releases frame buffer")
    check(result.frameCount == 3 && result.mergedFrameCount == 3, "GifFinalizeResult reports 3 unique & 3 merged frames")
    check(result.pixelSize == CGSize(width: 640, height: 400), "Retina 1600x1000 proportionally downsampled to 640x400, got \(result.pixelSize)")
    check(abs(result.durationSeconds - 0.50) < 0.02, "total duration accumulated accurately (\(result.durationSeconds)s)")
    check(result.fileSizeBytes > 256, "encoded GIF file non-empty (\(result.fileSizeBytes) B)")

    let rawData = try Data(contentsOf: result.fileURL)
    let headerASCII = String(data: rawData.prefix(6), encoding: .ascii)
    check(headerASCII == "GIF89a", "valid GIF89a magic header, got \(headerASCII ?? "nil")")

    guard let source = CGImageSourceCreateWithURL(result.fileURL as CFURL, nil) else {
        check(false, "CGImageSourceCreateWithURL reads output GIF")
        return
    }
    check(CGImageSourceGetCount(source) == 3, "CGImageSourceGetCount matches 3 merged frames")

    if let props0 = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
        let w = props0[kCGImagePropertyPixelWidth] as? Int
        let h = props0[kCGImagePropertyPixelHeight] as? Int
        check(w == 640 && h == 400, "GIF frame 0 pixel dimensions 640x400")
        if let gifDict = props0[kCGImagePropertyGIFDictionary] as? [CFString: Any],
           let delay0 = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double {
            check(abs(delay0 - 0.24) < 0.03, "merged frame 0 unclamped delay ~0.24s, got \(delay0)")
        } else {
            check(false, "GIF frame 0 contains unclamped delay metadata")
        }
    } else {
        check(false, "read GIF frame 0 properties")
    }

    MainActor.assumeIsolated {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }

        let copied = GifStreamEncoder.copyGifToPasteboard(at: result.fileURL, to: pb)
        check(copied, "copyGifToPasteboard returns true")
        let pbGifData = pb.data(forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
        check(pbGifData == rawData, "pasteboard com.compuserve.gif matches exact GIF89a bytes")
        let pbURLs = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        check(pbURLs?.first?.standardizedFileURL == result.fileURL.standardizedFileURL, "pasteboard NSURL matches GIF file URL")
    }

    let tempDiscardEncoder = GifStreamEncoder(options: options)
    _ = tempDiscardEncoder.appendFrame(frameA, delaySeconds: 0.1)
    let discardedURL = tempDiscardEncoder.outputURL
    tempDiscardEncoder.discard()
    check(tempDiscardEncoder.encodedFrameCount == 0 && !FileManager.default.fileExists(atPath: discardedURL.path), "discard releases memory and cleans temp file")

    print("[ok] v0.7.0 Native GIF89a Stream Encoder, Retina Downsample, Static Frame Merge & Dual Pasteboard")
}
