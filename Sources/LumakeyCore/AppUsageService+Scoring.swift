import Foundation

extension AppUsageService {
    public func rankApps(_ apps: [InstalledAppItem], now: Date = Date()) -> [InstalledAppItem] {
        lock.withLock {
            var byID: [String: InstalledAppItem] = [:]
            for app in apps { byID[app.id] = app }
            var pinned: [InstalledAppItem] = []
            var seen = Set<String>()
            for pid in state.pinnedAppIDs {
                let id = canonicalizeLocked(pid)
                if let app = byID[id], seen.insert(app.id).inserted { pinned.append(app) }
            }
            let unpinned = apps.filter { !seen.contains($0.id) }.sorted { lhs, rhs in
                let ls = scoreLocked(for: lhs.id, now: now)
                let rs = scoreLocked(for: rhs.id, now: now)
                if abs(ls - rs) > 0.0001 { return ls > rs }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return pinned + unpinned
        }
    }

    public func rankingBoost(for appID: String, now: Date = Date()) -> Int {
        lock.withLock { rankingBoostLocked(for: canonicalizeLocked(appID), now: now) }
    }

    public func rankingBoosts(for apps: [InstalledAppItem], now: Date = Date()) -> [String: Int] {
        lock.withLock {
            var out: [String: Int] = [:]
            out.reserveCapacity(apps.count)
            for app in apps {
                let boost = rankingBoostLocked(for: canonicalizeLocked(app.id), now: now)
                if boost > 0 { out[app.id] = boost }
            }
            return out
        }
    }

    public func formattedUsageSummary(for appID: String) -> String {
        let (pinned, rec, running) = lock.withLock { () -> (Bool, AppUsageRecord?, Bool) in
            let id = canonicalizeLocked(appID)
            return (state.pinnedAppIDs.contains(id), state.records[id], runningAppIDs.contains(id))
        }
        var parts: [String] = []
        if pinned { parts.append("已钉住") }
        if let dur = Self.formatDuration(rec?.foregroundSeconds ?? 0) { parts.append(dur) }
        if let cnt = Self.formatCount(rec) { parts.append(cnt) }
        if parts.isEmpty || parts == ["已钉住"] {
            if rec?.isInSystemDock == true { parts.append("Dock") }
            else if running { parts.append("运行中") }
        }
        return parts.isEmpty ? "暂无使用记录" : parts.joined(separator: " · ")
    }

    public func compactBadgeSummary(for appID: String) -> String? {
        let (rec, running) = lock.withLock { () -> (AppUsageRecord?, Bool) in
            let id = canonicalizeLocked(appID)
            return (state.records[id], runningAppIDs.contains(id))
        }
        if let dur = Self.formatDuration(rec?.foregroundSeconds ?? 0) { return dur }
        if let cnt = Self.formatCount(rec) { return cnt }
        if rec?.isInSystemDock == true { return "Dock" }
        return running ? "运行中" : nil
    }

    func mutateRecord(appID: String, _ transform: (inout AppUsageRecord) -> Void) {
        lock.withLock {
            let id = canonicalizeLocked(appID)
            var rec = state.records[id] ?? AppUsageRecord(appID: id)
            transform(&rec)
            state.records[id] = rec
            scheduleSaveLocked()
        }
    }

    func canonicalizeLocked(_ rawPath: String) -> String {
        let std = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        if let mapped = aliasToCanonicalID[std] {
            return mapped
        }
        let resolved = URL(fileURLWithPath: std).resolvingSymlinksInPath().standardizedFileURL.path
        return aliasToCanonicalID[resolved] ?? std
    }

    @discardableResult
    func migrateAliasesLocked() -> Bool {
        var changed = false
        let oldKeys = Array(state.records.keys)
        for key in oldKeys {
            let canonical = canonicalizeLocked(key)
            guard canonical != key, let old = state.records.removeValue(forKey: key) else { continue }
            var merged = state.records[canonical] ?? AppUsageRecord(appID: canonical)
            merged.activationCount += old.activationCount
            merged.lumakeyLaunchCount += old.lumakeyLaunchCount
            merged.foregroundSeconds += old.foregroundSeconds
            merged.lastActiveAt = Self.maxDate(merged.lastActiveAt, old.lastActiveAt)
            merged.systemUseCount = max(merged.systemUseCount, old.systemUseCount)
            merged.systemLastUsedAt = Self.maxDate(merged.systemLastUsedAt, old.systemLastUsedAt)
            merged.isInSystemDock = merged.isInSystemDock || old.isInSystemDock
            state.records[canonical] = merged
            changed = true
        }

        var remappedPins: [String] = []
        var seenPins = Set<String>()
        for pin in state.pinnedAppIDs {
            let canonical = canonicalizeLocked(pin)
            if canonical != pin { changed = true }
            if seenPins.insert(canonical).inserted {
                remappedPins.append(canonical)
            } else {
                changed = true
            }
        }
        state.pinnedAppIDs = remappedPins
        runningAppIDs = Set(runningAppIDs.map { canonicalizeLocked($0) })
        return changed
    }

    func scoreLocked(for canonicalID: String, now: Date) -> Double {
        let rec = state.records[canonicalID]
        let isRunning = runningAppIDs.contains(canonicalID)
        if rec == nil && !isRunning { return 0 }

        let lumakeyScore = log2(Double(max(0, rec?.lumakeyLaunchCount ?? 0)) + 1.0) * 28.0
        let activationScore = log2(Double(max(0, rec?.activationCount ?? 0)) + 1.0) * 18.0
        let minutes = max(0, rec?.foregroundSeconds ?? 0) / 60.0
        let durationScore = log2(minutes + 1.0) * 16.0
        let systemUseScore = log2(Double(max(0, rec?.systemUseCount ?? 0)) + 1.0) * 8.0
        let dockScore = (rec?.isInSystemDock == true) ? 18.0 : 0.0
        let runningScore = isRunning ? 12.0 : 0.0

        let latest = Self.maxDate(rec?.lastActiveAt, rec?.systemLastUsedAt)
        let recencyScore: Double
        if let latest {
            let hoursAgo = max(0, now.timeIntervalSince(latest) / 3600.0)
            recencyScore = 32.0 / (1.0 + hoursAgo / 24.0)
        } else {
            recencyScore = 0
        }
        return lumakeyScore + activationScore + durationScore + systemUseScore + dockScore + runningScore + recencyScore
    }

    func rankingBoostLocked(for canonicalID: String, now: Date) -> Int {
        if let pinIdx = state.pinnedAppIDs.firstIndex(of: canonicalID) {
            return 550 + max(0, 150 - pinIdx * 5)
        }
        let s = scoreLocked(for: canonicalID, now: now)
        return min(Int((s * 1.5).rounded()), 450)
    }

    func scheduleSaveLocked() {
        isDirty = true
        pendingSaveTask?.cancel()
        let delay = debounceNanoseconds
        pendingSaveTask = Task.detached(priority: .utility) { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled, let self else { return }
            self.flush()
        }
    }

    static func loadState(from url: URL) -> AppUsageState {
        guard let data = try? Data(contentsOf: url) else { return AppUsageState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(AppUsageState.self, from: data)) ?? AppUsageState()
    }

    static func writeState(_ state: AppUsageState, to url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(state) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func formatDuration(_ seconds: Double) -> String? {
        guard seconds >= 1 else { return nil }
        if seconds >= 3600 {
            let hours = seconds / 3600.0
            let formatted = String(format: "%.1f", hours)
            return formatted.hasSuffix(".0") ? "\(formatted.dropLast(2))h" : "\(formatted)h"
        }
        if seconds >= 60 {
            return "\(Int((seconds / 60.0).rounded()))m"
        }
        return "\(Int(seconds.rounded()))s"
    }

    static func formatCount(_ rec: AppUsageRecord?) -> String? {
        guard let rec else { return nil }
        let tracked = rec.lumakeyLaunchCount + rec.activationCount
        if tracked > 0 { return "\(tracked)次" }
        if rec.systemUseCount > 0 { return "系统 \(rec.systemUseCount)次" }
        return nil
    }

    static func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (let l?, let r?): max(l, r)
        case (let l?, nil): l
        case (nil, let r?): r
        case (nil, nil): nil
        }
    }
}
