import Foundation

public struct CachedDirectorySnapshot: Sendable {
    public let entries: [FileEntry]
    public let volumeSummary: VolumeSummary?
    public let includeHidden: Bool
    public let directoryMTime: Date?
    public let cachedAt: Date
}

public final class WorkspaceDirectoryCache: @unchecked Sendable {
    private let lock = NSLock()
    private let maxEntries: Int
    private var storage: [String: CachedDirectorySnapshot] = [:]
    private var lruOrder: [String] = []

    public init(maxEntries: Int = 48) {
        self.maxEntries = max(1, maxEntries)
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    public func lookup(for directoryURL: URL, includeHidden: Bool) -> CachedDirectorySnapshot? {
        let key = directoryURL.standardizedFileURL.path
        lock.lock()
        defer { lock.unlock() }
        guard let item = storage[key], item.includeHidden == includeHidden else { return nil }
        touchLocked(key)
        return item
    }

    public func needsBackgroundRevalidation(
        for directoryURL: URL,
        cached: CachedDirectorySnapshot,
        maxFreshAge: TimeInterval = 5
    ) -> Bool {
        if Date().timeIntervalSince(cached.cachedAt) > maxFreshAge { return true }
        if let currentMTime = DirectoryScanner.directoryModificationDate(at: directoryURL),
           cached.directoryMTime != currentMTime {
            return true
        }
        return false
    }

    public func store(
        entries: [FileEntry],
        volumeSummary: VolumeSummary?,
        for directoryURL: URL,
        includeHidden: Bool,
        directoryMTime: Date?
    ) {
        let key = directoryURL.standardizedFileURL.path
        let snapshot = CachedDirectorySnapshot(
            entries: entries,
            volumeSummary: volumeSummary,
            includeHidden: includeHidden,
            directoryMTime: directoryMTime,
            cachedAt: Date()
        )
        lock.lock()
        defer { lock.unlock() }
        storage[key] = snapshot
        touchLocked(key)
        while lruOrder.count > maxEntries {
            let evicted = lruOrder.removeFirst()
            storage.removeValue(forKey: evicted)
        }
    }

    public func invalidate(directoryURL: URL) {
        let key = directoryURL.standardizedFileURL.path
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
        lruOrder.removeAll { $0 == key }
    }

    public func trimKeepingRecent(_ maxKeep: Int) {
        lock.lock()
        defer { lock.unlock() }
        let keep = max(0, maxKeep)
        while lruOrder.count > keep {
            let evicted = lruOrder.removeFirst()
            storage.removeValue(forKey: evicted)
        }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
        lruOrder.removeAll()
    }

    private func touchLocked(_ key: String) {
        lruOrder.removeAll { $0 == key }
        lruOrder.append(key)
    }
}
