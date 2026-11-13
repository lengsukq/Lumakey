import AppKit
import LumakeyCore
import SwiftUI

struct WorkspaceEntryContextMenu: View {
    @ObservedObject var viewModel: AppViewModel
    let pane: PaneSide
    let entry: FileEntry

    var body: some View {
        let targets = viewModel.contextTargetEntries(for: entry, in: pane)
        let isBatch = targets.count > 1

        Button(openTitle(isBatch: isBatch, count: targets.count)) {
            selectTargetsIfNeeded(targets)
            viewModel.openEntries(targets, in: pane)
        }

        if !isBatch {
            mediaSpecificButtons
        }

        Divider()

        Button(isBatch ? "复制 \(targets.count) 项 (⌘C)" : "复制 (⌘C)") {
            selectTargetsIfNeeded(targets)
            viewModel.copyEntriesToWorkspaceClipboard(targets, cut: false)
        }
        Button(isBatch ? "剪切 \(targets.count) 项 (⌘X)" : "剪切 (⌘X)") {
            selectTargetsIfNeeded(targets)
            viewModel.copyEntriesToWorkspaceClipboard(targets, cut: true)
        }
        Button(isBatch ? "原地创建 \(targets.count) 项副本 (⌘D)" : "原地创建副本 (⌘D)") {
            selectTargetsIfNeeded(targets)
            viewModel.duplicateEntriesInPlace(targets, in: pane)
        }

        if !isBatch && entry.isDirectory && !entry.isPackage, let clip = viewModel.workspaceClipboard, !clip.isEmpty {
            let verb = clip.mode == .cutMove ? "移动" : "粘贴"
            Button("\(verb) \(clip.urls.count) 项到此文件夹") {
                viewModel.pasteWorkspaceClipboard(to: entry.url, in: pane, forceMove: false)
            }
        } else if let clip = viewModel.workspaceClipboard, !clip.isEmpty {
            let verb = clip.mode == .cutMove ? "移动" : "粘贴"
            Button("\(verb) \(clip.urls.count) 项到当前目录 (⌘V)") {
                viewModel.pasteWorkspaceClipboard(in: pane, forceMove: false)
            }
        }

        Divider()

        if viewModel.layoutMode == .dual {
            let otherLabel = pane == .left ? "右栏" : "左栏"
            Button("移动到\(otherLabel)") {
                selectTargetsIfNeeded(targets)
                viewModel.transferToOtherPane(entries: targets, copy: false, from: pane)
            }
            Button("复制到\(otherLabel)") {
                selectTargetsIfNeeded(targets)
                viewModel.transferToOtherPane(entries: targets, copy: true, from: pane)
            }
        }
        Button("移动到…") {
            selectTargetsIfNeeded(targets)
            viewModel.chooseDirectoryAndTransfer(entries: targets, copy: false, sourcePane: pane)
        }
        Button("复制到…") {
            selectTargetsIfNeeded(targets)
            viewModel.chooseDirectoryAndTransfer(entries: targets, copy: true, sourcePane: pane)
        }

        Divider()

        if !isBatch {
            Button("重命名… (↩)") { viewModel.beginSingleRename(entry, in: pane) }
        }
        Button("批量重命名…") {
            selectTargetsIfNeeded(targets)
            viewModel.showBatchRenameSheet = true
        }
        Button("新建文件夹… (⇧⌘N)") { viewModel.beginCreateFolder(in: pane) }

        Divider()

        Button("在访达中显示") {
            NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.url))
        }
        Button(isBatch ? "复制选中项路径" : "复制完整路径") {
            NSPasteboard.general.clearContents()
            let joined = targets.map(\.url.path).joined(separator: "\n")
            NSPasteboard.general.setString(joined, forType: .string)
            viewModel.serviceMessage = "已复制路径"
        }

        Divider()

        Button(isBatch ? "移入废纸篓 (\(targets.count) 项) (⌘⌫)" : "移入废纸篓 (⌘⌫)", role: .destructive) {
            selectTargetsIfNeeded(targets)
            viewModel.trashEntries(targets, in: pane)
        }
    }

    @ViewBuilder
    private var mediaSpecificButtons: some View {
        if entry.mediaKind == .image {
            Button("贴图钉在屏幕（图片置顶）") { PinWindowController.shared.pinImage(at: entry.url) }
            Button("大图窗口置顶查看") { viewModel.openMediaWindow(for: entry.url, kind: .image, pinOnTop: true) }
        } else if entry.mediaKind == .video {
            Button("影院播放（同目录播放列表）") { viewModel.openMediaWindow(for: entry.url, kind: .video, pinOnTop: false) }
            Button("视频窗口置顶播放") { viewModel.openMediaWindow(for: entry.url, kind: .video, pinOnTop: true) }
        } else if entry.mediaKind == .markdown || entry.mediaKind == .text {
            Button("独立窗口阅读") { viewModel.openMediaWindow(for: entry.url, kind: entry.mediaKind) }
        }
    }

    private func openTitle(isBatch: Bool, count: Int) -> String {
        if isBatch { return "打开选中的 \(count) 项" }
        return (entry.isDirectory && !entry.isPackage) ? "进入目录" : "打开"
    }

    private func selectTargetsIfNeeded(_ targets: [FileEntry]) {
        viewModel.activePane = pane
        if targets.count == 1, !viewModel.selectedEntryIDs.contains(targets[0].id) {
            viewModel.selectedEntryIDs = [targets[0].id]
            viewModel.selectionAnchorID = targets[0].id
            viewModel.selectedEntry = targets[0]
        }
    }
}

struct WorkspaceCanvasContextMenu: View {
    @ObservedObject var viewModel: AppViewModel
    let pane: PaneSide
    let state: PaneState

    var body: some View {
        Button("新建文件夹… (⇧⌘N)") { viewModel.beginCreateFolder(in: pane) }

        if let clip = viewModel.workspaceClipboard, !clip.isEmpty {
            Divider()
            let verb = clip.mode == .cutMove ? "移动" : "粘贴"
            Button("\(verb) \(clip.urls.count) 项到此处 (⌘V)") {
                viewModel.pasteWorkspaceClipboard(to: state.currentDirectory, in: pane, forceMove: false)
            }
            if clip.mode == .copy {
                Button("移动 \(clip.urls.count) 项到此处 (⌘⌥V)") {
                    viewModel.pasteWorkspaceClipboard(to: state.currentDirectory, in: pane, forceMove: true)
                }
            }
        }

        Divider()

        if !state.visibleEntries.isEmpty {
            Button("全选当前目录 (⌘A)") {
                viewModel.activePane = pane
                viewModel.selectAllInActivePane()
            }
        }
        Button("刷新当前目录") {
            viewModel.refreshDirectory(pane: pane, forceRescan: true)
        }
        Button("在访达中打开此目录") {
            NSWorkspace.shared.open(state.currentDirectory)
        }
    }
}
