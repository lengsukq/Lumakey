import Foundation
import LumakeyCore

func testV070Wave2Integration() throws {
    let appA = InstalledAppItem(name: "Safari", englishName: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))
    let appB = InstalledAppItem(name: "Slack", englishName: "Slack", url: URL(fileURLWithPath: "/Applications/Slack.app"))
    let boosts: [String: Int] = [appA.id: 120, appB.id: 660]
    let rankedApps = LauncherEngine.rankCandidates(
        query: "s",
        filter: .all,
        apps: [appA, appB],
        plugins: [],
        usageBoosts: boosts
    )
    if case .app(let topApp) = rankedApps.first?.kind {
        check(topApp.id == appB.id, "Wave 2 LauncherEngine ranks pinned/high-usage app first")
    } else {
        check(false, "Wave 2 expected top candidate to be .app")
    }

    let tmpPlugDir = try makeTempDir("v070-w2-plug")
    defer { try? FileManager.default.removeItem(at: tmpPlugDir) }
    let enabledDesc = try PluginSystem.scaffoldPlugin(id: "w2-on", name: "W2 Enabled", keywords: ["w2plug"], description: "enabled", in: tmpPlugDir)
    _ = try PluginSystem.scaffoldPlugin(id: "w2-off", name: "W2 Disabled", keywords: ["w2plug"], description: "disabled", in: tmpPlugDir)
    try PluginSystem.setPluginEnabled(id: "w2-off", isEnabled: false, in: tmpPlugDir)
    let allPlugs = PluginSystem.listPlugins(in: tmpPlugDir, includeDisabled: true)
    let plugHits = LauncherEngine.rankCandidates(query: "w2plug", filter: .all, apps: [], plugins: allPlugs)
    check(plugHits.count == 1 && plugHits.first?.id == "plugin:\(enabledDesc.id)", "Wave 2 LauncherEngine filters out disabled plugins")

    let devHits = LauncherEngine.rankCandidates(query: "uuid", filter: .all, apps: [], plugins: [])
    check(devHits.contains(where: { if case .devTool = $0.kind { return true }; return false }), "Wave 2 LauncherEngine surfaces .devTool candidates")

    let snipHits = LauncherEngine.rankCandidates(query: ";clip", filter: .all, apps: [], plugins: [], clipboardText: "LET_X")
    let hasExpandedClip = snipHits.contains {
        if case .snippet(let m) = $0.kind { return m.expandedText.contains("LET_X") }
        return false
    }
    check(hasExpandedClip, "Wave 2 LauncherEngine surfaces .snippet candidates with expanded clipboard")

    check(UnitAndCommandEngine.matchCommands(query: "gif", volumes: []).contains(where: { $0.command == .recordGif }), "gif command wired")
    check(UnitAndCommandEngine.matchCommands(query: "录屏", volumes: []).contains(where: { $0.command == .recordGif }), "录屏 command wired")
    check(UnitAndCommandEngine.matchCommands(query: "备份", volumes: []).contains(where: { $0.command == .openBackupSettings }), "备份 command wired")
    check(UnitAndCommandEngine.matchCommands(query: "webdav", volumes: []).contains(where: { $0.command == .openBackupSettings }), "webdav command wired")
    check(UnitAndCommandEngine.matchCommands(query: "短语", volumes: []).contains(where: { $0.command == .openSnippetsSettings }), "短语 command wired")
    check(UnitAndCommandEngine.matchCommands(query: "snippets", volumes: []).contains(where: { $0.command == .openSnippetsSettings }), "snippets command wired")
    print("[ok] v0.7.0 Wave 2 Full-Stack Launcher + Commands + UsageBoost + DisabledPlugin Integration")
}
