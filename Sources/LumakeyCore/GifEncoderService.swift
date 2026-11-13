import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct GifRecordingOptions: Codable, Sendable, Equatable {
    public static let fpsPresets: [Int] = [10, 15, 20]
    public static let dimensionPresets: [Int] = [640, 960, 1280]

    public var fps: Int
    public var maxDimension: Int
    public var maxDurationSeconds: Int
    public var loopCount: Int
    public var mergeStaticFrames: Bool
    public var showsCursor: Bool

    public init(
        fps: Int = 15, maxDimension: Int = 960, maxDurationSeconds: Int = 45,
        loopCount: Int = 0, mergeStaticFrames: Bool = true, showsCursor: Bool = true
    ) {
        self.fps = min(max(fps, 1), 60)
        self.maxDimension = max(16, maxDimension)
        self.maxDurationSeconds = min(max(maxDurationSeconds, 1), 300)
        self.loopCount = max(0, loopCount)
        self.mergeStaticFrames = mergeStaticFrames
        self.showsCursor = showsCursor
    }

    public var frameIntervalSeconds: Double { 1.0 / Double(max(1, fps)) }

    public static func dimensionLabel(for maxDimension: Int) -> String {
        switch maxDimension {
        case 640: "640p"
        case 960: "960p"
        case 1280: "HD"
        default: "\(maxDimension)px"
        }
    }
}

public struct GifFinalizeResult: Sendable, Equatable {
    public let fileURL: URL
    public let frameCount: Int
    public let mergedFrameCount: Int
    public let durationSeconds: Double
    public let fileSizeBytes: Int64
    public let pixelSize: CGSize

    public init(fileURL: URL, frameCount: Int, mergedFrameCount: Int = 0, durationSeconds: Double, fileSizeBytes: Int64, pixelSize: CGSize) {
        self.fileURL = fileURL; self.frameCount = frameCount; self.mergedFrameCount = mergedFrameCount
        self.durationSeconds = durationSeconds; self.fileSizeBytes = fileSizeBytes; self.pixelSize = pixelSize
    }
}

public enum GifEncoderError: LocalizedError, Sendable, Equatable {
    case emptyRecording
    case destinationCreationFailed(String)
    case finalizationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyRecording: "未捕获到有效录制画面帧。"
        case .destinationCreationFailed(let name): "无法创建 GIF 输出文件：\(name)"
        case .finalizationFailed(let name): "GIF89a 动图编码写入失败：\(name)"
        }
    }
}

public final class GifStreamEncoder: @unchecked Sendable {
    public static let gifPasteboardType = NSPasteboard.PasteboardType("com.compuserve.gif")

    private struct BufferedFrame {
        let image: CGImage
        var delaySeconds: Double
    }

    public let options: GifRecordingOptions
    public let outputURL: URL

    private let lock = NSLock()
    private var frames: [BufferedFrame] = []
    private var lastSignature: [UInt8]?
    private var mergedCount: Int = 0
    private var durationSum: Double = 0
    private var latestPixelSize: CGSize = .zero

    public static func defaultOutputDirectory(tempRoot: URL = FileManager.default.temporaryDirectory) -> URL {
        tempRoot.appendingPathComponent("lumakey-gifs", isDirectory: true)
    }

    public init(options: GifRecordingOptions = GifRecordingOptions(), outputURL: URL? = nil) {
        self.options = options
        if let outputURL {
            try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.outputURL = outputURL
        } else {
            let dir = Self.defaultOutputDirectory()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.outputURL = dir.appendingPathComponent("lumakey-gif-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).gif")
        }
    }

    public var encodedFrameCount: Int { withLock { frames.count } }
    public var mergedFrameCount: Int { withLock { mergedCount } }
    public var capturedFrameCount: Int { withLock { frames.count + mergedCount } }
    public var totalDurationSeconds: Double { withLock { durationSum } }
    public var currentPixelSize: CGSize { withLock { latestPixelSize } }

    @discardableResult
    public func appendFrame(_ image: CGImage, delaySeconds: Double) -> Bool {
        guard image.width > 0, image.height > 0 else { return false }
        let safeDelay = max(0.02, delaySeconds)
        let (targetW, targetH) = Self.scaledDimensions(width: image.width, height: image.height, maxDimension: options.maxDimension)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var rgba = [UInt8](repeating: 0, count: targetW * targetH * 4)
        let rendered: CGImage? = rgba.withUnsafeMutableBytes { rawBuf in
            guard let base = rawBuf.baseAddress,
                  let ctx = CGContext(
                      data: base, width: targetW, height: targetH, bitsPerComponent: 8,
                      bytesPerRow: targetW * 4, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
            let signature = Self.sampleGridSignature(rgba: rawBuf, width: targetW, height: targetH)
            let merged: Bool = withLock {
                if options.mergeStaticFrames, let prev = lastSignature, let lastFrame = frames.last,
                   prev.count == signature.count, lastFrame.image.width == targetW, lastFrame.image.height == targetH,
                   Self.isNearlyStatic(prev, signature) {
                    frames[frames.count - 1].delaySeconds += safeDelay
                    mergedCount += 1; durationSum += safeDelay
                    return true
                }
                lastSignature = signature
                return false
            }
            return merged ? nil : ctx.makeImage()
        }
        guard let normalized = rendered else { return false }
        withLock {
            frames.append(BufferedFrame(image: normalized, delaySeconds: safeDelay))
            durationSum += safeDelay
            latestPixelSize = CGSize(width: targetW, height: targetH)
        }
        return true
    }

    public func finalize() throws -> GifFinalizeResult {
        let (encodedFrames, mergedTotal, totalSeconds, size) = withLock {
            let copy = (frames, mergedCount, durationSum, latestPixelSize)
            frames.removeAll(keepingCapacity: false); lastSignature = nil
            return copy
        }
        guard !encodedFrames.isEmpty else { throw GifEncoderError.emptyRecording }
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL, UTType.gif.identifier as CFString, encodedFrames.count, nil
        ) else { throw GifEncoderError.destinationCreationFailed(outputURL.lastPathComponent) }

        let fileGifProps: [CFString: Any] = [kCGImagePropertyGIFLoopCount: options.loopCount, kCGImagePropertyGIFHasGlobalColorMap: true]
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: fileGifProps] as CFDictionary)
        for frame in encodedFrames {
            let clamped = max(0.02, (frame.delaySeconds * 100.0).rounded() / 100.0)
            let props: [CFString: Any] = [kCGImagePropertyGIFUnclampedDelayTime: clamped, kCGImagePropertyGIFDelayTime: clamped]
            CGImageDestinationAddImage(destination, frame.image, [kCGImagePropertyGIFDictionary: props] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: outputURL)
            throw GifEncoderError.finalizationFailed(outputURL.lastPathComponent)
        }
        Self.normalizeGIF89aHeader(at: outputURL)
        MemoryStats.reclaimFreeHeapPages()
        let bytes = Int64((try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return GifFinalizeResult(
            fileURL: outputURL, frameCount: encodedFrames.count, mergedFrameCount: mergedTotal,
            durationSeconds: totalSeconds, fileSizeBytes: bytes, pixelSize: size
        )
    }

    public func discard() {
        withLock {
            frames.removeAll(keepingCapacity: false); lastSignature = nil
            mergedCount = 0; durationSum = 0; latestPixelSize = .zero
        }
        try? FileManager.default.removeItem(at: outputURL)
        MemoryStats.reclaimFreeHeapPages()
    }

    @MainActor
    @discardableResult
    public static func copyGifToPasteboard(at url: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let gifData = try? Data(contentsOf: url), gifData.count >= 6 else { return false }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(gifData, forType: gifPasteboardType)
        item.setString(url.standardizedFileURL.absoluteString, forType: .fileURL)
        return pasteboard.writeObjects([item])
    }

    public static func scaledDimensions(width: Int, height: Int, maxDimension: Int) -> (Int, Int) {
        let longest = max(width, height)
        guard longest > maxDimension, longest > 0 else { return (max(2, width), max(2, height)) }
        let scale = Double(maxDimension) / Double(longest)
        return (max(2, Int((Double(width) * scale).rounded())), max(2, Int((Double(height) * scale).rounded())))
    }

    private static func sampleGridSignature(rgba: UnsafeMutableRawBufferPointer, width: Int, height: Int) -> [UInt8] {
        let stepX = max(1, width / 96), stepY = max(1, height / 96)
        var sig: [UInt8] = []
        sig.reserveCapacity(((width + stepX - 1) / stepX) * ((height + stepY - 1) / stepY) * 3)
        for y in stride(from: min(stepY / 2, height - 1), to: height, by: stepY) {
            let rowOffset = y * width * 4
            for x in stride(from: min(stepX / 2, width - 1), to: width, by: stepX) {
                let idx = rowOffset + x * 4
                sig.append(rgba[idx]); sig.append(rgba[idx + 1]); sig.append(rgba[idx + 2])
            }
        }
        return sig
    }

    private static func isNearlyStatic(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        let samples = lhs.count / 3
        guard samples > 0 else { return false }
        var totalDiff = 0, changedSamples = 0, limit = max(1, samples / 2000)
        for i in stride(from: 0, to: samples * 3, by: 3) {
            let dr = abs(Int(lhs[i]) - Int(rhs[i])), dg = abs(Int(lhs[i + 1]) - Int(rhs[i + 1])), db = abs(Int(lhs[i + 2]) - Int(rhs[i + 2]))
            totalDiff += dr + dg + db
            if max(dr, max(dg, db)) > 12 {
                changedSamples += 1
                if changedSamples > limit { return false }
            }
        }
        return Double(totalDiff) / Double(lhs.count) <= 1.0
    }

    private static func normalizeGIF89aHeader(at url: URL) {
        guard let fh = try? FileHandle(forUpdating: url) else { return }
        defer { try? fh.close() }
        if let head = try? fh.read(upToCount: 6), head == Data("GIF87a".utf8) {
            try? fh.seek(toOffset: 4); try? fh.write(contentsOf: Data([0x39]))
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body()
    }
}
