import AppKit
import LumakeyCore
import SwiftUI

struct WorkspaceEntriesContentView: View {
    @ObservedObject var viewModel: AppViewModel
    let pane: PaneSide
    let state: PaneState
    let entries: [FileEntry]

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView {
                Label(state.entries.isEmpty ? "目录为空" : "没有匹配当前筛选条件的文件", systemImage: "folder.badge.questionmark")
            } description: {
                if !state.entries.isEmpty {
                    Text("尝试切换分类胶囊或清空搜索关键词。")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch state.displayMode {
            case .list: listView
            case .grid: gridView
            case .compact: compactView
            }
        }
    }

    private var listView: some View {
        VStack(spacing: 0) {
            listHeaderRow
            Divider().opacity(0.2)
            List(entries) { entry in
                listRow(entry)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(selectionBackground(for: entry, cornerRadius: 8))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { activate(entry) }
                    .onTapGesture { select(entry) }
                    .contextMenu { entryContextMenu(entry) }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private var listHeaderRow: some View {
        HStack(spacing: 8) {
            sortHeaderButton("名称", field: .name)
            Spacer()
            sortHeaderButton("类型", field: .kind).frame(width: 68, alignment: .trailing)
            sortHeaderButton("大小", field: .size).frame(width: 72, alignment: .trailing)
            sortHeaderButton("修改时间", field: .modifiedAt).frame(width: 112, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(LiquidColors.pillSurface.opacity(0.45))
    }

    private func sortHeaderButton(_ title: String, field: SortField) -> some View {
        let active = state.sortField == field
        return Button {
            viewModel.activePane = pane
            viewModel.mutatePane(pane) { paneState in
                if paneState.sortField == field {
                    paneState.sortOrder = paneState.sortOrder.toggled
                } else {
                    paneState.sortField = field
                    paneState.sortOrder = field == .modifiedAt || field == .createdAt || field == .size ? .descending : .ascending
                }
            }
            viewModel.refreshDirectory(pane: pane)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if active {
                    Image(systemName: state.sortOrder == .ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .font(.caption2.weight(active ? .bold : .medium))
            .foregroundStyle(active ? LiquidColors.textPrimary : LiquidColors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func listRow(_ entry: FileEntry) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: IconCache.shared.icon(for: entry))
                .resizable()
                .frame(width: 18, height: 18)
            Text(entry.name)
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(LiquidColors.textPrimary)
            Spacer()
            Text(entry.mediaKind.badgeTitle)
                .font(.caption2)
                .foregroundStyle(LiquidColors.textSecondary)
                .frame(width: 68, alignment: .trailing)
            Text(entry.formattedSize)
                .font(.caption.monospacedDigit())
                .foregroundStyle(LiquidColors.textSecondary)
                .frame(width: 72, alignment: .trailing)
            Text(entry.formattedDate)
                .font(.caption.monospacedDigit())
                .foregroundStyle(LiquidColors.textSecondary)
                .frame(width: 112, alignment: .trailing)
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118, maximum: 152), spacing: 10)], spacing: 10) {
                ForEach(entries) { entry in
                    VStack(spacing: 6) {
                        WorkspaceThumbStage(entry: entry, size: 84)
                        Text(entry.name)
                            .font(.caption.weight(.medium)).foregroundStyle(LiquidColors.textPrimary)
                            .multilineTextAlignment(.center).lineLimit(2).frame(height: 30, alignment: .top)
                        Text("\(entry.mediaKind.badgeTitle) · \(entry.formattedSize)")
                            .font(.caption2.monospacedDigit()).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(selectionBackground(for: entry, cornerRadius: LiquidRadii.control))
                    .overlay {
                        if viewModel.selectedEntryIDs.contains(entry.id) {
                            RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.2)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                    .onTapGesture(count: 2) { activate(entry) }
                    .onTapGesture { select(entry) }
                    .contextMenu { entryContextMenu(entry) }
                }
            }
            .padding(10)
        }
    }

    private var compactView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 6) {
                ForEach(entries) { entry in
                    HStack(spacing: 8) {
                        Image(nsImage: IconCache.shared.icon(for: entry))
                            .resizable()
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(LiquidColors.textPrimary)
                                .lineLimit(1)
                            Text("\(entry.mediaKind.badgeTitle) · \(entry.formattedSize)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(LiquidColors.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(selectionBackground(for: entry, cornerRadius: 8))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { activate(entry) }
                    .onTapGesture { select(entry) }
                    .contextMenu { entryContextMenu(entry) }
                }
            }
            .padding(8)
        }
    }

    private func selectionBackground(for entry: FileEntry, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(viewModel.selectedEntryIDs.contains(entry.id) ? LiquidColors.highlightGlow : Color.clear)
    }

    private func select(_ entry: FileEntry) {
        viewModel.activePane = pane
        viewModel.selectEntry(entry)
    }

    private func activate(_ entry: FileEntry) {
        viewModel.activePane = pane
        viewModel.openEntry(entry, in: pane)
    }

    @ViewBuilder
    private func entryContextMenu(_ entry: FileEntry) -> some View {
        Button(entry.isDirectory ? "进入目录" : "打开") { activate(entry) }
        if entry.mediaKind == .image {
            Button("贴图钉在屏幕（图片置顶）") { PinWindowController.shared.pinImage(at: entry.url) }
            Button("大图窗口置顶查看") { viewModel.openMediaWindow(for: entry.url, kind: .image, pinOnTop: true) }
        } else if entry.mediaKind == .video {
            Button("影院播放（同目录播放列表）") { viewModel.openMediaWindow(for: entry.url, kind: .video, pinOnTop: false) }
            Button("视频窗口置顶播放") { viewModel.openMediaWindow(for: entry.url, kind: .video, pinOnTop: true) }
        } else if entry.mediaKind == .markdown || entry.mediaKind == .text {
            Button("独立窗口阅读") { viewModel.openMediaWindow(for: entry.url, kind: entry.mediaKind) }
        }
        Divider()
        Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        Button("复制完整路径") {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.url.path, forType: .string)
            viewModel.serviceMessage = "已复制路径"
        }
        Button("批量重命名") { select(entry); viewModel.showBatchRenameSheet = true }
    }
}
