import AppKit
import LumakeyCore
import SwiftUI

@MainActor
private final class MosDraftBundleState: ObservableObject {
    @Published var bundleInput: String = ""
}

struct MosPluginSettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var draft = MosDraftBundleState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeroHeader(
                    symbol: "computermouse.fill", topColor: .cyan, bottomColor: .indigo,
                    title: "内置 Mos 鼠标平滑与滚轮方向",
                    subtitle: "自动区分物理鼠标滚轮与触控板，提供滚轮反转与 120Hz 平滑插值；闲置时零后台消耗。"
                ) {
                    Toggle("", isOn: binding(\.enabled))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                permissionStatusRow
                behaviorCard
                exclusionsCard
            }
        }
        .onAppear {
            viewModel.refreshMosStatus()
        }
    }

    private var permissionStatusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            Text(statusSummary)
                .font(.caption.weight(.medium))
            Spacer()
            if !viewModel.mosAccessibilityTrusted {
                Button("请求辅助功能授权") {
                    viewModel.requestMosAccessibilityPermission()
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true))

                Button("打开系统设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(GlassPillButtonStyle())
            }
            Button("刷新状态") {
                viewModel.refreshMosStatus()
            }
            .buttonStyle(GlassPillButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("滚轮与平滑参数").font(.callout.weight(.semibold))

            Toggle("反转物理鼠标垂直滚轮方向（保留触控板自然滚动）", isOn: binding(\.reverseWheelDirection))
            Toggle("启用 120Hz 高帧率像素级平滑滚动", isOn: binding(\.smoothScroll))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("单格滚动步长").font(.caption)
                    Spacer()
                    Text("\(Int(viewModel.mosConfig.stepPixels)) px")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: binding(\.stepPixels), in: 16...96, step: 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("丝滑阻尼系数").font(.caption)
                    Spacer()
                    Text(String(format: "%.2f", viewModel.mosConfig.smoothness))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: binding(\.smoothness), in: 0.08...0.40, step: 0.02)
            }

            Divider().opacity(0.25)

            Toggle("按住 Shift (⇧) 将滚轮转换为水平横向滚动", isOn: binding(\.shiftHorizontal))
            Toggle("按住 Option (⌥) 触发 3× 极速长页浏览", isOn: binding(\.optionBoost))
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private var exclusionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("应用排除列表（Bundle ID）").font(.callout.weight(.semibold))
            Text("在下列应用中保持系统原始滚轮行为（例如全屏远程桌面、游戏或 CAD 工具）：")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                GlassInputField(symbol: "app.badge", placeholder: "输入 Bundle ID，例如 com.microsoft.rdc.macos", text: $draft.bundleInput)
                Button("添加") {
                    addExclusion()
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true))
                .disabled(draft.bundleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if viewModel.mosConfig.excludedBundleIDs.isEmpty {
                Text("暂无排除应用，所有应用均生效。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                FlowTagsList(items: viewModel.mosConfig.excludedBundleIDs) { id in
                    var next = viewModel.mosConfig
                    next.excludedBundleIDs.removeAll { $0 == id }
                    viewModel.applyMosConfig(next)
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private var statusColor: Color {
        if !viewModel.mosConfig.enabled { return .secondary }
        if !viewModel.mosAccessibilityTrusted { return .orange }
        return viewModel.mosTapActive ? .green : .yellow
    }

    private var statusSummary: String {
        if !viewModel.mosConfig.enabled { return "插件已关闭 · 未安装 CGEventTap（零系统事件回调消耗）" }
        if !viewModel.mosAccessibilityTrusted { return "需要系统「辅助功能」权限以区分鼠标与触控板事件" }
        return viewModel.mosTapActive ? "CGEventTap 已激活 · 正在拦截物理鼠标滚轮" : "辅助功能已授权，准备激活中"
    }

    private func binding<T>(_ keyPath: WritableKeyPath<MosConfig, T>) -> Binding<T> {
        Binding(
            get: { viewModel.mosConfig[keyPath: keyPath] },
            set: { newValue in
                var next = viewModel.mosConfig
                next[keyPath: keyPath] = newValue
                viewModel.applyMosConfig(next)
            }
        )
    }

    private func addExclusion() {
        let trimmed = draft.bundleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = viewModel.mosConfig
        if !next.excludedBundleIDs.contains(trimmed) {
            next.excludedBundleIDs.append(trimmed)
            viewModel.applyMosConfig(next)
        }
        draft.bundleInput = ""
    }
}

private struct FlowTagsList: View {
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { id in
                HStack(spacing: 6) {
                    Text(id).font(.caption2.monospaced()).lineLimit(1)
                    Spacer(minLength: 4)
                    Button { onRemove(id) } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            }
        }
    }
}
