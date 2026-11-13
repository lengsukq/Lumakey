import Foundation
import LumakeyCore

func testV070AppUsageAndPinning() throws {
    let tmp = try makeTempDir("appusage")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let storeURL = tmp.appendingPathComponent("nested/app-usage.json")

    let appA = InstalledAppItem(name: "Alpha", englishName: "Alpha", url: URL(fileURLWithPath: "/Applications/Alpha.app"))
    let appB = InstalledAppItem(name: "Beta", englishName: "Beta", url: URL(fileURLWithPath: "/Applications/Beta.app"))
    let appC = InstalledAppItem(name: "Gamma", englishName: "Gamma", url: URL(fileURLWithPath: "/Applications/Gamma.app"))
    let appD = InstalledAppItem(name: "Delta", englishName: "Delta", url: URL(fileURLWithPath: "/Applications/Delta.app"))
    let allApps = [appA, appB, appC, appD]

    let dockRaw: [[String: Any]] = [
        ["tile-data": ["file-data": ["_CFURLString": "file:///Applications/Gamma.app/"]]],
        ["tile-data": ["file-data": ["_CFURLString": "file:///Applications/Delta%20Pro.app/"]]],
        ["tile-data": ["file-data": ["_CFURLString": "file:///Applications/Gamma.app/"]]]
    ]
    let parsedDock = AppSystemUsageProbe.parseDockPersistentAppPaths(from: dockRaw)
    check(parsedDock == ["/Applications/Gamma.app", "/Applications/Delta Pro.app"], "dock plist path normalization & dedup")

    let safeProbe = AppSystemUsageProbe.probe(appURLs: [
        tmp.appendingPathComponent("MissingApp.app"),
        URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    ])
    check(safeProbe.recordsByAppID[tmp.appendingPathComponent("MissingApp.app").standardizedFileURL.path]?.useCount == 0, "nil-safe probe for missing app")

    let now = Date()
    let service = AppUsageService(storageURL: storeURL, debounceNanoseconds: 50_000_000)

    let coldSnapshot = AppSystemUsageSnapshot(
        recordsByAppID: [
            appC.id: AppSystemMetadata(appID: appC.id, useCount: 85, lastUsedDate: now.addingTimeInterval(-1800), isInDock: true, isRunning: false),
            appA.id: AppSystemMetadata(appID: appA.id, useCount: 2, lastUsedDate: now.addingTimeInterval(-86_400 * 7), isInDock: false, isRunning: false)
        ],
        dockAppIDs: [appC.id],
        runningAppIDs: []
    )
    service.mergeSystemProbe(coldSnapshot)
    let coldRanked = service.rankApps(allApps, now: now)
    check(coldRanked.map(\.id) == [appC.id, appA.id, appB.id, appD.id], "cold start ranks Spotlight + Dock app first")

    service.recordActivation(appID: appA.id, at: now)
    service.recordForegroundDuration(appID: appA.id, seconds: 10, at: now)
    for _ in 0..<20 {
        service.recordActivation(appID: appB.id, at: now)
    }
    service.recordForegroundDuration(appID: appB.id, seconds: 3600, at: now)
    let activeRanked = service.rankApps(allApps, now: now)
    check(activeRanked.first?.id == appB.id, "3600s + 20 activations ranks B ahead of A and cold-start C")
    check(service.formattedUsageSummary(for: appB.id) == "1h · 20次", "formatted summary for B: \(service.formattedUsageSummary(for: appB.id))")

    service.recordForegroundDuration(appID: appD.id, seconds: 25_000, at: now)
    check(service.record(for: appD.id)?.foregroundSeconds == AppUsageService.maxSessionSeconds, "single session capped at 4h (14400s)")

    let pinnedA = service.togglePin(appID: appA.id)
    check(pinnedA && service.isPinned(appA.id), "togglePin pins appA")
    service.setPinned(true, appID: appD.id)
    check(service.rankApps(allApps, now: now).prefix(2).map(\.id) == [appA.id, appD.id], "pinned apps precede all unpinned apps in pin order")

    check(!service.canMovePinned(appID: appA.id, offset: -1), "cannot move first pinned app left")
    check(service.canMovePinned(appID: appD.id, offset: -1), "can move second pinned app left")
    service.movePinned(appID: appD.id, offset: -1)
    check(service.pinnedAppIDs == [appD.id, appA.id], "movePinned reorders pinned apps")
    check(service.formattedUsageSummary(for: appA.id).hasPrefix("已钉住 · "), "pinned summary prefix")

    let boosts = service.rankingBoosts(for: allApps, now: now)
    check((boosts[appD.id] ?? 0) > (boosts[appA.id] ?? 0), "first pinned app gets higher boost than second")
    check((boosts[appA.id] ?? 0) > (boosts[appB.id] ?? 0), "pinned app boost exceeds unpinned apps")
    check((boosts[appB.id] ?? 0) > (boosts[appC.id] ?? 0), "high-usage app boost exceeds cold-start app")

    let realTarget = tmp.appendingPathComponent("RealTarget.app", isDirectory: true)
    let aliasLink = tmp.appendingPathComponent("AliasTarget.app", isDirectory: true)
    try FileManager.default.createDirectory(at: realTarget, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: aliasLink, withDestinationURL: realTarget)
    let aliasItem = InstalledAppItem(name: "Alias", englishName: "Alias", url: aliasLink)
    service.recordForegroundDuration(appID: realTarget.resolvingSymlinksInPath().standardizedFileURL.path, seconds: 120, at: now)
    service.registerKnownApps([aliasItem])
    check((service.record(for: aliasItem.id)?.foregroundSeconds ?? 0) >= 120, "symlink alias merges into canonical InstalledAppItem.id")

    service.flush()
    check(FileManager.default.fileExists(atPath: storeURL.path), "app-usage.json persisted to disk")

    let reloaded = AppUsageService(storageURL: storeURL)
    check(reloaded.pinnedAppIDs == [appD.id, appA.id], "reloaded pinned order matches")
    check(reloaded.record(for: appB.id)?.activationCount == 20, "reloaded activation count matches")
    check(reloaded.record(for: appB.id)?.foregroundSeconds == 3600, "reloaded foreground seconds matches")
    check(reloaded.rankApps(allApps, now: now).map(\.id) == [appD.id, appA.id, appB.id, appC.id], "reloaded ranking matches")

    reloaded.resetStats(for: appB.id)
    check(reloaded.record(for: appB.id) == nil && reloaded.isPinned(appA.id), "resetStats clears target app record without dropping pins")

    print("[ok] v0.7.0 AppUsageService + AppSystemUsageProbe + Pinning + Persistence")
}
