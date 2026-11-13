import AppKit
import Foundation
import LumakeyCore
import SwiftUI

enum PluginCenterTab: String, CaseIterable, Identifiable {
    case gallery = "精选市场"
    case inspector = "配置与预览"
    case scaffold = "脚手架"
    var id: String { rawValue }
}

@MainActor
final class PluginCenterController: ObservableObject {
    @Published var activeTab: PluginCenterTab = .gallery
    @Published var selectedPluginID: String?
    @Published var configDraft: [String: String] = [:]
    @Published var testQuery: String = ""
    @Published var isRunning: Bool = false
    @Published var latestOutput: PluginResolvedOutput?
    @Published var statusNote: String = "350ms 防抖实时热重载就绪"
    @Published var isWatcherOnline: Bool = false

    @Published var newID: String = "uuid-card"
    @Published var newName: String = "UUID 视图卡"
    @Published var newKeywords: String = "uuidcard"
    @Published var newMode: PluginMode = .view

    private var watcher: PluginDirectoryWatcher?
    private var runTask: Task<Void, Never>?

    func startWatching(syncing viewModel: AppViewModel) {
        if watcher == nil {
            watcher = PluginDirectoryWatcher(debounceInterval: 0.35) { [weak self, weak viewModel] in
                Task { @MainActor in
                    guard let self, let viewModel else { return }
                    viewModel.reloadAppsAndPlugins()
                    self.syncSelection(from: viewModel.plugins)
                    let df = DateFormatter()
                    df.dateFormat = "HH:mm:ss"
                    self.statusNote = "已热重载 · \(df.string(from: Date()))"
                }
            }
        }
        isWatcherOnline = watcher?.isWatching ?? false
        syncSelection(from: viewModel.plugins)
    }

    func stopWatching() {
        runTask?.cancel()
        runTask = nil
        watcher?.stop()
        watcher = nil
        isWatcherOnline = false
    }

    func syncSelection(from plugins: [PluginDescriptor]) {
        if let currentID = selectedPluginID,
           let matched = plugins.first(where: { $0.id == currentID }) {
            if configDraft.isEmpty { configDraft = matched.userConfig }
            return
        }
        if let first = plugins.first {
            select(first, switchTab: false)
        } else {
            selectedPluginID = nil
            configDraft = [:]
        }
    }

    func select(_ plugin: PluginDescriptor, switchTab: Bool = true) {
        selectedPluginID = plugin.id
        configDraft = plugin.userConfig
        if switchTab { activeTab = .inspector }
    }

    func binding(for field: PluginConfigField) -> Binding<String> {
        let fallback = field.defaultValue ?? ""
        return Binding(
            get: { self.configDraft[field.key] ?? fallback },
            set: { self.configDraft[field.key] = $0 }
        )
    }

    func boolBinding(for field: PluginConfigField) -> Binding<Bool> {
        let fallback = (field.defaultValue ?? "false").lowercased() == "true"
        return Binding(
            get: { (self.configDraft[field.key].map { $0.lowercased() == "true" }) ?? fallback },
            set: { self.configDraft[field.key] = $0 ? "true" : "false" }
        )
    }

    func setEnabled(_ plugin: PluginDescriptor, isEnabled: Bool, viewModel: AppViewModel) {
        do {
            try PluginSystem.setPluginEnabled(id: plugin.id, isEnabled: isEnabled)
            viewModel.reloadAppsAndPlugins()
            statusNote = "\(plugin.manifest.name) 已\(isEnabled ? "启用" : "禁用")"
        } catch {
            statusNote = error.localizedDescription
        }
    }

    func saveConfig(for plugin: PluginDescriptor, viewModel: AppViewModel) {
        do {
            try PluginSystem.updatePluginConfig(id: plugin.id, values: configDraft)
            viewModel.reloadAppsAndPlugins()
            statusNote = "已保存 \(plugin.manifest.name) 配置"
            viewModel.serviceMessage = statusNote
        } catch {
            statusNote = error.localizedDescription
        }
    }

    func runAsync(_ plugin: PluginDescriptor, arguments: [String] = [], viewModel: AppViewModel) {
        runTask?.cancel()
        isRunning = true
        let query = testQuery
        let clip = NSPasteboard.general.string(forType: .string) ?? ""
        runTask = Task { [weak self, weak viewModel] in
            do {
                let resolved = try await PluginSystem.runPluginAsync(
                    plugin, query: query, clipboardText: clip, arguments: arguments
                )
                guard !Task.isCancelled, let self else { return }
                self.isRunning = false
                self.latestOutput = resolved
                viewModel?.pluginOutputText = resolved.plainText
                self.statusNote = "\(plugin.manifest.name) 完成 (\(resolved.execution.durationMs) ms)"
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isRunning = false
                let msg = (error as? LumakeyError)?.diagnostic.reason ?? error.localizedDescription
                self.statusNote = msg
                viewModel?.pluginOutputText = msg
            }
        }
    }

    func installStarter(_ tpl: PluginStarterTemplate, viewModel: AppViewModel) {
        do {
            let installed = try PluginStarterGallery.install(templateID: tpl.id, overwrite: true)
            viewModel.reloadAppsAndPlugins()
            select(installed, switchTab: true)
            statusNote = "已安装精选模板：\(installed.manifest.name)"
            runAsync(installed, viewModel: viewModel)
        } catch {
            statusNote = error.localizedDescription
        }
    }

    func scaffoldCustom(viewModel: AppViewModel) {
        let kws = newKeywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        do {
            let created = try PluginSystem.scaffoldPlugin(
                id: newID, name: newName, keywords: kws,
                description: "通过 Lumakey 插件中心创建", mode: newMode
            )
            viewModel.reloadAppsAndPlugins()
            select(created, switchTab: true)
            statusNote = "已创建插件：\(created.manifest.name)"
            runAsync(created, viewModel: viewModel)
        } catch let err as LumakeyError {
            viewModel.diagnostic = err.diagnostic
            statusNote = err.diagnostic.reason
        } catch {
            statusNote = error.localizedDescription
        }
    }

    func remove(_ plugin: PluginDescriptor, viewModel: AppViewModel) {
        do {
            try PluginSystem.removePlugin(id: plugin.id)
            if latestOutput?.pluginID == plugin.id { latestOutput = nil }
            viewModel.reloadAppsAndPlugins()
            syncSelection(from: viewModel.plugins)
            statusNote = "已移除插件：\(plugin.manifest.name)"
        } catch {
            statusNote = error.localizedDescription
        }
    }

    func importFromFinder(viewModel: AppViewModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "导入插件目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try PluginSystem.importPluginDirectory(from: url, overwrite: true)
            viewModel.reloadAppsAndPlugins()
            select(imported, switchTab: true)
            statusNote = "已导入插件：\(imported.manifest.name)"
        } catch {
            statusNote = (error as? LumakeyError)?.diagnostic.reason ?? error.localizedDescription
        }
    }

    func exportToFinder(_ plugin: PluginDescriptor) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "导出到此文件夹"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        if let outURL = try? PluginSystem.exportPlugin(id: plugin.id, to: dest) {
            NSWorkspace.shared.activateFileViewerSelecting([outURL])
            statusNote = "已导出至 \(outURL.path)"
        }
    }

    func openPluginsDirectoryInFinder() {
        let dir = PluginSystem.defaultPluginsDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}
