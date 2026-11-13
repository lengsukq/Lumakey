import AVFoundation
import CoreMedia
import Foundation
import ObjectiveC
import UniformTypeIdentifiers

public struct VideoStreamMetadata: Sendable, Hashable {
    public let width: Int
    public let height: Int
    public let fps: Double
    public let codecBadge: String

    public init(width: Int, height: Int, fps: Double, codecBadge: String) {
        self.width = width
        self.height = height
        self.fps = fps
        self.codecBadge = codecBadge
    }

    public var resolutionLabel: String {
        if width >= 3800 || height >= 2100 { return "4K" }
        if width >= 1900 || height >= 1070 { return "1080P" }
        if width > 0 && height > 0 { return "\(width)×\(height)" }
        return "HD"
    }
}

public enum ResolvedVideoPlayback: @unchecked Sendable {
    case ready(item: AVPlayerItem, metadata: VideoStreamMetadata, tempFileURL: URL?)
    case unsupported(reason: String)
}

public final class Hev1ResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    private nonisolated(unsafe) static var assocKey: UInt8 = 0
    private static let hev1Pattern = Data([0x68, 0x65, 0x76, 0x31, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    private static let hvc1Bytes: [UInt8] = [0x68, 0x76, 0x63, 0x31]

    public let fileURL: URL
    public let fileSize: Int64
    public let patchOffsets: [Int64]
    private let loaderQueue = DispatchQueue(label: "app.lumakey.hev1.loader", qos: .userInitiated)
    private var activeHandles: [ObjectIdentifier: FileHandle] = [:]

    public init(fileURL: URL, fileSize: Int64, patchOffsets: [Int64]) {
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.patchOffsets = patchOffsets
    }

    public static func findHev1SampleEntryOffsets(in fileURL: URL) -> (fileSize: Int64, offsets: [Int64]) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return (0, []) }
        defer { try? handle.close() }
        let fileSize = Int64((try? handle.seekToEnd()) ?? 0)
        guard fileSize >= 16 else { return (fileSize, []) }

        var offset: Int64 = 0
        var sawMoov = false
        var hits: [Int64] = []

        while offset + 8 <= fileSize {
            try? handle.seek(toOffset: UInt64(offset))
            guard let hdr = try? handle.read(upToCount: 16), hdr.count >= 8 else { break }
            let size32 = UInt32(hdr[0]) << 24 | UInt32(hdr[1]) << 16 | UInt32(hdr[2]) << 8 | UInt32(hdr[3])
            let type = String(bytes: hdr[4..<8], encoding: .ascii) ?? ""
            var boxSize: Int64
            if size32 == 1 {
                guard hdr.count == 16 else { break }
                var size64: UInt64 = 0
                for i in 8..<16 { size64 = (size64 << 8) | UInt64(hdr[i]) }
                boxSize = Int64(min(size64, UInt64(Int64.max)))
            } else if size32 == 0 {
                boxSize = fileSize - offset
            } else {
                boxSize = Int64(size32)
            }
            guard boxSize >= 8 else { break }

            if type == "moov" && boxSize <= 64 * 1024 * 1024 {
                sawMoov = true
                try? handle.seek(toOffset: UInt64(offset))
                if let moovData = try? handle.read(upToCount: Int(boxSize)) {
                    hits.append(contentsOf: scanPatternOffsets(in: moovData, baseOffset: offset))
                }
            }
            let nextOffset = offset + boxSize
            if nextOffset <= offset { break }
            offset = nextOffset
        }

        if !sawMoov && fileSize <= 8 * 1024 * 1024 {
            try? handle.seek(toOffset: 0)
            if let head = try? handle.read(upToCount: Int(min(fileSize, 1_048_576))) {
                hits = scanPatternOffsets(in: head, baseOffset: 0)
            }
        }
        return (fileSize, hits)
    }

    private static func scanPatternOffsets(in data: Data, baseOffset: Int64) -> [Int64] {
        var foundOffsets: [Int64] = []
        var range = data.startIndex..<data.endIndex
        while let found = data.range(of: hev1Pattern, options: [], in: range) {
            foundOffsets.append(baseOffset + Int64(found.lowerBound - data.startIndex))
            let next = found.lowerBound + hev1Pattern.count
            if next >= data.endIndex { break }
            range = next..<data.endIndex
        }
        return foundOffsets
    }

    public static func makePatchedAsset(fileURL: URL, fileSize: Int64, patchOffsets: [Int64]) -> AVURLAsset? {
        guard var comps = URLComponents(url: fileURL, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = "lumakey-hev1"
        guard let customURL = comps.url else { return nil }
        let loader = Hev1ResourceLoader(fileURL: fileURL, fileSize: fileSize, patchOffsets: patchOffsets)
        let asset = AVURLAsset(url: customURL)
        asset.resourceLoader.setDelegate(loader, queue: loader.loaderQueue)
        objc_setAssociatedObject(asset, &assocKey, loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return asset
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = UTType.mpeg4Movie.identifier
            info.contentLength = fileSize
            info.isByteRangeAccessSupported = true
        }
        guard let dataReq = loadingRequest.dataRequest else {
            loadingRequest.finishLoading()
            return true
        }
        let startOffset = dataReq.currentOffset > 0 ? dataReq.currentOffset : dataReq.requestedOffset
        let totalLength = dataReq.requestsAllDataToEndOfResource ? max(0, fileSize - startOffset) : Int64(dataReq.requestedLength)
        guard totalLength > 0 else { loadingRequest.finishLoading(); return true }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            loadingRequest.finishLoading(with: NSError(domain: "app.lumakey.hev1", code: -1)); return true
        }
        do { try handle.seek(toOffset: UInt64(startOffset)) } catch {
            try? handle.close(); loadingRequest.finishLoading(with: error); return true
        }
        activeHandles[ObjectIdentifier(loadingRequest)] = handle
        let endOffset = startOffset + totalLength
        loaderQueue.async { [weak self] in self?.feedNextChunk(loadingRequest: loadingRequest, dataReq: dataReq, cursor: startOffset, endOffset: endOffset) }
        return true
    }

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        closeHandle(for: loadingRequest)
    }

    private func closeHandle(for loadingRequest: AVAssetResourceLoadingRequest) {
        if let handle = activeHandles.removeValue(forKey: ObjectIdentifier(loadingRequest)) { try? handle.close() }
    }

    private func feedNextChunk(loadingRequest: AVAssetResourceLoadingRequest, dataReq: AVAssetResourceLoadingDataRequest, cursor: Int64, endOffset: Int64) {
        guard !loadingRequest.isCancelled, let handle = activeHandles[ObjectIdentifier(loadingRequest)] else {
            closeHandle(for: loadingRequest); return
        }
        let remaining = endOffset - cursor
        guard remaining > 0, var chunk = try? handle.read(upToCount: Int(min(131_072, remaining))), !chunk.isEmpty else {
            closeHandle(for: loadingRequest); loadingRequest.finishLoading(); return
        }
        let chunkEnd = cursor + Int64(chunk.count)
        for patchPos in patchOffsets {
            for byteIdx in 0..<4 {
                let gPos = patchPos + Int64(byteIdx)
                if gPos >= cursor && gPos < chunkEnd { chunk[Int(gPos - cursor)] = Self.hvc1Bytes[byteIdx] }
            }
        }
        dataReq.respond(with: chunk)
        if chunkEnd >= endOffset {
            closeHandle(for: loadingRequest); loadingRequest.finishLoading()
        } else {
            loaderQueue.async { [weak self] in self?.feedNextChunk(loadingRequest: loadingRequest, dataReq: dataReq, cursor: chunkEnd, endOffset: endOffset) }
        }
    }
}

public enum VideoPlaybackCompat {
    public static var tempDirectoryURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-cinema", isDirectory: true)
    }

    public static func preparePlayback(for url: URL, allowFFmpegRemux: Bool = true) async -> ResolvedVideoPlayback {
        let nativeAsset = AVURLAsset(url: url)
        if let meta = await inspectDecodableTrack(in: nativeAsset, badgeSuffix: "原生硬解") {
            return .ready(item: AVPlayerItem(asset: nativeAsset), metadata: meta, tempFileURL: nil)
        }

        let scan = await Task.detached(priority: .userInitiated) {
            Hev1ResourceLoader.findHev1SampleEntryOffsets(in: url)
        }.value
        if !scan.offsets.isEmpty,
           let patchedAsset = Hev1ResourceLoader.makePatchedAsset(fileURL: url, fileSize: scan.fileSize, patchOffsets: scan.offsets),
           let meta = await inspectDecodableTrack(in: patchedAsset, badgeSuffix: "HEVC · VideoToolbox 硬解") {
            return .ready(item: AVPlayerItem(asset: patchedAsset), metadata: meta, tempFileURL: nil)
        }

        if allowFFmpegRemux, let ffmpegPath = HostToolingStatus.detect().ffmpegPath {
            if let remuxedURL = await remuxToFastMP4(sourceURL: url, ffmpegPath: ffmpegPath) {
                let remuxAsset = AVURLAsset(url: remuxedURL)
                if let meta = await inspectDecodableTrack(in: remuxAsset, badgeSuffix: "无损快封 · 硬解") {
                    return .ready(item: AVPlayerItem(asset: remuxAsset), metadata: meta, tempFileURL: remuxedURL)
                }
                try? FileManager.default.removeItem(at: remuxedURL)
            }
        }
        return .unsupported(reason: "当前视频封装或编码超出 macOS 原生解码范围，建议使用 IINA 打开。")
    }

    public static func cleanupTempDirectory() {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
    }

    private static func inspectDecodableTrack(in asset: AVURLAsset, badgeSuffix: String) async -> VideoStreamMetadata? {
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else { return nil }
        var bestMeta: VideoStreamMetadata?
        for track in tracks {
            let decodable = (try? await track.load(.isDecodable)) ?? false
            let playable = (try? await track.load(.isPlayable)) ?? false
            guard decodable && playable else { continue }
            let size = (try? await track.load(.naturalSize)) ?? .zero
            let fps = Double((try? await track.load(.nominalFrameRate)) ?? 0)
            let w = Int(abs(size.width)), h = Int(abs(size.height))
            let tempMeta = VideoStreamMetadata(width: w, height: h, fps: fps, codecBadge: "")
            let badge = "\(tempMeta.resolutionLabel) \(badgeSuffix)"
            let candidate = VideoStreamMetadata(width: w, height: h, fps: fps, codecBadge: badge)
            if bestMeta == nil || (fps > 0 && (bestMeta?.fps ?? 0) == 0) || (w * h > (bestMeta?.width ?? 0) * (bestMeta?.height ?? 0)) {
                bestMeta = candidate
            }
        }
        return bestMeta
    }

    private static func remuxToFastMP4(sourceURL: URL, ffmpegPath: String) async -> URL? {
        let probePath = HostToolingStatus.detect().ffprobePath
        return await Task.detached(priority: .userInitiated) {
            try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
            let destURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString).mp4")
            let codecs = probeStreamCodecs(sourceURL: sourceURL, ffprobePath: probePath)
            var args = ["-y", "-nostdin", "-loglevel", "error", "-i", sourceURL.path, "-map", "0:v:0", "-map", "0:a:0?"]
            switch codecs.video {
            case "hevc": args += ["-c:v", "copy", "-tag:v", "hvc1"]
            case "h264": args += ["-c:v", "copy"]
            default: args += ["-c:v", "h264_videotoolbox", "-q:v", "65"]
            }
            if ["aac", "mp3", "ac3", "eac3", "alac"].contains(codecs.audio) {
                args += ["-c:a", "copy"]
            } else {
                args += ["-c:a", "aac", "-b:a", "192k"]
            }
            args += [destURL.path]

            guard let res = try? ProcessSupervisor.shared.run(executableURL: URL(fileURLWithPath: ffmpegPath), arguments: args, timeoutSeconds: 90, maxOutputBytes: 4096),
                  res.exitCode == 0, FileManager.default.fileExists(atPath: destURL.path) else {
                try? FileManager.default.removeItem(at: destURL)
                return nil
            }
            return destURL
        }.value
    }

    private static func probeStreamCodecs(sourceURL: URL, ffprobePath: String?) -> (video: String, audio: String) {
        guard let ffprobePath else { return ("h264", "aac") }
        let url = URL(fileURLWithPath: ffprobePath)
        let vRes = try? ProcessSupervisor.shared.run(executableURL: url, arguments: ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_name", "-of", "default=nw=1:nk=1", sourceURL.path], timeoutSeconds: 5, maxOutputBytes: 128)
        let aRes = try? ProcessSupervisor.shared.run(executableURL: url, arguments: ["-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_name", "-of", "default=nw=1:nk=1", sourceURL.path], timeoutSeconds: 5, maxOutputBytes: 128)
        return (
            vRes?.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "h264",
            aRes?.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "aac"
        )
    }
}
