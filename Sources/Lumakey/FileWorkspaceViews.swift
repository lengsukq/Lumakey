import LumakeyCore
import SwiftUI

struct FileWorkspaceView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 12) {
            LocationSidebarView(viewModel: viewModel)
                .frame(width: 205)

            VStack(spacing: 10) {
                WorkspaceTopToolbar(viewModel: viewModel)
                HStack(spacing: 10) {
                    FilePaneView(viewModel: viewModel, pane: .left, state: viewModel.leftPane)
                    if viewModel.layoutMode == .dual {
                        FilePaneView(viewModel: viewModel, pane: .right, state: viewModel.rightPane)
                    }
                }
            }

            SidePreviewPanelView(viewModel: viewModel)
                .frame(width: 350)
        }
    }
}

private struct LocationSidebarView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("位置与磁盘").font(.headline)
                Spacer()
                Button { viewModel.refreshLocations() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.locations) { item in
                        let isActive = viewModel.activePaneState.currentDirectory.standardizedFileURL.path == item.url.standardizedFileURL.path
                        Button {
                            viewModel.navigate(pane: viewModel.activePane, to: item.url)
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                SquircleBadge(
                                    symbol: item.kind.symbolName,
                                    topColor: item.kind == .external ? .orange : .cyan,
                                    bottomColor: item.kind == .external ? .red : .blue,
                                    size: 28
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.callout.weight(.medium)).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
                                    if let vol = item.volumeSummary {
                                        Text(vol.formatKind.badgeText)
                                            .font(.caption2)
                                            .foregroundStyle(vol.formatKind == .ntfsReadOnly ? .orange : .secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(isActive ? LiquidColors.highlightGlow : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("宿主机工具链").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ToolRow(label: "ntfs-3g", available: viewModel.toolingStatus.ntfs3gPath != nil)
                ToolRow(label: "ffmpeg", available: viewModel.toolingStatus.ffmpegPath != nil)
                ToolRow(label: "ffprobe", available: viewModel.toolingStatus.ffprobePath != nil)
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }
}

private struct ToolRow: View {
    let label: String
    let available: Bool

    var body: some View {
        HStack {
            Text(label).font(.caption)
            Spacer()
            Text(available ? "已就绪" : "未安装")
                .font(.caption2)
                .foregroundStyle(available ? .green : .secondary)
        }
    }
}

private struct FilePaneView: View {
    @ObservedObject var viewModel: AppViewModel
    let pane: PaneSide
    let state: PaneState

    var body: some View {
        let visible = state.visibleEntries
        return VStack(spacing: 8) {
            WorkspacePaneHeaderToolbar(viewModel: viewModel, pane: pane, state: state)
            categoryFilterStrip
            if let summary = state.volumeSummary, summary.formatKind == .ntfsReadOnly {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.orange)
                    Text("NTFS 只读卷（\(summary.capacityText)）：仅开放浏览、播放、OCR 与校验，已保护禁止写入。")
                        .font(.caption)
                    Spacer()
                }
                .padding(8)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
            }
            if let diag = state.diagnostic {
                Text("\(diag.title)：\(diag.reason) \(diag.nextStep)")
                    .font(.caption).foregroundStyle(.red).padding(8)
            }
            WorkspaceEntriesContentView(viewModel: viewModel, pane: pane, state: state, entries: visible)
            WorkspaceFloatingActionBar(viewModel: viewModel, pane: pane)
            Divider().opacity(0.22)
            WorkspacePaneFooterStatusBar(
                state: state,
                visibleCount: visible.count,
                selectionSummary: viewModel.selectionSummaryText(in: pane),
                serviceMessage: viewModel.activePane == pane ? viewModel.serviceMessage : nil
            )
        }
        .padding(10)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
        .overlay {
            if viewModel.activePane == pane && viewModel.layoutMode == .dual {
                RoundedRectangle(cornerRadius: LiquidRadii.bento, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.5)
            }
        }
    }

    private var categoryFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(WorkspaceMediaFilter.allCases) { filter in
                    let count = state.categoryCount(for: filter)
                    Button("\(filter.title) (\(count))") {
                        viewModel.activePane = pane
                        viewModel.mutatePane(pane) { $0.mediaFilter = filter }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: state.mediaFilter == filter))
                }
                if state.mediaFilter != .all || !state.filterText.isEmpty {
                    Button("重置筛选") {
                        viewModel.activePane = pane
                        viewModel.mutatePane(pane) { $0.mediaFilter = .all; $0.filterText = "" }
                    }
                    .buttonStyle(GlassPillButtonStyle())
                }
            }
        }
    }
}
