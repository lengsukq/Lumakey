import AppKit
import LumakeyCore
import SwiftUI

struct PluginCenterView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var ctrl = PluginCenterController()

    private var selectedPlugin: PluginDescriptor? {
        guard let id = ctrl.selectedPluginID else { return viewModel.plugins.first }
        return viewModel.plugins.first { $0.id == id } ?? viewModel.plugins.first
    }

    var body: some View {
        HStack(spacing: 12) {
            installedPane
            rightWorkbench
                .frame(width: 390)
        }
        .onAppear { ctrl.startWatching(syncing: viewModel) }
        .onDisappear { ctrl.stopWatching() }
    }

    private var installedPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text("已安装 (\(viewModel.plugins.count))").font(.callout.weight(.bold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(ctrl.isWatcherOnline ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(ctrl.statusNote)
                        .font(.system(size: 10))
                        .foregroundStyle(LiquidColors.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(LiquidColors.pillSurface, in: Capsule())
                Spacer(minLength: 4)
                Button("导入…") { ctrl.importFromFinder(viewModel: viewModel) }
                    .buttonStyle(GlassPillButtonStyle())
                Button("目录") { ctrl.openPluginsDirectoryInFinder() }
                    .buttonStyle(GlassPillButtonStyle())
                Button("刷新") { viewModel.reloadAppsAndPlugins(); ctrl.syncSelection(from: viewModel.plugins) }
                    .buttonStyle(GlassPillButtonStyle())
            }

            if viewModel.plugins.isEmpty {
                ContentUnavailableView {
                    Label("暂无已安装插件", systemImage: "puzzlepiece.extension")
                } description: {
                    Text("可在右侧「精选市场」一键安装诊断/哈希/端口/速记插件，或使用脚手架创建。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.plugins) { plugin in
                            installedPluginRow(plugin)
                        }
                    }
                    .padding(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
            }
        }
    }

    private func installedPluginRow(_ plugin: PluginDescriptor) -> some View {
        let isSelected = selectedPlugin?.id == plugin.id
        let symbol = plugin.manifest.icon ?? (plugin.manifest.mode == .view ? "rectangle.3.group.bubble.fill" : "terminal.fill")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                SquircleBadge(
                    symbol: symbol,
                    topColor: plugin.manifest.mode == .view ? .cyan : .purple,
                    bottomColor: plugin.manifest.mode == .view ? .blue : .indigo,
                    size: 32
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(plugin.manifest.name).font(.callout.weight(.semibold))
                        Text(plugin.manifest.mode.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(plugin.manifest.mode == .view ? .cyan : .purple)
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(LiquidColors.pillSurface, in: Capsule())
                        if let hk = plugin.manifest.hotkey, !hk.isEmpty {
                            Text(hk).font(.caption2.monospaced()).foregroundStyle(LiquidColors.textSecondary)
                        }
                    }
                    Text("ID: \(plugin.id) · 触发词: \(plugin.manifest.keywords.joined(separator: ", "))")
                        .font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Toggle("", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { ctrl.setEnabled(plugin, isEnabled: $0, viewModel: viewModel) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            if !plugin.isValid {
                Text(plugin.validationIssues.joined(separator: "；"))
                    .font(.caption2).foregroundStyle(.red)
            }

            HStack(spacing: 6) {
                Button("配置与预览") { ctrl.select(plugin, switchTab: true) }
                    .buttonStyle(GlassPillButtonStyle(prominent: isSelected))
                Button("访达") { NSWorkspace.shared.activateFileViewerSelecting([plugin.directoryURL]) }
                    .buttonStyle(GlassPillButtonStyle())
                Button("导出") { ctrl.exportToFinder(plugin) }
                    .buttonStyle(GlassPillButtonStyle())
                Spacer()
                Button("删除") { ctrl.remove(plugin, viewModel: viewModel) }
                    .buttonStyle(GlassPillButtonStyle())
            }
        }
        .padding(10)
        .background(isSelected ? LiquidColors.highlightGlow : LiquidColors.pillSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous)
                .strokeBorder(isSelected ? Color.cyan.opacity(0.45) : LiquidColors.pillBorder, lineWidth: 0.8)
        }
    }

    private var rightWorkbench: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(PluginCenterTab.allCases) { tab in
                    Button(tab.rawValue) { ctrl.activeTab = tab }
                        .buttonStyle(GlassPillButtonStyle(prominent: ctrl.activeTab == tab))
                }
                Spacer()
            }

            switch ctrl.activeTab {
            case .gallery:
                PluginStarterGalleryListView(installedIDs: Set(viewModel.plugins.map(\.id))) { tpl in
                    ctrl.installStarter(tpl, viewModel: viewModel)
                }
            case .inspector:
                inspectorTab
            case .scaffold:
                scaffoldTab
            }
        }
    }

    @ViewBuilder
    private var inspectorTab: some View {
        if let plugin = selectedPlugin {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let fields = plugin.manifest.config, !fields.isEmpty {
                        PluginConfigFormCard(plugin: plugin, fields: fields, ctrl: ctrl, viewModel: viewModel)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("实时运行测试 · \(plugin.manifest.name)").font(.caption.weight(.bold))
                            Spacer()
                            if ctrl.isRunning { ProgressView().controlSize(.small) }
                        }
                        HStack(spacing: 6) {
                            GlassInputField(symbol: "play.circle", placeholder: "输入查询参数 query (可留空)", text: $ctrl.testQuery)
                            Button("运行 ↩") { ctrl.runAsync(plugin, viewModel: viewModel) }
                                .buttonStyle(GlassPillButtonStyle(prominent: true))
                        }
                    }
                    .padding(10)
                    .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)

                    if let out = ctrl.latestOutput, out.pluginID == plugin.id, let viewPayload = out.viewPayload {
                        PluginStructuredViewCard(
                            payload: viewPayload,
                            onCopyText: { val in
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(val, forType: .string)
                                viewModel.serviceMessage = "已复制：\(val)"
                            },
                            onRunCommandArgs: { args in
                                ctrl.runAsync(plugin, arguments: args, viewModel: viewModel)
                            }
                        )
                    } else {
                        let rawText = (ctrl.latestOutput?.pluginID == plugin.id ? ctrl.latestOutput?.plainText : nil) ?? viewModel.pluginOutputText
                        Text(rawText.isEmpty ? "点击上方「运行」查看声明式 view 卡片或脚本输出。" : rawText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(11)
                            .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
                    }
                }
            }
        } else {
            ContentUnavailableView("未选择插件", systemImage: "slider.horizontal.3", description: Text("请先从左侧选择插件或在「精选市场」安装。"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
        }
    }

    private var scaffoldTab: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("脚手架创建自定义插件").font(.callout.weight(.semibold))
            GlassInputField(symbol: "number", placeholder: "插件 ID (小写/数字/连字符)", text: $ctrl.newID)
            GlassInputField(symbol: "tag", placeholder: "显示名称", text: $ctrl.newName)
            GlassInputField(symbol: "text.magnifyingglass", placeholder: "触发关键词（逗号分隔）", text: $ctrl.newKeywords)
            HStack(spacing: 8) {
                Text("输出协议:").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                ForEach(PluginMode.allCases, id: \.rawValue) { mode in
                    Button(mode.rawValue.uppercased()) { ctrl.newMode = mode }
                        .buttonStyle(GlassPillButtonStyle(prominent: ctrl.newMode == mode))
                }
            }
            Button("生成并运行测试") { ctrl.scaffoldCustom(viewModel: viewModel) }
                .buttonStyle(GlassPillButtonStyle(prominent: true))
            Text("也可将 lumakey-mcp 接入 AI 客户端，读取 lumakey://specs/plugin-v2 自动生成。")
                .font(.caption2).foregroundStyle(LiquidColors.textSecondary)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }
}
