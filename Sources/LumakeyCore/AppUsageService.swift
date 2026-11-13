import Foundation

public struct AppUsageRecord: Codable, Sendable, Equatable {
    public var appID: String
    public var activationCount: Int
    public var lumakeyLaunchCount: Int
    public var foregroundSeconds: Double
    public var lastActiveAt: Date?
    public var systemUseCount: Int
    public var systemLastUsedAt: Date?
    public var isInSystemDock: Bool

    public init(
        appID: String,
        activationCount: Int = 0,
        lumakeyLaunchCount: Int = 0,
        foregroundSeconds: Double = 0,
        lastActiveAt: Date? = nil,
        systemUseCount: Int = 0,
        systemLastUsedAt: Date? = nil,
        isInSystemDock: Bool = false
    ) {
        self.appID = appID
        self.activationCount = activationCount
        self.lumakeyLaunchCount = lumakeyLaunchCount
        self.foregroundSeconds = foregroundSeconds
        self.lastActiveAt = lastActiveAt
        self.systemUseCount = systemUseCount
        self.systemLastUsedAt = systemLastUsedAt
        self.isInSystemDock = isInSystemDock
    }
}

public struct AppUsageState: Codable, Sendable, Equatable {
    public var version: Int
    public var pinnedAppIDs: [String]
    public var records: [String: AppUsageRecord]
    public var lastSystemProbeAt: Date?

    public init(
        version: Int = 1,
        pinnedAppIDs: [String] = [],
        records: [String: AppUsageRecord] = [:],
        lastSystemProbeAt: Date? = nil
    ) {
        self.version = version
        self.pinnedAppIDs = pinnedAppIDs
        self.records = records
        self.lastSystemProbeAt = lastSystemProbeAt
    }
}

public final class AppUsageService: @unchecked Sendable {
    public static let shared = AppUsageService()
    public static let maxSessionSeconds: Double = 4 * 3600

    let lock = NSLock()
    let ioLock = NSLock()
    let storageURL: URL
    let debounceNanoseconds: UInt64
    var state: AppUsageState
    var aliasToCanonicalID: [String: String] = [:]
    var runningAppIDs: Set<String> = []
    var pendingSaveTask: Task<Void, Never>?
    var isDirty = false

    public static func defaultStorageURL() -> URL {
        AppCacheService.defaultAppSupportRoot().appendingPathComponent("app-usage.json")
    }

    public init(
        storageURL: URL = AppUsageService.defaultStorageURL(),
        debounceNanoseconds: UInt64 = 1_200_000_000
    ) {
        self.storageURL = storageURL
        self.debounceNanoseconds = debounceNanoseconds
        self.state = Self.loadState(from: storageURL)
    }

    public var pinnedAppIDs: [String] { lock.withLock { state.pinnedAppIDs } }
    public func isPinned(_ appID: String) -> Bool { lock.withLock { state.pinnedAppIDs.contains(canonicalizeLocked(appID)) } }
    public func record(for appID: String) -> AppUsageRecord? { lock.withLock { state.records[canonicalizeLocked(appID)] } }

    public func canonicalAppID(for url: URL) -> String {
        lock.withLock { canonicalizeLocked(url.standardizedFileURL.path) }
    }

    public func registerKnownApps(_ apps: [InstalledAppItem]) {
        let map = AppSystemUsageProbe.canonicalAliasMap(for: apps.map(\.url))
        lock.withLock {
            aliasToCanonicalID.merge(map) { _, new in new }
            if migrateAliasesLocked() { scheduleSaveLocked() }
        }
    }

    @discardableResult
    public func togglePin(appID: String) -> Bool {
        lock.withLock {
            let id = canonicalizeLocked(appID)
            if let idx = state.pinnedAppIDs.firstIndex(of: id) {
                state.pinnedAppIDs.remove(at: idx)
                scheduleSaveLocked()
                return false
            }
            state.pinnedAppIDs.append(id)
            scheduleSaveLocked()
            return true
        }
    }

    public func setPinned(_ pinned: Bool, appID: String) {
        lock.withLock {
            let id = canonicalizeLocked(appID)
            if pinned {
                guard !state.pinnedAppIDs.contains(id) else { return }
                state.pinnedAppIDs.append(id)
            } else {
                guard let idx = state.pinnedAppIDs.firstIndex(of: id) else { return }
                state.pinnedAppIDs.remove(at: idx)
            }
            scheduleSaveLocked()
        }
    }

    public func movePinned(appID: String, offset: Int) {
        guard offset != 0 else { return }
        lock.withLock {
            let id = canonicalizeLocked(appID)
            guard let idx = state.pinnedAppIDs.firstIndex(of: id) else { return }
            let target = min(max(0, idx + offset), state.pinnedAppIDs.count - 1)
            guard target != idx else { return }
            state.pinnedAppIDs.remove(at: idx)
            state.pinnedAppIDs.insert(id, at: target)
            scheduleSaveLocked()
        }
    }

    public func canMovePinned(appID: String, offset: Int) -> Bool {
        guard offset != 0 else { return false }
        return lock.withLock {
            let id = canonicalizeLocked(appID)
            guard let idx = state.pinnedAppIDs.firstIndex(of: id) else { return false }
            let target = idx + offset
            return target >= 0 && target < state.pinnedAppIDs.count
        }
    }

    public func recordActivation(appID: String, at date: Date = Date()) {
        mutateRecord(appID: appID) { rec in
            rec.activationCount += 1
            rec.lastActiveAt = Self.maxDate(rec.lastActiveAt, date)
        }
    }

    public func recordLumakeyLaunch(appID: String, at date: Date = Date()) {
        mutateRecord(appID: appID) { rec in
            rec.lumakeyLaunchCount += 1
            rec.lastActiveAt = Self.maxDate(rec.lastActiveAt, date)
        }
    }

    public func recordForegroundDuration(appID: String, seconds: Double, at date: Date = Date()) {
        guard seconds.isFinite, seconds > 0 else { return }
        let clamped = min(seconds, Self.maxSessionSeconds)
        mutateRecord(appID: appID) { rec in
            rec.foregroundSeconds += clamped
            rec.lastActiveAt = Self.maxDate(rec.lastActiveAt, date)
        }
    }

    public func setAppRunning(_ running: Bool, appID: String, at date: Date = Date()) {
        lock.withLock {
            let id = canonicalizeLocked(appID)
            if running {
                runningAppIDs.insert(id)
                var rec = state.records[id] ?? AppUsageRecord(appID: id)
                rec.lastActiveAt = Self.maxDate(rec.lastActiveAt, date)
                state.records[id] = rec
                scheduleSaveLocked()
            } else {
                runningAppIDs.remove(id)
            }
        }
    }

    public func mergeSystemProbe(_ snapshot: AppSystemUsageSnapshot) {
        lock.withLock {
            aliasToCanonicalID.merge(snapshot.aliasToCanonicalID) { _, new in new }
            _ = migrateAliasesLocked()
            runningAppIDs = Set(snapshot.runningAppIDs.map { canonicalizeLocked($0) })
            for key in state.records.keys { state.records[key]?.isInSystemDock = false }
            for dockID in snapshot.dockAppIDs {
                let id = canonicalizeLocked(dockID)
                var rec = state.records[id] ?? AppUsageRecord(appID: id)
                rec.isInSystemDock = true
                state.records[id] = rec
            }
            for (rawID, meta) in snapshot.recordsByAppID {
                let id = canonicalizeLocked(rawID)
                var rec = state.records[id] ?? AppUsageRecord(appID: id)
                rec.systemUseCount = max(rec.systemUseCount, meta.useCount)
                rec.systemLastUsedAt = Self.maxDate(rec.systemLastUsedAt, meta.lastUsedDate)
                if meta.isInDock { rec.isInSystemDock = true }
                state.records[id] = rec
            }
            state.lastSystemProbeAt = Date()
            scheduleSaveLocked()
        }
    }

    public func resetStats(for appID: String?) {
        lock.withLock {
            if let appID {
                state.records.removeValue(forKey: canonicalizeLocked(appID))
            } else {
                state.records.removeAll()
            }
            scheduleSaveLocked()
        }
    }

    public func flush() {
        ioLock.withLock {
            let snapshot: AppUsageState? = lock.withLock {
                pendingSaveTask?.cancel()
                pendingSaveTask = nil
                guard isDirty else { return nil }
                isDirty = false
                return state
            }
            if let snapshot { Self.writeState(snapshot, to: storageURL) }
        }
    }
}
