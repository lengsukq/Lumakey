import SwiftUI
import LumakeyCore

@MainActor
private final class PluginDraftState: ObservableObject {
    @Published var newID = "uuid-gen"
    @Published var newName = "UUID 生成器"
    @Published var newKeywords = "uuid,guid"
    @Published var testQuery = "generate"
}

struct PluginCenterView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var draft = PluginDraftState()

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("已安装插件 (\(viewModel.plugins.count))").font(.headline)
                    Spacer()
                    Button("刷新") { viewModel.reloadAppsAndPlugins() }
                        .buttonStyle(GlassPillButtonStyle())
                }
                if viewModel.plugins.isEmpty {
                    ContentUnavailableView {
                        Label("暂无外部脚本插件", systemImage: "puzzlepiece.extension")
                    } description: {
                        Text("可在右侧输入名称快速脚手架创建，或接入 lumakey-mcp 自动生成。")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
                } else {
                    List(viewModel.plugins) { plugin in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(plugin.manifest.name).font(.body.weight(.semibold))
                                Text(plugin.manifest.mode.rawValue)
                                    .font(.caption2)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(LiquidColors.pillSurface, in: Capsule())
                                Spacer()
                                Button("运行测试") { viewModel.runPlugin(plugin, query: draft.testQuery) }
                                    .buttonStyle(GlassPillButtonStyle())
                            }
                            Text("ID: \(plugin.id) · 触发词: \(plugin.manifest.keywords.joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary)
                            if !plugin.isValid {
                                Text(plugin.validationIssues.joined(separator: "；"))
                                    .font(.caption).foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("脚手架生成（写入 Lumakey Plugins 目录）").font(.callout.weight(.semibold))
                    GlassInputField(symbol: "number", placeholder: "插件 ID (小写/数字/连字符)", text: $draft.newID)
                    GlassInputField(symbol: "tag", placeholder: "显示名称", text: $draft.newName)
                    GlassInputField(symbol: "text.magnifyingglass", placeholder: "触发关键词（逗号分隔）", text: $draft.newKeywords)
                    GlassInputField(symbol: "play.circle", placeholder: "测试查询参数", text: $draft.testQuery)
                    Button("创建示例插件") {
                        viewModel.scaffoldExamplePlugin(id: draft.newID, name: draft.newName, keywordsCSV: draft.newKeywords)
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
                }
                .padding(12)
                .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("最近运行输出 / MCP 说明").font(.callout.weight(.semibold))
                    Text("AI Agent 可通过 stdio 启动 Lumakey.app/Contents/MacOS/lumakey-mcp 自动编写、校验并测试插件。")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        Text(viewModel.pluginOutputText.isEmpty ? "尚未执行插件输出。" : viewModel.pluginOutputText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
            }
            .frame(width: 340)
        }
    }
}
