import SwiftUI
import LumakeyCore

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
                                SquircleBadge(symbol: item.kind.symbolName, topColor: item.kind == .external ? .orange : .cyan, bottomColor: item.kind == .external ? .red : .blue, size: 28)
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

private struct WorkspaceTopToolbar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ExplorerLayoutMode.allCases) { mode in
                Button(mode.title) { viewModel.layoutMode = mode }
                    .buttonStyle(GlassPillButtonStyle(prominent: viewModel.layoutMode == mode))
            }
            Button("新建标签") { viewModel.addTab(pane: viewModel.activePane) }
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
            Spacer()
            Button("快捷台 (⌥Space)") { viewModel.showOverlay(filter: .all) }.buttonStyle(GlassPillButtonStyle())
            Button("网络流量 (⌥N)") { viewModel.openRoute(.networkMonitor) }.buttonStyle(GlassPillButtonStyle())
            Button("系统截图 (⌥A)") { viewModel.captureAndPinScreenshot() }.buttonStyle(GlassPillButtonStyle(prominent: true))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }
}

private struct FilePaneView: View {
    @ObservedObject var viewModel: AppViewModel
    let pane: PaneSide
    let state: PaneState

    var body: some View {
        let visible = state.visibleEntries
        return VStack(spacing: 8) {
            paneHeader
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
            Divider().opacity(0.22)
            paneFooterBar(visibleCount: visible.count)
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

    private var paneHeader: some View {
        VStack(spacing: 6) {
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
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Button { viewModel.goBack(pane: pane) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(GlassPillButtonStyle()).disabled(state.history.isEmpty)
                Button { viewModel.navigate(pane: pane, to: state.currentDirectory.deletingLastPathComponent()) } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(GlassPillButtonStyle())
                Button { viewModel.refreshDirectory(pane: pane, forceRescan: true) } label: { Image(systemName: state.isScanning ? "hourglass" : "arrow.clockwise") }
                    .buttonStyle(GlassPillButtonStyle()).help("强制重新扫描目录")
                Text(state.currentDirectory.path)
                    .font(.caption.monospaced()).lineLimit(1).truncationMode(.head)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle").font(.caption).foregroundStyle(.secondary)
                    TextField("过滤文件名 / 扩展名...", text: Binding(
                        get: { state.filterText },
                        set: { text in viewModel.mutatePane(pane) { $0.filterText = text } }
                    )).textFieldStyle(.plain).font(.caption)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .frame(width: 146)

                displayModeStrip
                sortControls
            }
        }
    }

    private var displayModeStrip: some View {
        HStack(spacing: 2) {
            ForEach(WorkspaceDisplayMode.allCases) { mode in
                Button {
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
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
                    .overlay { Capsule(style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.8) }
            }
            .menuStyle(.borderlessButton)

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

    private var categoryFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(WorkspaceMediaFilter.allCases) { filter in
                    let count = state.categoryCount(for: filter)
                    Button("\(filter.title) (\(count))") { viewModel.mutatePane(pane) { $0.mediaFilter = filter } }
                        .buttonStyle(GlassPillButtonStyle(prominent: state.mediaFilter == filter))
                }
                if state.mediaFilter != .all || !state.filterText.isEmpty {
                    Button("重置筛选") { viewModel.mutatePane(pane) { $0.mediaFilter = .all; $0.filterText = "" } }
                        .buttonStyle(GlassPillButtonStyle())
                }
            }
        }
    }

    private func paneFooterBar(visibleCount: Int) -> some View {
        HStack {
            Text("显示 \(visibleCount) / 共 \(state.entries.count) 项 · \(state.displayMode.title)视图 · 按\(state.sortField.title)\(state.sortOrder == .ascending ? "升序" : "降序")")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            if let cap = state.volumeSummary?.capacityText {
                Text(cap).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}
