import AppKit
import Foundation
import LumakeyCore
import UniformTypeIdentifiers

struct PendingBackupRestore: Equatable {
    let sourceLabel: String
    let data: Data
    let summary: BackupInspectionSummary
    var options: BackupRestoreOptions
}

enum BackupBannerTone: Equatable { case success, info, error }

struct BackupStatusBanner: Equatable {
    let tone: BackupBannerTone
    let message: String
}

@MainActor
enum BackupCoordinator {
    static func exportCurrentArchiveData(viewModel: AppViewModel) throws -> Data {
        try BackupArchiveService.exportBackupData(
            clipboardEntries: viewModel.clipboardItems,
            mosConfig: viewModel.mosConfig,
            telemetryConfig: SystemPulseWindowController.shared.state.config
        )
    }

    static func applyRestoreReport(_ report: BackupRestoreReport, to viewModel: AppViewModel) {
        viewModel.applyMosConfig(report.mosConfig)
        let pulse = SystemPulseWindowController.shared
        pulse.state.config = report.telemetryConfig
        pulse.state.config.save()
        pulse.setMenuBarEnabled(report.telemetryConfig.showInMenuBar)
        pulse.setFloatingEnabled(report.telemetryConfig.floatingEnabled)

        var merged = viewModel.clipboardItems
        for entry in report.restoredClipboardEntries.reversed() {
            merged = ClipboardService.insert(entry, into: merged)
        }
        viewModel.clipboardItems = merged
        viewModel.reloadAppsAndPlugins()
    }

    static func triggerQuickBackup(viewModel: AppViewModel) {
        let cfg = WebDAVConfig.load()
        if cfg.isConfigured, let pwd = try? WebDAVKeychainStore.loadPassword(account: cfg.username), !pwd.isEmpty {
            viewModel.serviceMessage = "正在后台上传 WebDAV 快照备份…"
            Task { @MainActor in
                do {
                    let archive = try exportCurrentArchiveData(viewModel: viewModel)
                    let client = WebDAVClient(config: cfg, password: pwd)
                    let item = try await Task.detached(priority: .utility) { try await client.uploadBackup(data: archive) }.value
                    viewModel.serviceMessage = "已上传云备份：\(item.fileName)"
                } catch {
                    viewModel.serviceMessage = "云备份失败：\(error.localizedDescription)"
                }
            }
        } else {
            BackupSettingsViewState().exportLocalBackupInteractive(viewModel: viewModel)
        }
    }

    static func triggerAutoBackupOnLaunchIfNeeded(viewModel: AppViewModel) {
        let cfg = WebDAVConfig.load()
        guard cfg.autoBackupOnLaunch, cfg.isConfigured,
              let pwd = try? WebDAVKeychainStore.loadPassword(account: cfg.username), !pwd.isEmpty else { return }
        Task { @MainActor in
            guard let archive = try? exportCurrentArchiveData(viewModel: viewModel) else { return }
            let client = WebDAVClient(config: cfg, password: pwd)
            _ = try? await Task.detached(priority: .background) { try await client.uploadBackup(data: archive) }.value
        }
    }
}

@MainActor
final class BackupSettingsViewState: ObservableObject {
    @Published var webdavConfig: WebDAVConfig = WebDAVConfig.load()
    @Published var passwordInput: String = ""
    @Published var selectedPresetID: String = "jianguoyun"
    @Published var remoteItems: [WebDAVRemoteItem] = []
    @Published var pendingRestore: PendingBackupRestore?
    @Published var isBusy: Bool = false
    @Published var busyLabel: String = ""
    @Published var banner: BackupStatusBanner?
    private var previousAccount: String = ""

    var activePreset: WebDAVProviderPreset {
        WebDAVProviderPreset.allPresets.first(where: { $0.id == selectedPresetID }) ?? WebDAVProviderPreset.allPresets[0]
    }

    func onAppearLoad() {
        let cfg = WebDAVConfig.load()
        webdavConfig = cfg
        previousAccount = cfg.username
        if let saved = try? WebDAVKeychainStore.loadPassword(account: cfg.username) {
            passwordInput = saved
        }
        if let matched = WebDAVProviderPreset.allPresets.first(where: {
            !cfg.serverURL.isEmpty && cfg.serverURL.lowercased().contains($0.id)
        }) {
            selectedPresetID = matched.id
        }
    }

    func selectPreset(_ preset: WebDAVProviderPreset) {
        selectedPresetID = preset.id
        let trimmed = webdavConfig.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || WebDAVProviderPreset.allPresets.contains(where: { $0.sampleURL == trimmed }) {
            webdavConfig.serverURL = preset.sampleURL
        }
    }

    @discardableResult
    func persistSettings() -> Bool {
        webdavConfig.save()
        do {
            if !previousAccount.isEmpty && previousAccount != webdavConfig.username {
                try? WebDAVKeychainStore.deletePassword(account: previousAccount)
            }
            try WebDAVKeychainStore.savePassword(passwordInput, account: webdavConfig.username)
            previousAccount = webdavConfig.username
            return true
        } catch {
            banner = BackupStatusBanner(tone: .error, message: error.localizedDescription)
            return false
        }
    }

    func exportLocalBackupInteractive(viewModel: AppViewModel) {
        let panel = NSSavePanel()
        panel.title = "导出 Lumakey 全量备份归档"
        panel.nameFieldStringValue = BackupArchiveService.defaultBackupFileName()
        panel.canCreateDirectories = true
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let targetURL = panel.url else { return }
        do {
            let data = try BackupCoordinator.exportCurrentArchiveData(viewModel: viewModel)
            try data.write(to: targetURL, options: .atomic)
            let s = try BackupArchiveService.inspectBackupData(data)
            let msg = "已导出 \(targetURL.lastPathComponent)（\(s.configCount) 项配置 · \(s.pinnedClipboardCount) 条收藏 · \(s.pluginCount) 个插件）"
            banner = BackupStatusBanner(tone: .success, message: msg)
            viewModel.serviceMessage = msg
        } catch {
            banner = BackupStatusBanner(tone: .error, message: error.localizedDescription)
        }
    }

    func chooseLocalBackupForRestore() {
        let panel = NSOpenPanel()
        panel.title = "选择 .lumakeybackup 备份归档文件"
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: BackupEnvelope.fileExtension, conformingTo: .data), .json, .data
        ].compactMap { $0 }
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        do {
            let data = try Data(contentsOf: sourceURL)
            let summary = try BackupArchiveService.inspectBackupData(data)
            pendingRestore = PendingBackupRestore(sourceLabel: sourceURL.lastPathComponent, data: data, summary: summary, options: .all)
            banner = BackupStatusBanner(tone: .info, message: "SHA-256 校验通过，请核对下方快照摘要后确认恢复")
        } catch {
            banner = BackupStatusBanner(tone: .error, message: error.localizedDescription)
        }
    }

    func confirmPendingRestore(viewModel: AppViewModel) {
        guard let pending = pendingRestore else { return }
        do {
            let r = try BackupArchiveService.restoreBackupData(pending.data, options: pending.options)
            BackupCoordinator.applyRestoreReport(r, to: viewModel)
            pendingRestore = nil
            let msg = "恢复完成：\(r.restoredConfigFileNames.count) 项配置、\(r.restoredClipboardEntries.count) 条收藏、\(r.restoredPluginIDs.count) 个插件已生效"
            banner = BackupStatusBanner(tone: .success, message: msg)
            viewModel.serviceMessage = msg
        } catch {
            banner = BackupStatusBanner(tone: .error, message: error.localizedDescription)
        }
    }

    func runWebDAVTest() {
        guard persistSettings() else { return }
        let client = WebDAVClient(config: webdavConfig, password: passwordInput)
        runAsyncTask(label: "正在验证 WebDAV 连通性…") {
            let status = try await client.testConnection()
            self.banner = BackupStatusBanner(tone: .success, message: status)
        }
    }

    func uploadBackupToWebDAV(viewModel: AppViewModel) {
        guard persistSettings() else { return }
        let archive: Data
        do { archive = try BackupCoordinator.exportCurrentArchiveData(viewModel: viewModel) }
        catch { banner = BackupStatusBanner(tone: .error, message: error.localizedDescription); return }
        let client = WebDAVClient(config: webdavConfig, password: passwordInput)
        runAsyncTask(label: "正在上传备份并执行快照轮转…") {
            let uploaded = try await client.uploadBackup(data: archive)
            self.remoteItems = (try? await client.listBackups()) ?? [uploaded]
            self.banner = BackupStatusBanner(tone: .success, message: "云备份成功：\(uploaded.fileName)（保留最近 \(self.webdavConfig.keepLatestCount) 份）")
        }
    }

    func refreshRemoteList() {
        guard persistSettings() else { return }
        let client = WebDAVClient(config: webdavConfig, password: passwordInput)
        runAsyncTask(label: "正在拉取云端备份列表…") {
            do {
                let items = try await client.listBackups()
                self.remoteItems = items
                self.banner = BackupStatusBanner(tone: .info, message: items.isEmpty ? "云端目录暂无 .lumakeybackup 快照" : "已同步 \(items.count) 份云端历史快照")
            } catch WebDAVError.notFound {
                self.remoteItems = []
                self.banner = BackupStatusBanner(tone: .info, message: "远端备份目录尚未建立，首次上传时将自动创建")
            }
        }
    }

    func downloadAndStageRemoteRestore(_ item: WebDAVRemoteItem) {
        let client = WebDAVClient(config: webdavConfig, password: passwordInput)
        runAsyncTask(label: "正在下载 \(item.fileName)…") {
            let data = try await client.downloadBackup(item: item)
            let summary = try BackupArchiveService.inspectBackupData(data)
            self.pendingRestore = PendingBackupRestore(sourceLabel: "云端 · \(item.fileName)", data: data, summary: summary, options: .all)
            self.banner = BackupStatusBanner(tone: .info, message: "云端快照下载并通过 SHA-256 校验，请确认恢复")
        }
    }

    func deleteRemoteItem(_ item: WebDAVRemoteItem) {
        let client = WebDAVClient(config: webdavConfig, password: passwordInput)
        runAsyncTask(label: "正在删除 \(item.fileName)…") {
            try await client.deleteBackup(item: item)
            self.remoteItems.removeAll { $0.id == item.id }
            self.banner = BackupStatusBanner(tone: .success, message: "已删除云端快照：\(item.fileName)")
        }
    }

    private func runAsyncTask(label: String, operation: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true; busyLabel = label
        Task { @MainActor in
            defer { self.isBusy = false; self.busyLabel = "" }
            do { try await operation() }
            catch { self.banner = BackupStatusBanner(tone: .error, message: error.localizedDescription) }
        }
    }
}
