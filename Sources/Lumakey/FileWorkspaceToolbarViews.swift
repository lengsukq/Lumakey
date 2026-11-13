import LumakeyCore
import SwiftUI

struct WorkspaceTopToolbar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ExplorerLayoutMode.allCases) { mode in
                    Button(mode.title) { viewModel.layoutMode = mode }
                        .buttonStyle(GlassPillButtonStyle(prominent: viewModel.layoutMode == mode))
                }
                Button("新建标签") { viewModel.addTab(pane: viewModel.activePane) }
                    .buttonStyle(GlassPillButtonStyle())
                Button("新建文件夹 (⇧⌘N)") { viewModel.beginCreateFolder(in: viewModel.activePane) }
                    .buttonStyle(GlassPillButtonStyle())
                Button("批量重命名") { viewModel.showBatchRenameSheet = true }
                    .buttonStyle(GlassPillButtonStyle())
                Button("秒搜此目录 (⌥F)") {
                    let targetDir = viewModel.activePaneState.currentDirectory
                    if viewModel.everythingIndex == nil {
                        viewModel.rebuildEverythingIndex(scope: .volume(name: targetDir.lastPathComponent, mountPath: targetDir.path))
                    }
                    viewModel.overlayQuery = "path:\(targetDir.lastPathComponent) "
                    viewModel.showOverlay(filter: .files)
                }
                .buttonStyle(GlassPillButtonStyle())

                if let summary = viewModel.selectionSummaryText(in: viewModel.activePane) {
                    LiquidStatusPill(title: summary, symbol: "checkmark.circle", tint: .cyan)
                }

                if let clip = viewModel.workspaceClipboard, !clip.isEmpty {
                    let title = clip.mode == .cutMove
                        ? "移动 \(clip.urls.count) 项到此目录 (⌘V)"
                        : "粘贴 \(clip.urls.count) 项到此目录 (⌘V)"
                    Button(title) { viewModel.pasteWorkspaceClipboard(forceMove: false) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                }

                Spacer(minLength: 12)
                Button("快捷台 (⌥Space)") { viewModel.showOverlay(filter: .all) }.buttonStyle(GlassPillButtonStyle())
                Button("网络流量 (⌥N)") { viewModel.openRoute(.networkMonitor) }.buttonStyle(GlassPillButtonStyle())
                Button("系统截图 (⌥A)") { viewModel.captureAndPinScreenshot() }.buttonStyle(GlassPillButtonStyle(prominent: true))
            }
            .frame(minWidth: 680)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }
}

struct WorkspacePaneHeaderToolbar: View {
    @ObservedObject var viewModel: AppViewModel
    let pane: PaneSide
    let state: PaneState

    var body: some View {
        VStack(spacing: 6) {
            tabBarStrip
            navigationAndControlsRow
        }
    }

    private var tabBarStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(state.tabs) { tab in
                    HStack(spacing: 4) {
                        Button(tab.title) {
                            viewModel.activePane = pane
                            viewModel.selectTab(tab.id, in: pane)
                        }
                        .buttonStyle(GlassPillButtonStyle(prominent: tab.id == state.activeTabID))
                        if state.tabs.count > 1 {
                            Button { viewModel.closeTab(tab.id, in: pane) } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption2).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var navigationAndControlsRow: some View {
        HStack(spacing: 6) {
            Button { viewModel.activePane = pane; viewModel.goBack(pane: pane) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(GlassPillButtonStyle()).disabled(state.history.isEmpty)
            Button {
                viewModel.activePane = pane
                viewModel.navigate(pane: pane, to: state.currentDirectory.deletingLastPathComponent())
            } label: { Image(systemName: "arrow.up") }
                .buttonStyle(GlassPillButtonStyle())
            Button {
                viewModel.activePane = pane
                viewModel.refreshDirectory(pane: pane, forceRescan: true)
            } label: { Image(systemName: state.isScanning ? "hourglass" : "arrow.clockwise") }
                .buttonStyle(GlassPillButtonStyle()).help("强制重新扫描目录")
            Button { viewModel.beginCreateFolder(in: pane) } label: { Image(systemName: "folder.badge.plus") }
                .buttonStyle(GlassPillButtonStyle()).help("在此目录新建文件夹 (⇧⌘N)")
            Text(state.currentDirectory.path)
                .font(.caption.monospaced()).lineLimit(1).truncationMode(.head)
                .frame(minWidth: 60, maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle").font(.caption).foregroundStyle(.secondary)
                TextField("过滤文件名 / 扩展名...", text: Binding(
                    get: { state.filterText },
                    set: { text in viewModel.mutatePane(pane) { $0.filterText = text } }
                )).textFieldStyle(.plain).font(.caption)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .frame(width: 140)

            displayModeStrip
            sortControls
        }
    }

    private var displayModeStrip: some View {
        HStack(spacing: 2) {
            ForEach(WorkspaceDisplayMode.allCases) { mode in
                Button {
                    viewModel.activePane = pane
                    viewModel.mutatePane(pane) { $0.displayMode = mode }
                } label: {
                    Image(systemName: mode.symbolName)
                        .font(.caption)
                        .foregroundStyle(state.displayMode == mode ? Color.white : LiquidColors.textSecondary)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(state.displayMode == mode ? Color.accentColor : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("\(mode.title)视图")
            }
        }
        .padding(2)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var sortControls: some View {
        HStack(spacing: 5) {
            Menu {
                ForEach(SortField.allCases) { field in
                    Button {
                        viewModel.mutatePane(pane) { $0.sortField = field }
                        viewModel.refreshDirectory(pane: pane)
                    } label: {
                        if state.sortField == field { Label(field.title, systemImage: "checkmark") } else { Text(field.title) }
                    }
                }
            } label: {
                Label(state.sortField.title, systemImage: "arrow.up.arrow.down")
                    .font(.caption.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
                    .overlay { Capsule(style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.8) }
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)

            Button {
                viewModel.mutatePane(pane) { $0.sortOrder = $0.sortOrder.toggled }; viewModel.refreshDirectory(pane: pane)
            } label: { Image(systemName: state.sortOrder == .ascending ? "arrow.up" : "arrow.down") }
                .buttonStyle(GlassPillButtonStyle()).help(state.sortOrder == .ascending ? "升序排列" : "降序排列")

            Button {
                viewModel.mutatePane(pane) { $0.foldersFirst.toggle() }; viewModel.refreshDirectory(pane: pane)
            } label: { Image(systemName: state.foldersFirst ? "folder.badge.gearshape" : "folder") }
                .buttonStyle(GlassPillButtonStyle(prominent: state.foldersFirst)).help("文件夹置顶显示")

            Button {
                viewModel.mutatePane(pane) { $0.showHidden.toggle() }; viewModel.refreshDirectory(pane: pane)
            } label: { Image(systemName: state.showHidden ? "eye.fill" : "eye.slash") }
                .buttonStyle(GlassPillButtonStyle(prominent: state.showHidden)).help("显示隐藏文件")
        }
    }
}

struct WorkspacePaneFooterStatusBar: View {
    let state: PaneState
    let visibleCount: Int
    let selectionSummary: String?
    let serviceMessage: String?

    var body: some View {
        HStack(spacing: 8) {
            let base = "显示 \(visibleCount) / 共 \(state.entries.count) 项"
            let selPart = selectionSummary.map { " · \($0)" } ?? ""
            Text("\(base)\(selPart) · \(state.displayMode.title)视图 · 按\(state.sortField.title)\(state.sortOrder == .ascending ? "升序" : "降序")")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(selectionSummary == nil ? Color.secondary : LiquidColors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let serviceMessage, !serviceMessage.isEmpty {
                Text(serviceMessage)
                    .font(.caption2)
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
            }
            if let cap = state.volumeSummary?.capacityText {
                Text(cap).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
    }
}
