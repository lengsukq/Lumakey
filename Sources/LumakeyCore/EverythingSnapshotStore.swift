import CryptoKit
import Darwin
import Foundation

public struct SnapshotHeaderMetadata: Sendable {
    public let nodeCount: Int
    public let builtAt: Date
    public let reachedNodeLimit: Bool
}

public enum EverythingSnapshotStore {
    private static let magic: [UInt8] = Array("LMKYIDX2".utf8)

    public static func defaultCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("com.queensu.lumakey/everything-index", isDirectory: true)
    }

    public static func snapshotFileURL(scopeKey: String, cacheDirectory: URL? = nil) -> URL {
        let dir = cacheDirectory ?? defaultCacheDirectory()
        let digest = SHA256.hash(data: Data(scopeKey.utf8))
        let hex = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent("idx-\(hex).lmkyidx", isDirectory: false)
    }

    public static func removeAllSnapshots(cacheDirectory: URL? = nil) -> Int64 {
        let dir = cacheDirectory ?? defaultCacheDirectory()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey], options: []
        ) else { return 0 }
        var freed: Int64 = 0
        for url in urls where url.pathExtension == "lmkyidx" {
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            if (try? FileManager.default.removeItem(at: url)) != nil {
                freed += size
            }
        }
        return freed
    }

    public static func readHeaderMetadata(
        scopeKey: String,
        expectedRoots: [URL],
        maxAgeSeconds: TimeInterval = 43_200,
        cacheDirectory: URL? = nil
    ) -> SnapshotHeaderMetadata? {
        let fileURL = snapshotFileURL(scopeKey: scopeKey, cacheDirectory: cacheDirectory)
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4096), !data.isEmpty else { return nil }
        return data.withUnsafeBytes { raw -> SnapshotHeaderMetadata? in
            var offset = 0
            guard let parsed = parseHeader(raw, offset: &offset, expectedRoots: expectedRoots, maxAgeSeconds: maxAgeSeconds) else {
                return nil
            }
            return SnapshotHeaderMetadata(
                nodeCount: Int(parsed.nodeCount),
                builtAt: parsed.builtAt,
                reachedNodeLimit: parsed.reachedNodeLimit
            )
        }
    }

    @discardableResult
    public static func save(_ index: EverythingIndex, scopeKey: String, cacheDirectory: URL? = nil) -> URL? {
        let fileURL = snapshotFileURL(scopeKey: scopeKey, cacheDirectory: cacheDirectory)
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var data = Data()
        data.reserveCapacity(max(4096, index.nodes.count * 26))
        data.append(contentsOf: magic)
        appendLE(index.builtAt.timeIntervalSince1970.bitPattern, to: &data)
        data.append(index.reachedNodeLimit ? 1 : 0)
        appendLE(UInt32(index.rootPaths.count), to: &data)
        for path in index.rootPaths {
            let utf8 = Array(path.utf8)
            appendLE(UInt32(utf8.count), to: &data)
            data.append(contentsOf: utf8)
        }
        appendLE(UInt32(index.nodes.count), to: &data)
        for node in index.nodes {
            appendLE(node.parentID, to: &data)
            appendLE(node.rootIndex, to: &data)
            data.append(node.isDirectory ? 1 : 0)
            var nameStr = node.name
            let writtenLen: Bool = nameStr.withUTF8 { utf8 in
                let count = min(utf8.count, Int(UInt16.max))
                appendLE(UInt16(count), to: &data)
                data.append(UnsafeBufferPointer(start: utf8.baseAddress, count: count))
                return true
            }
            if !writtenLen {
                appendLE(UInt16(0), to: &data)
            }
        }
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    public static func load(
        scopeKey: String,
        expectedRoots: [URL],
        maxAgeSeconds: TimeInterval = 43_200,
        cacheDirectory: URL? = nil
    ) -> EverythingIndex? {
        let fileURL = snapshotFileURL(scopeKey: scopeKey, cacheDirectory: cacheDirectory)
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return nil }
        return data.withUnsafeBytes { raw -> EverythingIndex? in
            var offset = 0
            guard let header = parseHeader(raw, offset: &offset, expectedRoots: expectedRoots, maxAgeSeconds: maxAgeSeconds) else {
                return nil
            }
            var nodes: [IndexedNode] = []
            nodes.reserveCapacity(Int(header.nodeCount))
            for _ in 0..<header.nodeCount {
                guard let parentID = readLE(raw, offset: &offset, as: Int32.self),
                      let rootIndex = readLE(raw, offset: &offset, as: UInt16.self),
                      let isDirByte = readByte(raw, offset: &offset),
                      let nameLen = readLE(raw, offset: &offset, as: UInt16.self),
                      let name = readString(raw, offset: &offset, count: Int(nameLen))
                else { return nil }
                nodes.append(IndexedNode(
                    parentID: parentID,
                    rootIndex: rootIndex,
                    isDirectory: isDirByte != 0,
                    name: name
                ))
            }
            return EverythingIndex(
                rootURLs: header.rootURLs,
                nodes: nodes,
                builtAt: header.builtAt,
                reachedNodeLimit: header.reachedNodeLimit
            )
        }
    }

    private struct ParsedHeader {
        let builtAt: Date
        let reachedNodeLimit: Bool
        let rootURLs: [URL]
        let nodeCount: UInt32
    }

    private static func parseHeader(
        _ raw: UnsafeRawBufferPointer,
        offset: inout Int,
        expectedRoots: [URL],
        maxAgeSeconds: TimeInterval
    ) -> ParsedHeader? {
        guard raw.count >= magic.count + 17 else { return nil }
        for i in 0..<magic.count where raw[i] != magic[i] { return nil }
        offset = magic.count

        guard let builtBits = readLE(raw, offset: &offset, as: UInt64.self),
              let reachedByte = readByte(raw, offset: &offset),
              let rootCount = readLE(raw, offset: &offset, as: UInt32.self)
        else { return nil }

        let builtAt = Date(timeIntervalSince1970: Double(bitPattern: builtBits))
        if Date().timeIntervalSince(builtAt) > maxAgeSeconds { return nil }

        var rootURLs: [URL] = []
        rootURLs.reserveCapacity(Int(rootCount))
        for _ in 0..<rootCount {
            guard let len = readLE(raw, offset: &offset, as: UInt32.self),
                  let path = readString(raw, offset: &offset, count: Int(len))
            else { return nil }
            rootURLs.append(URL(fileURLWithPath: path))
        }
        let expectedPaths = expectedRoots.map { $0.standardizedFileURL.path }
        guard rootURLs.map(\.path) == expectedPaths else { return nil }

        guard let nodeCount = readLE(raw, offset: &offset, as: UInt32.self) else { return nil }
        return ParsedHeader(builtAt: builtAt, reachedNodeLimit: reachedByte != 0, rootURLs: rootURLs, nodeCount: nodeCount)
    }

    private static func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func readByte(_ raw: UnsafeRawBufferPointer, offset: inout Int) -> UInt8? {
        guard offset < raw.count else { return nil }
        let b = raw[offset]
        offset += 1
        return b
    }

    private static func readLE<T: FixedWidthInteger>(_ raw: UnsafeRawBufferPointer, offset: inout Int, as _: T.Type) -> T? {
        let size = MemoryLayout<T>.size
        guard offset + size <= raw.count else { return nil }
        var value: T = 0
        withUnsafeMutableBytes(of: &value) { dst in
            dst.copyBytes(from: UnsafeRawBufferPointer(start: raw.baseAddress!.advanced(by: offset), count: size))
        }
        offset += size
        return T(littleEndian: value)
    }

    private static func readString(_ raw: UnsafeRawBufferPointer, offset: inout Int, count: Int) -> String? {
        guard count >= 0, offset + count <= raw.count else { return nil }
        let slice = UnsafeRawBufferPointer(start: raw.baseAddress!.advanced(by: offset), count: count)
        offset += count
        return String(decoding: slice, as: UTF8.self)
    }
}
