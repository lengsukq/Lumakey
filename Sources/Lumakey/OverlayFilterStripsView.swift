import AppKit
import LumakeyCore
import SwiftUI

struct OverlayEverythingFilterStrip: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.availableEverythingScopes) { scope in
                    let active = viewModel.everythingScope == scope
                    Button(scope.title) {
                        viewModel.rebuildEverythingIndex(scope: scope)
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: active))
                }
                Divider().frame(height: 16).opacity(0.35)
                ForEach(["ext:swift", "ext:md", "pic:", "video:", "folder:"], id: \.self) { token in
                    Button(token) {
                        viewModel.overlayQuery = viewModel.overlayQuery.isEmpty ? token : "\(viewModel.overlayQuery) \(token)"
                        viewModel.bumpFocusToken()
                    }
                    .buttonStyle(GlassPillButtonStyle())
                }
                if viewModel.isIndexingEverything {
                    ProgressView().controlSize(.small).padding(.leading, 4)
                } else {
                    Text("\(viewModel.everythingNodeCount) 节点")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(LiquidColors.textSecondary)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
    }
}

struct OverlayClipboardCategoryStrip: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ClipboardCategory.allCases) { cat in
                Button(cat.rawValue) {
                    viewModel.clipboardCategory = cat
                    viewModel.overlaySelectedIndex = 0
                }
                .buttonStyle(GlassPillButtonStyle(prominent: viewModel.clipboardCategory == cat))
            }
            Spacer()
            Button("清空非收藏") {
                viewModel.clearUnpinnedClipboard()
            }
            .buttonStyle(GlassPillButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

struct OverlayBottomFooterBar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ZStack {
            WindowDragRegion()
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.caption).foregroundStyle(.cyan)
                Text(viewModel.serviceMessage ?? "⌘1..9 瞬启候选 · ⌘C 复制结果 · ⌘↩ 定位/独立打开")
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)
                Spacer()

                Button { viewModel.openRoute(.workspace) } label: {
                    Label("文件台 ⌥E", systemImage: "sidebar.squares.left").font(.caption2)
                }
                .buttonStyle(.plain).foregroundStyle(LiquidColors.textSecondary)

                Button { viewModel.startGifRecording() } label: {
                    Image(systemName: "record.circle.fill").font(.caption).foregroundStyle(.pink)
                }
                .buttonStyle(.plain).help("区域 / 窗口 GIF 动图录制 (⌥G)")

                Button { viewModel.openRoute(.networkMonitor) } label: {
                    Image(systemName: "network").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                }
                .buttonStyle(.plain).help("本机网络流量与去向监控 (⌥N)")

                Button { SystemPulseWindowController.shared.toggleFloatingWidget() } label: {
                    Image(systemName: "waveform.path.ecg").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                }
                .buttonStyle(.plain).help("系统脉搏悬浮监控 (⌥M)")

                Button { viewModel.openRoute(.settings(.backup)) } label: {
                    Image(systemName: "externaldrive.badge.icloud").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                }
                .buttonStyle(.plain).help("数据导出与 WebDAV 云同步")

                Button { viewModel.openRoute(.settings(.mos)) } label: {
                    Image(systemName: "computermouse.fill").font(.caption)
                        .foregroundStyle(viewModel.mosTapActive ? .cyan : LiquidColors.textSecondary)
                }
                .buttonStyle(.plain).help("Mos 鼠标平滑与滚轮方向")

                Button { viewModel.openRoute(.settings(.general)) } label: {
                    Image(systemName: "gearshape.fill").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(LiquidColors.textSecondary).help("设置、热键与插件中心 (⌘,)")

                Button { viewModel.isOverlayPinned.toggle() } label: {
                    Image(systemName: viewModel.isOverlayPinned ? "pin.fill" : "pin").font(.caption)
                        .foregroundStyle(viewModel.isOverlayPinned ? .cyan : LiquidColors.textSecondary)
                }
                .buttonStyle(.plain).help("固定悬浮窗不被失焦收起")

                Divider().frame(height: 14).opacity(0.35)
                KeycapPill(title: "过滤", keyText: "⇥")
                KeycapPill(title: "预览", keyText: "⌘Y")
                KeycapPill(title: "执行", keyText: "↩", prominent: true)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 36)
        .background(LiquidColors.pillSurface.opacity(0.55))
    }
}
