import AppKit
import LumakeyCore
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceEntriesContentView: View {
    @ObservedObject var viewModel: AppViewModel
    let pane: PaneSide
    let state: PaneState
    let entries: [FileEntry]
    @StateObject private var canvas = WorkspaceCanvasController()

    private var spaceName: String { "workspace-canvas-\(pane.rawValue)" }

    var body: some View {
        VStack(spacing: 0) {
            if state.displayMode == .list && !entries.isEmpty {
                listHeaderRow
                Divider().opacity(0.2)
            }
            WorkspaceMarqueeContainer(viewModel: viewModel, canvas: canvas, pane: pane, state: state, spaceName: spaceName) {
                if entries.isEmpty {
                    emptyPlaceholder
                } else {
                    switch state.displayMode {
                    case .list: listRowsStack
                    case .grid: gridCardsStack
                    case .compact: compactCardsStack
                    }
                }
            }
        }
    }

    private var emptyPlaceholder: some View {
        ContentUnavailableView {
            Label(state.entries.isEmpty ? "目录为空（支持右键新建或拖入文件）" : "没有匹配当前筛选条件的文件", systemImage: "folder.badge.questionmark")
        } description: {
            Text(state.entries.isEmpty ? "按 ⇧⌘N 新建文件夹，或按 ⌘V 粘贴文件到此处。" : "尝试切换分类胶囊或清空搜索关键词。")
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .allowsHitTesting(false)
    }

    private var listHeaderRow: some View {
        HStack(spacing: 8) {
            sortHeaderButton("名称", field: .name)
            Spacer()
            sortHeaderButton("类型", field: .kind).frame(width: 68, alignment: .trailing)
            sortHeaderButton("大小", field: .size).frame(width: 76, alignment: .trailing)
            sortHeaderButton("修改时间", field: .modifiedAt).frame(width: 116, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
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
                Text(title).lineLimit(1)
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

    private var listRowsStack: some View {
        LazyVStack(spacing: 2) {
            ForEach(entries) { entry in
                decorateEntryView(entry: entry, cornerRadius: 8) {
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(nsImage: IconCache.shared.icon(for: entry))
                                .resizable()
                                .frame(width: 18, height: 18)
                            Text(entry.name)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(LiquidColors.textPrimary)
                        }
                        .onDrag { startDragSession(for: entry) }

                        Spacer(minLength: 8)
                        Text(entry.mediaKind.badgeTitle)
                            .font(.caption2)
                            .foregroundStyle(LiquidColors.textSecondary)
                            .frame(width: 68, alignment: .trailing)
                        Text(entry.formattedSize)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(LiquidColors.textSecondary)
                            .frame(width: 76, alignment: .trailing)
                        Text(entry.formattedDate)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(LiquidColors.textSecondary)
                            .frame(width: 116, alignment: .trailing)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    private var gridCardsStack: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 118, maximum: 152), spacing: 10)], spacing: 10) {
            ForEach(entries) { entry in
                decorateEntryView(entry: entry, cornerRadius: LiquidRadii.control) {
                    VStack(spacing: 6) {
                        VStack(spacing: 6) {
                            WorkspaceThumbStage(entry: entry, size: 84)
                            Text(entry.name)
                                .font(.caption.weight(.medium)).foregroundStyle(LiquidColors.textPrimary)
                                .multilineTextAlignment(.center).lineLimit(2).frame(height: 30, alignment: .top)
                        }
                        .onDrag { startDragSession(for: entry) }
                        Text("\(entry.mediaKind.badgeTitle) · \(entry.formattedSize)")
                            .font(.caption2.monospacedDigit()).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(10)
    }

    private var compactCardsStack: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 6) {
            ForEach(entries) { entry in
                decorateEntryView(entry: entry, cornerRadius: 8) {
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(nsImage: IconCache.shared.icon(for: entry))
                                .resizable()
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.name).font(.caption.weight(.medium)).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
                                Text("\(entry.mediaKind.badgeTitle) · \(entry.formattedSize)")
                                    .font(.caption2.monospacedDigit()).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                            }
                        }
                        .onDrag { startDragSession(for: entry) }
                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private func decorateEntryView<ItemContent: View>(
        entry: FileEntry,
        cornerRadius: CGFloat,
        @ViewBuilder itemContent: () -> ItemContent
    ) -> some View {
        let isSelected = viewModel.activePane == pane && viewModel.selectedEntryIDs.contains(entry.id)
        let isCut = viewModel.isCutPending(entry)
        let isDropHovered = canvas.hoveredDropID == entry.id
        let base = itemContent()
            .opacity(isCut ? 0.54 : 1.0)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? LiquidColors.highlightGlow : (isDropHovered ? Color.cyan.opacity(0.18) : Color.clear))
            }
            .overlay {
                if isDropHovered {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.cyan, lineWidth: 1.6)
                } else if isCut {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.7), style: StrokeStyle(lineWidth: 1.1, dash: [4, 3]))
                } else if isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.58), lineWidth: 1.1)
                }
            }
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: WorkspaceItemFramesKey.self,
                        value: [entry.id: geo.frame(in: .named(spaceName))]
                    )
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onTapGesture(count: 2) {
                viewModel.activePane = pane
                viewModel.openEntry(entry, in: pane)
            }
            .onTapGesture {
                viewModel.handleWorkspaceEntryTap(entry, in: pane, modifiers: NSEvent.modifierFlags)
            }
            .contextMenu {
                WorkspaceEntryContextMenu(viewModel: viewModel, pane: pane, entry: entry)
            }

        if entry.isDirectory && !entry.isPackage {
            base.onDrop(
                of: [UTType.fileURL],
                delegate: WorkspaceDropTargetDelegate(viewModel: viewModel, canvas: canvas, destinationURL: entry.url, targetID: entry.id, targetPane: pane)
            )
        } else {
            base
        }
    }

    private func startDragSession(for entry: FileEntry) -> NSItemProvider {
        canvas.beginItemDrag(viewModel: viewModel)
        _ = viewModel.prepareDragURLs(for: entry, in: pane)
        return NSItemProvider(object: entry.url as NSURL)
    }
}
