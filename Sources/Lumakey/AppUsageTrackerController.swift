import AppKit
import Foundation
import LumakeyCore
import SwiftUI

@MainActor
final class AppUsageTrackerController: ObservableObject {
    static let shared = AppUsageTrackerController()

    @Published private(set) var revision: Int = 0

    private let service: AppUsageService
    private let ownBundlePath: String?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []
    private var probeTask: Task<Void, Never>?
    private var activeAppID: String?
    private var activeSessionStartedAt: Date?
    private var isSystemSleeping = false
    private var hasProbedInstalledApps = false
    private var lastSyncedAppIDs: [String] = []

    init(service: AppUsageService = .shared, startMonitoring: Bool = true) {
        self.service = service
        self.ownBundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        if startMonitoring {
            installObservers()
            seedInitialFrontmostApp()
            runColdStartProbe(appURLs: [])
        }
    }

    var pinnedCount: Int { service.pinnedAppIDs.count }

    func ensureSystemProbe(for apps: [InstalledAppItem]) {
        guard !apps.isEmpty else { return }
        let ids = apps.map(\.id)
        if ids != lastSyncedAppIDs {
            lastSyncedAppIDs = ids
            service.registerKnownApps(apps)
            revision &+= 1
        }
        guard !hasProbedInstalledApps else { return }
        hasProbedInstalledApps = true
        runColdStartProbe(appURLs: apps.map(\.url))
    }

    func rankedDockApps(from apps: [InstalledAppItem], limit: Int = 8) -> [InstalledAppItem] {
        guard limit > 0 else { return [] }
        return Array(service.rankApps(apps).prefix(limit))
    }

    func rankingBoost(for appID: String) -> Int {
        service.rankingBoost(for: appID)
    }

    func rankingBoosts(for apps: [InstalledAppItem]) -> [String: Int] {
        service.rankingBoosts(for: apps)
    }

    func togglePin(_ app: InstalledAppItem) {
        service.togglePin(appID: app.id)
        revision &+= 1
    }

    func isPinned(_ app: InstalledAppItem) -> Bool {
        service.isPinned(app.id)
    }

    func movePin(_ app: InstalledAppItem, delta: Int) {
        service.movePinned(appID: app.id, offset: delta)
        revision &+= 1
    }

    func canMovePin(_ app: InstalledAppItem, delta: Int) -> Bool {
        service.canMovePinned(appID: app.id, offset: delta)
    }

    func recordLumakeyLaunch(_ app: InstalledAppItem) {
        service.recordLumakeyLaunch(appID: app.id)
        revision &+= 1
    }

    func resetStats(for appID: String?) {
        service.resetStats(for: appID)
        revision &+= 1
    }

    func usageSummary(for app: InstalledAppItem) -> String {
        service.formattedUsageSummary(for: app.id)
    }

    func compactUsageBadge(for app: InstalledAppItem) -> String? {
        service.compactBadgeSummary(for: app.id)
    }

    func flushNow() {
        settleActiveSession(at: Date())
        service.flush()
    }

    func stopMonitoring() {
        probeTask?.cancel()
        probeTask = nil
        let wsCenter = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers { wsCenter.removeObserver(obs) }
        workspaceObservers.removeAll()
        for obs in appObservers { NotificationCenter.default.removeObserver(obs) }
        appObservers.removeAll()
    }

    private func installObservers() {
        workspaceObservers = [
            observeWorkspaceApp(NSWorkspace.didActivateApplicationNotification) { [weak self] url, isReg in
                self?.handleDidActivate(bundleURL: url, isRegular: isReg)
            },
            observeWorkspaceApp(NSWorkspace.didLaunchApplicationNotification) { [weak self] url, isReg in
                self?.handleDidLaunch(bundleURL: url, isRegular: isReg)
            },
            observeWorkspaceEvent(NSWorkspace.willSleepNotification) { [weak self] in
                self?.handleWillSleep()
            },
            observeWorkspaceEvent(NSWorkspace.didWakeNotification) { [weak self] in
                self?.handleDidWake()
            }
        ]

        let localService = service
        let termObs = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.flushNow()
                    self?.stopMonitoring()
                }
            } else {
                localService.flush()
            }
        }
        appObservers = [termObs]
    }

    private func observeWorkspaceApp(
        _ name: Notification.Name,
        handler: @escaping @MainActor (URL?, Bool) -> Void
    ) -> NSObjectProtocol {
        NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleURL = app?.bundleURL
            let isRegular = app?.activationPolicy == .regular
            MainActor.assumeIsolated { handler(bundleURL, isRegular) }
        }
    }

    private func observeWorkspaceEvent(
        _ name: Notification.Name,
        handler: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    private func runColdStartProbe(appURLs: [URL]) {
        probeTask?.cancel()
        let localService = service
        probeTask = Task { [weak self] in
            let snapshot = await AppSystemUsageProbe.probeAsync(appURLs: appURLs)
            guard !Task.isCancelled, let self else { return }
            localService.mergeSystemProbe(snapshot)
            self.revision &+= 1
        }
    }

    private func seedInitialFrontmostApp() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.activationPolicy == .regular,
              let bundleURL = front.bundleURL,
              !isOwnBundle(bundleURL) else { return }
        activeAppID = service.canonicalAppID(for: bundleURL)
        activeSessionStartedAt = Date()
    }

    private func handleDidActivate(bundleURL: URL?, isRegular: Bool) {
        let now = Date()
        guard !isSystemSleeping else { return }
        let settled = settleActiveSession(at: now)
        guard isRegular, let bundleURL, !isOwnBundle(bundleURL) else {
            activeAppID = nil
            activeSessionStartedAt = nil
            if settled { revision &+= 1 }
            return
        }
        let appID = service.canonicalAppID(for: bundleURL)
        activeAppID = appID
        activeSessionStartedAt = now
        service.recordActivation(appID: appID, at: now)
        revision &+= 1
    }

    private func handleDidLaunch(bundleURL: URL?, isRegular: Bool) {
        guard isRegular, let bundleURL, !isOwnBundle(bundleURL) else { return }
        let appID = service.canonicalAppID(for: bundleURL)
        service.setAppRunning(true, appID: appID, at: Date())
        revision &+= 1
    }

    private func handleWillSleep() {
        _ = settleActiveSession(at: Date())
        isSystemSleeping = true
        activeSessionStartedAt = nil
        service.flush()
        revision &+= 1
    }

    private func handleDidWake() {
        isSystemSleeping = false
        seedInitialFrontmostApp()
    }

    @discardableResult
    private func settleActiveSession(at now: Date) -> Bool {
        guard !isSystemSleeping, let prevID = activeAppID, let start = activeSessionStartedAt else {
            return false
        }
        let elapsed = now.timeIntervalSince(start)
        activeSessionStartedAt = now
        guard elapsed > 0 else { return false }
        service.recordForegroundDuration(appID: prevID, seconds: elapsed, at: now)
        return true
    }

    private func isOwnBundle(_ url: URL) -> Bool {
        guard let ownBundlePath else { return false }
        return url.standardizedFileURL.path == ownBundlePath
    }
}
