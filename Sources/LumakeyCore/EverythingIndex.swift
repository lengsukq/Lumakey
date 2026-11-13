import Darwin
import Foundation

public struct IndexedNode: Sendable, Hashable {
    public let parentID: Int32
    public let rootIndex: UInt16
    public let isDirectory: Bool
    public let name: String

    public init(parentID: Int32, rootIndex: UInt16, isDirectory: Bool, name: String) {
        self.parentID = parentID
        self.rootIndex = rootIndex
        self.isDirectory = isDirectory
        self.name = name
    }
}

public struct EverythingSearchHit: Identifiable, Sendable, Hashable {
    public let id: Int
    public let url: URL
    public let relativeParentPath: String
    public let name: String
    public let isDirectory: Bool
    public let sizeBytes: Int64
    public let modifiedAt: Date
    public let mediaKind: PreviewMediaKind

    public var formattedSize: String {
        if isDirectory || sizeBytes < 0 { return "—" }
        return FastFormatters.formatFileBytes(sizeBytes)
    }
}

public struct EverythingIndex: Sendable {
    public let rootURLs: [URL]
    public let rootPaths: [String]
    public var rootURL: URL { rootURLs.first ?? URL(fileURLWithPath: "/") }
    public let nodes: [IndexedNode]
    public let builtAt: Date
    public let reachedNodeLimit: Bool

    public init(rootURLs: [URL], nodes: [IndexedNode], builtAt: Date, reachedNodeLimit: Bool) {
        self.rootURLs = rootURLs
        self.rootPaths = rootURLs.map { $0.standardizedFileURL.path }
        self.nodes = nodes
        self.builtAt = builtAt
        self.reachedNodeLimit = reachedNodeLimit
    }

    private static let skippedFolderNames: Set<String> = [
        "Library", "node_modules", ".git", ".build", "DerivedData", "Caches",
        ".Spotlight-V100", ".Trashes", "$RECYCLE.BIN", "System Volume Information",
        ".fseventsd", ".TemporaryItems", ".venv", "venv", "__pycache__", "Pods",
        ".gradle", ".cargo", ".rustup", ".npm"
    ]

    private static let packageSuffixBytes: [[UInt8]] = [
        ".app", ".framework", ".bundle", ".xcodeproj", ".xcworkspace", ".playground", ".photoslibrary"
    ].map { Array($0.utf8) }

    public static func build(
        rootURL: URL,
        maxNodes: Int = 80_000,
        includeHidden: Bool = false
    ) throws -> EverythingIndex {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw LumakeyError.directoryNotFound(rootURL)
        }
        return try build(rootURLs: [rootURL], maxNodes: maxNodes, includeHidden: includeHidden)
    }

    public static func build(
        rootURLs: [URL],
        maxNodes: Int = 240_000,
        includeHidden: Bool = false
    ) throws -> EverythingIndex {
        var seenPaths = Set<String>()
        let validRoots: [URL] = rootURLs.filter { url in
            let std = url.standardizedFileURL.path
            guard seenPaths.insert(std).inserted else { return false }
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: std, isDirectory: &isDir) && isDir.boolValue
        }
        guard !validRoots.isEmpty else {
            return EverythingIndex(rootURLs: [], nodes: [], builtAt: Date(), reachedNodeLimit: false)
        }

        var nodes: [IndexedNode] = []
        nodes.reserveCapacity(min(maxNodes, 8192))
        var queues: [[(path: String, parentID: Int32)]] = validRoots.map { [($0.standardizedFileURL.path, Int32(-1))] }
        var heads = Array(repeating: 0, count: validRoots.count)
        var reachedLimit = false
        var active = true

        while active && !reachedLimit {
            active = false
            for rootIdx in 0..<validRoots.count {
                try Task.checkCancellation()
                guard heads[rootIdx] < queues[rootIdx].count else { continue }
                active = true
                let current = queues[rootIdx][heads[rootIdx]]
                heads[rootIdx] += 1

                guard let dir = current.path.withCString({ opendir($0) }) else { continue }
                defer { closedir(dir) }

                while let entry = readdir(dir) {
                    let name = decodeEntryName(entry)
                    if name == "." || name == ".." { continue }
                    if !includeHidden && name.hasPrefix(".") { continue }

                    let childPath = current.path == "/" ? "/\(name)" : "\(current.path)/\(name)"
                    let rawIsDir: Bool
                    switch Int32(entry.pointee.d_type) {
                    case DT_DIR:
                        rawIsDir = true
                    case DT_UNKNOWN:
                        var st = stat()
                        rawIsDir = childPath.withCString { lstat($0, &st) == 0 } && ((st.st_mode & S_IFMT) == S_IFDIR)
                    default:
                        rawIsDir = false
                    }

                    let isPackage = rawIsDir && hasPackageSuffix(name)
                    let isDirectory = rawIsDir && !isPackage
                    if isDirectory && !includeHidden && skippedFolderNames.contains(name) { continue }

                    if nodes.count >= maxNodes {
                        reachedLimit = true
                        break
                    }
                    let nodeID = Int32(nodes.count)
                    nodes.append(IndexedNode(
                        parentID: current.parentID,
                        rootIndex: UInt16(rootIdx),
                        isDirectory: isDirectory,
                        name: name
                    ))
                    if isDirectory {
                        queues[rootIdx].append((childPath, nodeID))
                    }
                }
                if reachedLimit { break }
            }
        }

        return EverythingIndex(rootURLs: validRoots, nodes: nodes, builtAt: Date(), reachedNodeLimit: reachedLimit)
    }

    public func merging(_ other: EverythingIndex) -> EverythingIndex {
        guard !other.nodes.isEmpty else { return self }
        let rootOffset = UInt16(rootURLs.count)
        let nodeOffset = Int32(nodes.count)
        var combinedNodes = nodes
        combinedNodes.reserveCapacity(nodes.count + other.nodes.count)
        for node in other.nodes {
            combinedNodes.append(IndexedNode(
                parentID: node.parentID >= 0 ? node.parentID + nodeOffset : -1,
                rootIndex: node.rootIndex + rootOffset,
                isDirectory: node.isDirectory,
                name: node.name
            ))
        }
        return EverythingIndex(
            rootURLs: rootURLs + other.rootURLs,
            nodes: combinedNodes,
            builtAt: Date(),
            reachedNodeLimit: reachedNodeLimit || other.reachedNodeLimit
        )
    }

    private static func decodeEntryName(_ entry: UnsafeMutablePointer<dirent>) -> String {
        let len = Int(entry.pointee.d_namlen) + 1
        return withUnsafePointer(to: entry.pointee.d_name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: len) { String(cString: $0) }
        }
    }

    public static func hasPackageSuffix(_ name: String) -> Bool {
        guard name.utf8.count >= 4 else { return false }
        var copy = name
        return copy.withUTF8 { utf8 in
            for suffix in packageSuffixBytes where utf8.count >= suffix.count {
                let start = utf8.count - suffix.count
                var matched = true
                for i in 0..<suffix.count {
                    let b = utf8[start &+ i]
                    let folded = (b >= 0x41 && b <= 0x5A) ? (b &+ 32) : b
                    if folded != suffix[i] { matched = false; break }
                }
                if matched { return true }
            }
            return false
        }
    }

    public static func extractExtensionLower(fromName name: String) -> String {
        var copy = name
        return copy.withUTF8 { utf8 in
            guard utf8.count >= 2 else { return "" }
            var dotPos = -1
            var idx = utf8.count - 1
            while idx > 0 {
                if utf8[idx] == 0x2E {
                    dotPos = idx
                    break
                }
                idx &-= 1
            }
            guard dotPos > 0, dotPos + 1 < utf8.count else { return "" }
            let extStart = dotPos + 1
            let extCount = utf8.count - extStart
            return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: extCount) { tmp in
                for i in 0..<extCount {
                    let b = utf8[extStart &+ i]
                    if b >= 0x80 {
                        let slice = UnsafeBufferPointer(rebasing: utf8[extStart...])
                        return String(decoding: slice, as: UTF8.self).lowercased()
                    }
                    tmp[i] = (b >= 0x41 && b <= 0x5A) ? (b &+ 32) : b
                }
                return String(decoding: UnsafeBufferPointer(tmp), as: UTF8.self)
            }
        }
    }

    public static func extractExtensionLower(_ lowerName: String) -> String {
        extractExtensionLower(fromName: lowerName)
    }
}
