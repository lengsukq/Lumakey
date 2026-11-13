import AppKit
import CoreServices
import Foundation

public struct AppSystemMetadata: Sendable, Equatable {
    public let appID: String
    public let useCount: Int
    public let lastUsedDate: Date?
    public let isInDock: Bool
    public let isRunning: Bool

    public init(
        appID: String,
        useCount: Int = 0,
        lastUsedDate: Date? = nil,
        isInDock: Bool = false,
        isRunning: Bool = false
    ) {
        self.appID = appID
        self.useCount = useCount
        self.lastUsedDate = lastUsedDate
        self.isInDock = isInDock
        self.isRunning = isRunning
    }
}

public struct AppSystemUsageSnapshot: Sendable, Equatable {
    public let recordsByAppID: [String: AppSystemMetadata]
    public let dockAppIDs: [String]
    public let runningAppIDs: Set<String>
    public let aliasToCanonicalID: [String: String]

    public init(
        recordsByAppID: [String: AppSystemMetadata] = [:],
        dockAppIDs: [String] = [],
        runningAppIDs: Set<String> = [],
        aliasToCanonicalID: [String: String] = [:]
    ) {
        self.recordsByAppID = recordsByAppID
        self.dockAppIDs = dockAppIDs
        self.runningAppIDs = runningAppIDs
        self.aliasToCanonicalID = aliasToCanonicalID
    }
}

public enum AppSystemUsageProbe {
    public static func canonicalAliasMap(for appURLs: [URL]) -> [String: String] {
        var map: [String: String] = [:]
        map.reserveCapacity(appURLs.count * 2)
        for url in appURLs {
            let canonical = url.standardizedFileURL.path
            if map[canonical] == nil {
                map[canonical] = canonical
            }
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
            if map[resolved] == nil {
                map[resolved] = canonical
            }
        }
        return map
    }

    public static func canonicalizePath(_ rawPath: String, aliasMap: [String: String]) -> String {
        let std = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        if let mapped = aliasMap[std] {
            return mapped
        }
        let resolved = URL(fileURLWithPath: std).resolvingSymlinksInPath().standardizedFileURL.path
        return aliasMap[resolved] ?? std
    }

    public static func readSpotlightMetadata(for appURL: URL) -> (useCount: Int, lastUsedDate: Date?) {
        let primary = readSingleSpotlightItem(at: appURL)
        if primary.useCount > 0 || primary.lastUsedDate != nil {
            return primary
        }
        let resolved = appURL.resolvingSymlinksInPath()
        if resolved.standardizedFileURL.path != appURL.standardizedFileURL.path {
            return readSingleSpotlightItem(at: resolved)
        }
        return primary
    }

    private static func readSingleSpotlightItem(at url: URL) -> (useCount: Int, lastUsedDate: Date?) {
        guard FileManager.default.fileExists(atPath: url.path),
              let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else {
            return (0, nil)
        }
        let rawCount = MDItemCopyAttribute(item, "kMDItemUseCount" as CFString) as? NSNumber
        let count = max(0, rawCount?.intValue ?? 0)
        let lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        return (count, lastUsed)
    }

    public static func parseDockPersistentAppPaths(from persistentApps: [Any]?) -> [String] {
        guard let persistentApps else { return [] }
        var seen = Set<String>()
        var paths: [String] = []
        for entry in persistentApps {
            guard let dict = entry as? [String: Any],
                  let tileData = dict["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let rawURLString = fileData["_CFURLString"] as? String,
                  let normalized = normalizeDockURLString(rawURLString) else {
                continue
            }
            if seen.insert(normalized).inserted {
                paths.append(normalized)
            }
        }
        return paths
    }

    public static func readDockPersistentAppPaths(
        userDefaults: UserDefaults? = UserDefaults(suiteName: "com.apple.dock")
    ) -> [String] {
        parseDockPersistentAppPaths(from: userDefaults?.array(forKey: "persistent-apps"))
    }

    public static func readRunningRegularAppPaths() -> Set<String> {
        var paths = Set<String>()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleURL = app.bundleURL else { continue }
            paths.insert(bundleURL.standardizedFileURL.path)
        }
        return paths
    }

    public static func probe(appURLs: [URL]) -> AppSystemUsageSnapshot {
        let aliasMap = canonicalAliasMap(for: appURLs)
        let dockIDs = readDockPersistentAppPaths().map { canonicalizePath($0, aliasMap: aliasMap) }
        let dockSet = Set(dockIDs)
        let runningIDs = Set(readRunningRegularAppPaths().map { canonicalizePath($0, aliasMap: aliasMap) })

        var records: [String: AppSystemMetadata] = [:]
        records.reserveCapacity(appURLs.count)

        for url in appURLs {
            let appID = canonicalizePath(url.path, aliasMap: aliasMap)
            if records[appID] != nil { continue }
            let meta = readSpotlightMetadata(for: url)
            records[appID] = AppSystemMetadata(
                appID: appID,
                useCount: meta.useCount,
                lastUsedDate: meta.lastUsedDate,
                isInDock: dockSet.contains(appID),
                isRunning: runningIDs.contains(appID)
            )
        }

        for extraID in dockSet.union(runningIDs) where records[extraID] == nil {
            let meta = readSpotlightMetadata(for: URL(fileURLWithPath: extraID))
            records[extraID] = AppSystemMetadata(
                appID: extraID,
                useCount: meta.useCount,
                lastUsedDate: meta.lastUsedDate,
                isInDock: dockSet.contains(extraID),
                isRunning: runningIDs.contains(extraID)
            )
        }

        return AppSystemUsageSnapshot(
            recordsByAppID: records,
            dockAppIDs: dockIDs,
            runningAppIDs: runningIDs,
            aliasToCanonicalID: aliasMap
        )
    }

    public static func probeAsync(appURLs: [URL]) async -> AppSystemUsageSnapshot {
        await Task.detached(priority: .utility) {
            probe(appURLs: appURLs)
        }.value
    }

    private static func normalizeDockURLString(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed) {
            return url.standardizedFileURL.path
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL.path
        }
        return nil
    }
}
