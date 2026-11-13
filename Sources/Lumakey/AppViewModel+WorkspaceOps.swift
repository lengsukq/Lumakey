import AppKit
import Foundation
import LumakeyCore

extension AppViewModel {
    func handleWorkspaceKeyShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let code = event.keyCode
        if flags.isEmpty && code == 53 { return escapeWorkspaceSelectionOrClipboard() }
        if flags.isEmpty && code == 36 {
            let picked = selectedEntries(in: activePane)
            guard picked.count == 1 else { return false }
            beginSingleRename(picked[0], in: activePane); return true
        }
        if flags == [.command, .shift] && (key == "n" || code == 45) { beginCreateFolder(in: activePane); return true }
        if flags == [.command, .option] && (key == "v" || code == 9) { pasteWorkspaceClipboard(in: activePane, forceMove: true); return true }
        guard flags == [.command] else { return false }
        if key == "a" || code == 0 { selectAllInActivePane(); return true }
        if key == "c" || code == 8 { copySelectionToWorkspaceClipboard(cut: false); return true }
        if key == "x" || code == 7 { copySelectionToWorkspaceClipboard(cut: true); return true }
        if key == "v" || code == 9 { pasteWorkspaceClipboard(in: activePane, forceMove: false); return true }
        if key == "d" || code == 2 { duplicateSelectionInPlace(); return true }
        if code == 51 || code == 117 { trashSelection(); return true }
        return false
    }

    func beginCreateFolder(in pane: PaneSide) {
        activePane = pane
        let dir = (pane == .left ? leftPane : rightPane).currentDirectory
        do {
            try WorkspaceFileOperations.checkWritableDirectory(dir)
            workspacePrompt.presentCreateFolder(in: pane, directory: dir)
        } catch {
            presentWorkspaceError(error)
        }
    }

    func beginSingleRename(_ entry: FileEntry, in pane: PaneSide) {
        activePane = pane
        selectedEntryIDs = [entry.id]
        selectionAnchorID = entry.id
        selectedEntry = entry
        do {
            try WorkspaceFileOperations.checkWritableDirectory(entry.url.deletingLastPathComponent())
            workspacePrompt.presentSingleRename(entry: entry, in: pane)
        } catch {
            presentWorkspaceError(error)
        }
    }

    func submitWorkspacePrompt() {
        guard let mode = workspacePrompt.activeMode else { return }
        do {
            switch mode {
            case .createFolder(let pane, let dir):
                let created = try WorkspaceFileOperations.createFolder(named: workspacePrompt.inputText, in: dir)
                workspacePrompt.dismiss()
                invalidateAndRefreshAfterFileOp(affectedDirs: [dir], highlightURLs: [created], in: pane, message: "已新建文件夹“\(created.lastPathComponent)”")
            case .renameSingle(let pane, let entry):
                let dir = entry.url.deletingLastPathComponent()
                let renamed = try WorkspaceFileOperations.renameItem(at: entry.url, to: workspacePrompt.inputText)
                workspacePrompt.dismiss()
                invalidateAndRefreshAfterFileOp(affectedDirs: [dir], highlightURLs: [renamed], in: pane, message: "已重命名为“\(renamed.lastPathComponent)”")
            }
        } catch let err as LumakeyError {
            if case .readOnlyVolume = err {
                workspacePrompt.dismiss()
                diagnostic = err.diagnostic
            } else {
                workspacePrompt.inlineError = err.diagnostic.reason
            }
        } catch {
            workspacePrompt.inlineError = error.localizedDescription
        }
    }

    func copyEntriesToWorkspaceClipboard(_ entries: [FileEntry], cut: Bool) {
        guard !entries.isEmpty else { return }
        let urls = entries.map(\.url)
        workspaceClipboard = WorkspaceClipboardState(urls: urls, mode: cut ? .cutMove : .copy)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
        serviceMessage = cut ? "已剪切 \(urls.count) 项，按 ⌘V 移动到目标目录" : "已复制 \(urls.count) 项，按 ⌘V 粘贴（⌘⌥V 移动）"
    }

    func copySelectionToWorkspaceClipboard(cut: Bool) {
        let picked = selectedEntries(in: activePane)
        copyEntriesToWorkspaceClipboard(picked, cut: cut)
    }

    func pasteWorkspaceClipboard(to explicitDir: URL? = nil, in pane: PaneSide? = nil, forceMove: Bool = false) {
        guard let clip = workspaceClipboard, !clip.isEmpty else { return }
        let targetPane = pane ?? activePane
        activePane = targetPane
        let dstDir = explicitDir ?? (targetPane == .left ? leftPane : rightPane).currentDirectory
        let shouldMove = forceMove || clip.mode == .cutMove
        do {
            let sourceDirs = clip.urls.map { $0.deletingLastPathComponent() }
            let resulting: [URL]
            if shouldMove {
                resulting = try WorkspaceFileOperations.moveItems(clip.urls, to: dstDir)
                workspaceClipboard = nil
            } else {
                resulting = try WorkspaceFileOperations.copyItems(clip.urls, to: dstDir)
            }
            let verb = shouldMove ? "已移动" : "已粘贴"
            invalidateAndRefreshAfterFileOp(
                affectedDirs: sourceDirs + [dstDir],
                highlightURLs: resulting,
                in: targetPane,
                message: "\(verb) \(resulting.count) 项至“\(dstDir.lastPathComponent)”"
            )
        } catch {
            presentWorkspaceError(error)
        }
    }

    func duplicateEntriesInPlace(_ entries: [FileEntry], in pane: PaneSide) {
        guard !entries.isEmpty else { return }
        let dir = (pane == .left ? leftPane : rightPane).currentDirectory
        do {
            let created = try WorkspaceFileOperations.copyItems(entries.map(\.url), to: dir)
            invalidateAndRefreshAfterFileOp(affectedDirs: [dir], highlightURLs: created, in: pane, message: "已原地创建 \(created.count) 项副本")
        } catch {
            presentWorkspaceError(error)
        }
    }

    func duplicateSelectionInPlace() {
        duplicateEntriesInPlace(selectedEntries(in: activePane), in: activePane)
    }

    func transferEntries(_ entries: [FileEntry], to destinationDir: URL, copy: Bool, highlightPane: PaneSide) {
        guard !entries.isEmpty else { return }
        handleDroppedURLs(entries.map(\.url), to: destinationDir, copy: copy, targetPane: highlightPane)
    }

    func transferToOtherPane(entries: [FileEntry], copy: Bool, from sourcePane: PaneSide) {
        let otherPane: PaneSide = sourcePane == .left ? .right : .left
        let dstDir = (otherPane == .left ? leftPane : rightPane).currentDirectory
        transferEntries(entries, to: dstDir, copy: copy, highlightPane: otherPane)
    }

    func chooseDirectoryAndTransfer(entries: [FileEntry], copy: Bool, sourcePane: PaneSide) {
        guard !entries.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = copy ? "选择目标文件夹以复制 \(entries.count) 项" : "选择目标文件夹以移动 \(entries.count) 项"
        panel.prompt = copy ? "复制到此处" : "移动到此处"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = (sourcePane == .left ? leftPane : rightPane).currentDirectory
        if panel.runModal() == .OK, let targetURL = panel.url {
            transferEntries(entries, to: targetURL, copy: copy, highlightPane: sourcePane)
        }
    }

    func trashEntries(_ entries: [FileEntry], in pane: PaneSide) {
        guard !entries.isEmpty else { return }
        let urls = entries.map(\.url)
        let dirs = urls.map { $0.deletingLastPathComponent() }
        do {
            _ = try WorkspaceFileOperations.trashItems(urls)
            if let clip = workspaceClipboard {
                let trashedPaths = Set(urls.map { $0.standardizedFileURL.path })
                let remaining = clip.urls.filter { !trashedPaths.contains($0.standardizedFileURL.path) }
                workspaceClipboard = remaining.isEmpty ? nil : WorkspaceClipboardState(urls: remaining, mode: clip.mode)
            }
            clearWorkspaceSelection(in: pane)
            invalidateAndRefreshAfterFileOp(affectedDirs: dirs, highlightURLs: [], in: pane, message: "已安全移入系统废纸篓（\(urls.count) 项）")
        } catch {
            presentWorkspaceError(error)
        }
    }

    func trashSelection() {
        trashEntries(selectedEntries(in: activePane), in: activePane)
    }

    func handleDroppedURLs(_ urls: [URL], to destinationDir: URL, copy: Bool, targetPane: PaneSide) {
        activeDragURLs = []
        guard !urls.isEmpty else { return }
        let sourceDirs = urls.map { $0.deletingLastPathComponent() }
        do {
            let resulting = copy
                ? try WorkspaceFileOperations.copyItems(urls, to: destinationDir)
                : try WorkspaceFileOperations.moveItems(urls, to: destinationDir)
            let verb = copy ? "已复制" : "已移动"
            invalidateAndRefreshAfterFileOp(
                affectedDirs: sourceDirs + [destinationDir],
                highlightURLs: resulting,
                in: targetPane,
                message: "\(verb) \(resulting.count) 项至“\(destinationDir.lastPathComponent)”"
            )
        } catch {
            presentWorkspaceError(error)
        }
    }

    func invalidateAndRefreshAfterFileOp(affectedDirs: [URL], highlightURLs: [URL], in pane: PaneSide, message: String) {
        for dir in WorkspaceFileOperations.deduplicateURLs(affectedDirs + [leftPane.currentDirectory, rightPane.currentDirectory]) {
            directoryCache.invalidate(directoryURL: dir)
        }
        let targetDir = (pane == .left ? leftPane : rightPane).currentDirectory.standardizedFileURL.path
        let matchingIDs = Set(
            highlightURLs
                .filter { $0.deletingLastPathComponent().standardizedFileURL.path == targetDir }
                .map { $0.standardizedFileURL.path }
        )
        if !matchingIDs.isEmpty {
            activePane = pane
            selectedEntryIDs = matchingIDs
            selectionAnchorID = matchingIDs.first
        }
        refreshDirectory(pane: .left, forceRescan: true)
        refreshDirectory(pane: .right, forceRescan: true)
        serviceMessage = message
    }

    private func presentWorkspaceError(_ error: Error) {
        if let lmErr = error as? LumakeyError {
            diagnostic = lmErr.diagnostic
        } else {
            diagnostic = UserFacingDiagnostic(
                title: "文件操作未完成",
                reason: error.localizedDescription,
                dataSafety: "未覆盖现有文件。",
                nextStep: "请检查磁盘空间与目录读写权限后重试。"
            )
        }
    }
}
