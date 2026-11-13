import Darwin
import Foundation

public extension EverythingIndex {
    private static let fsSkippedFolders: Set<String> = [
        "Library", "node_modules", ".git", ".build", "DerivedData", "Caches",
        ".Spotlight-V100", ".Trashes", "$RECYCLE.BIN", "System Volume Information",
        ".fseventsd", ".TemporaryItems", ".venv", "venv", "__pycache__", "Pods",
        ".gradle", ".cargo", ".rustup", ".npm"
    ]

    func applyingFSEventDirectories(_ rawChangedDirs: Set<String>, maxNodes: Int = 260_000) -> EverythingIndex {
        guard !rawChangedDirs.isEmpty, !rootPaths.isEmpty else { return self }
        let resolvedRoots = rootPaths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path }
        var changedSet = Set<String>()
        for raw in rawChangedDirs {
            let std = URL(fileURLWithPath: raw).standardizedFileURL.path
            let res = URL(fileURLWithPath: raw).resolvingSymlinksInPath().standardizedFileURL.path
            for (idx, rootPath) in rootPaths.enumerated() {
                let resRoot = resolvedRoots[idx]
                if std == rootPath || std.hasPrefix(rootPath + "/") { changedSet.insert(std) }
                if res == resRoot || res.hasPrefix(resRoot + "/") {
                    changedSet.insert(resRoot == rootPath ? res : rootPath + String(res.dropFirst(resRoot.count)))
                }
            }
        }
        guard !changedSet.isEmpty else { return self }

        var oldPaths = Array(repeating: "", count: nodes.count)
        var oldChildren = Array(repeating: [Int](), count: nodes.count)
        var oldRootChildren = Array(repeating: [Int](), count: rootPaths.count)
        var oldDirIDByPath: [String: Int] = [:]
        for idx in 0..<nodes.count {
            let node = nodes[idx]
            let parentID = Int(node.parentID)
            let rootIdx = Int(node.rootIndex)
            let parentPath = parentID >= 0 && parentID < idx ? oldPaths[parentID] : rootPaths[rootIdx]
            let fullPath = parentPath == "/" ? "/\(node.name)" : "\(parentPath)/\(node.name)"
            oldPaths[idx] = fullPath
            if parentID >= 0 && parentID < idx {
                oldChildren[parentID].append(idx)
            } else if rootIdx < oldRootChildren.count {
                oldRootChildren[rootIdx].append(idx)
            }
            if node.isDirectory { oldDirIDByPath[fullPath] = idx }
        }

        struct QueueItem { let path: String; let parentNewID: Int32; let oldDirID: Int? }
        var newNodes: [IndexedNode] = []
        newNodes.reserveCapacity(min(maxNodes, max(nodes.count, 1024)))
        var queues: [[QueueItem]] = rootPaths.map { [QueueItem(path: $0, parentNewID: -1, oldDirID: nil)] }
        var heads = Array(repeating: 0, count: rootPaths.count)
        var reachedLimit = false
        var active = true

        while active && !reachedLimit {
            active = false
            for rootIdx in 0..<rootPaths.count {
                guard heads[rootIdx] < queues[rootIdx].count else { continue }
                active = true
                let item = queues[rootIdx][heads[rootIdx]]
                heads[rootIdx] += 1
                let isRoot = item.parentNewID == -1
                let shouldScan = changedSet.contains(item.path) || (!isRoot && item.oldDirID == nil)

                if shouldScan {
                    for child in scanSingleDirectory(at: item.path) {
                        if newNodes.count >= maxNodes { reachedLimit = true; break }
                        let newID = Int32(newNodes.count)
                        newNodes.append(IndexedNode(
                            parentID: item.parentNewID,
                            rootIndex: UInt16(rootIdx),
                            isDirectory: child.isDirectory,
                            name: child.name
                        ))
                        if child.isDirectory {
                            let childPath = item.path == "/" ? "/\(child.name)" : "\(item.path)/\(child.name)"
                            let matchingOld = changedSet.contains(item.path) ? oldDirIDByPath[childPath] : nil
                            queues[rootIdx].append(QueueItem(path: childPath, parentNewID: newID, oldDirID: matchingOld))
                        }
                    }
                } else {
                    let existing = isRoot ? oldRootChildren[rootIdx] : (item.oldDirID.map { oldChildren[$0] } ?? [])
                    for oldIdx in existing {
                        if newNodes.count >= maxNodes { reachedLimit = true; break }
                        let old = nodes[oldIdx]
                        let newID = Int32(newNodes.count)
                        newNodes.append(IndexedNode(
                            parentID: item.parentNewID,
                            rootIndex: UInt16(rootIdx),
                            isDirectory: old.isDirectory,
                            name: old.name
                        ))
                        if old.isDirectory {
                            queues[rootIdx].append(QueueItem(path: oldPaths[oldIdx], parentNewID: newID, oldDirID: oldIdx))
                        }
                    }
                }
                if reachedLimit { break }
            }
        }
        return EverythingIndex(rootURLs: rootURLs, nodes: newNodes, builtAt: Date(), reachedNodeLimit: reachedLimit)
    }

    private func scanSingleDirectory(at path: String) -> [(name: String, isDirectory: Bool)] {
        guard let dir = path.withCString({ opendir($0) }) else { return [] }
        defer { closedir(dir) }
        var result: [(name: String, isDirectory: Bool)] = []
        while let entry = readdir(dir) {
            let len = Int(entry.pointee.d_namlen) + 1
            let name: String = withUnsafePointer(to: entry.pointee.d_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: len) { String(cString: $0) }
            }
            if name == "." || name == ".." || name.hasPrefix(".") { continue }
            let childPath = path == "/" ? "/\(name)" : "\(path)/\(name)"
            let rawIsDir: Bool
            switch Int32(entry.pointee.d_type) {
            case DT_DIR: rawIsDir = true
            case DT_UNKNOWN:
                var st = stat()
                rawIsDir = childPath.withCString { lstat($0, &st) == 0 } && ((st.st_mode & S_IFMT) == S_IFDIR)
            default: rawIsDir = false
            }
            let isPackage = rawIsDir && EverythingIndex.hasPackageSuffix(name)
            let isDirectory = rawIsDir && !isPackage
            if isDirectory && Self.fsSkippedFolders.contains(name) { continue }
            result.append((name, isDirectory))
        }
        return result
    }
}
