import Darwin
import Foundation

public extension EverythingIndex {
    private struct RankedCandidate {
        let nodeID: Int
        let rank: Int
        let nameLength: Int
    }

    func search(queryText: String, limit: Int = 300) -> [EverythingSearchHit] {
        guard limit > 0, !nodes.isEmpty else { return [] }
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        var relParentCache: [Int32: String] = [:]

        func cachedRelativeParent(_ parentID: Int32) -> String {
            guard parentID >= 0 else { return "" }
            if let existing = relParentCache[parentID] { return existing }
            let resolved = relativeParent(forParentID: parentID)
            relParentCache[parentID] = resolved
            return resolved
        }

        if trimmed.isEmpty {
            return makeInitialHits(limit: limit, homePath: homePath, relParentResolver: cachedRelativeParent)
        }

        let query = EverythingQuery.parse(trimmed)
        if query.isEmpty {
            return makeInitialHits(limit: limit, homePath: homePath, relParentResolver: cachedRelativeParent)
        }

        if let rankNeedle = query.primaryPositiveTextNeedle {
            var candidates: [RankedCandidate] = []
            candidates.reserveCapacity(min(limit * 4, 256))
            var substringCount = 0
            let highRankCap = max(limit * 4, 256)

            for (idx, node) in nodes.enumerated() {
                let matched = query.matches(
                    name: node.name,
                    isDirectory: node.isDirectory,
                    parentPathProvider: {
                        displayParent(for: node, relParent: cachedRelativeParent(node.parentID), homePath: homePath)
                    }
                )
                if !matched { continue }
                let rank = max(1, rankNeedle.matchRank(in: node.name))
                if rank == 1 {
                    guard substringCount < limit else { continue }
                    substringCount += 1
                }
                candidates.append(RankedCandidate(nodeID: idx, rank: rank, nameLength: node.name.utf8.count))
                if candidates.count >= limit + highRankCap { break }
            }

            if candidates.count > 1 {
                candidates.sort { lhs, rhs in
                    if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
                    if lhs.nameLength != rhs.nameLength { return lhs.nameLength < rhs.nameLength }
                    return lhs.nodeID < rhs.nodeID
                }
            }

            var hits: [EverythingSearchHit] = []
            hits.reserveCapacity(min(limit, candidates.count))
            for item in candidates.prefix(limit) {
                let node = nodes[item.nodeID]
                let relParent = cachedRelativeParent(node.parentID)
                hits.append(makeHit(nodeID: item.nodeID, for: node, relParent: relParent, homePath: homePath))
            }
            return hits
        }

        var hits: [EverythingSearchHit] = []
        hits.reserveCapacity(min(limit, 128))
        for (idx, node) in nodes.enumerated() {
            let matched = query.matches(
                name: node.name,
                isDirectory: node.isDirectory,
                parentPathProvider: {
                    displayParent(for: node, relParent: cachedRelativeParent(node.parentID), homePath: homePath)
                }
            )
            if !matched { continue }
            let relParent = cachedRelativeParent(node.parentID)
            hits.append(makeHit(nodeID: idx, for: node, relParent: relParent, homePath: homePath))
            if hits.count >= limit { break }
        }
        return hits
    }

    func relativeParent(forParentID parentID: Int32) -> String {
        guard parentID >= 0, Int(parentID) < nodes.count else { return "" }
        let firstNode = nodes[Int(parentID)]
        if firstNode.parentID < 0 { return firstNode.name }

        var totalBytes = 0
        var count = 0
        var cursor = Int(parentID)
        while cursor >= 0 && cursor < nodes.count {
            totalBytes += nodes[cursor].name.utf8.count
            count += 1
            cursor = Int(nodes[cursor].parentID)
        }
        guard count > 0 else { return "" }
        totalBytes += (count - 1)

        return String(unsafeUninitializedCapacity: totalBytes) { buffer in
            var writeEnd = totalBytes
            var walk = Int(parentID)
            while walk >= 0 && walk < nodes.count {
                var seg = nodes[walk].name
                seg.withUTF8 { utf8 in
                    writeEnd -= utf8.count
                    if utf8.count > 0, let src = utf8.baseAddress, let dst = buffer.baseAddress?.advanced(by: writeEnd) {
                        dst.initialize(from: src, count: utf8.count)
                    }
                }
                walk = Int(nodes[walk].parentID)
                if walk >= 0 && walk < nodes.count && writeEnd > 0 {
                    writeEnd -= 1
                    buffer[writeEnd] = 0x2F
                }
            }
            return totalBytes
        }
    }

    private func makeInitialHits(
        limit: Int,
        homePath: String,
        relParentResolver: (Int32) -> String
    ) -> [EverythingSearchHit] {
        var hits: [EverythingSearchHit] = []
        hits.reserveCapacity(min(limit, nodes.count))
        for (idx, node) in nodes.prefix(limit).enumerated() {
            let relParent = relParentResolver(node.parentID)
            hits.append(makeHit(nodeID: idx, for: node, relParent: relParent, homePath: homePath))
        }
        return hits
    }

    private func makeHit(
        nodeID: Int,
        for node: IndexedNode,
        relParent: String,
        homePath: String
    ) -> EverythingSearchHit {
        let url = resolveURL(for: node, relativeParent: relParent)
        let stats = lazyStatIfNeeded(url: url, isDirectory: node.isDirectory)
        let extLower = Self.extractExtensionLower(fromName: node.name)
        return EverythingSearchHit(
            id: nodeID,
            url: url,
            relativeParentPath: displayParent(for: node, relParent: relParent, homePath: homePath),
            name: node.name,
            isDirectory: node.isDirectory,
            sizeBytes: stats.sizeBytes,
            modifiedAt: stats.modifiedAt,
            mediaKind: MediaClassifier.classifyExtension(extLower, isDirectory: node.isDirectory)
        )
    }

    private func displayParent(for node: IndexedNode, relParent: String, homePath: String) -> String {
        let idx = Int(node.rootIndex)
        let rootPath = rootPaths[idx]
        let rootLabel = rootPath == homePath ? "~" : rootURLs[idx].lastPathComponent
        if relParent.isEmpty { return rootLabel }
        return rootURLs.count > 1 ? "\(rootLabel)/\(relParent)" : relParent
    }

    private func lazyStatIfNeeded(url: URL, isDirectory: Bool) -> (sizeBytes: Int64, modifiedAt: Date) {
        var st = stat()
        guard url.path.withCString({ stat($0, &st) == 0 }) else { return (0, .distantPast) }
        let mod = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
        return (isDirectory ? 0 : Int64(st.st_size), mod)
    }

    private func resolveURL(for node: IndexedNode, relativeParent: String) -> URL {
        let base = rootPaths[Int(node.rootIndex)]
        let path: String
        if relativeParent.isEmpty {
            path = base == "/" ? "/\(node.name)" : "\(base)/\(node.name)"
        } else {
            path = base == "/" ? "/\(relativeParent)/\(node.name)" : "\(base)/\(relativeParent)/\(node.name)"
        }
        return URL(fileURLWithPath: path, isDirectory: node.isDirectory)
    }
}
