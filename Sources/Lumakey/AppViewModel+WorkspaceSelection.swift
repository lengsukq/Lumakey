import AppKit
import Foundation
import LumakeyCore

extension AppViewModel {
    func selectEntry(_ entry: FileEntry) {
        selectedEntry = entry
        selectionAnchorID = entry.id
        if !selectedEntryIDs.contains(entry.id) { selectedEntryIDs = [entry.id] }
        startPreview(for: entry)
    }

    func handleWorkspaceEntryTap(
        _ entry: FileEntry,
        in pane: PaneSide,
        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags
    ) {
        let switchedPane = activePane != pane
        activePane = pane
        let visible = (pane == .left ? leftPane : rightPane).visibleEntries
        let visibleIDSet = Set(visible.map(\.id))
        if switchedPane {
            selectedEntryIDs = selectedEntryIDs.intersection(visibleIDSet)
            selectionAnchorID = nil
        } else {
            selectedEntryIDs = selectedEntryIDs.intersection(visibleIDSet)
        }

        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift), let targetIdx = visible.firstIndex(where: { $0.id == entry.id }) {
            let anchorIdx = selectionAnchorID.flatMap { anchor in visible.firstIndex(where: { $0.id == anchor }) }
                ?? selectedEntry.flatMap { sel in visible.firstIndex(where: { $0.id == sel.id }) }
                ?? targetIdx
            let lo = min(anchorIdx, targetIdx)
            let hi = max(anchorIdx, targetIdx)
            let rangeIDs = Set(visible[lo...hi].map(\.id))
            if flags.contains(.command) {
                selectedEntryIDs.formUnion(rangeIDs)
            } else {
                selectedEntryIDs = rangeIDs
            }
            if selectionAnchorID == nil || !visibleIDSet.contains(selectionAnchorID ?? "") {
                selectionAnchorID = visible[anchorIdx].id
            }
            selectedEntry = entry
            startPreview(for: entry)
            return
        }

        if flags.contains(.command) {
            if selectedEntryIDs.contains(entry.id) {
                selectedEntryIDs.remove(entry.id)
                if selectedEntry?.id == entry.id {
                    if let fallback = visible.first(where: { selectedEntryIDs.contains($0.id) }) {
                        selectedEntry = fallback
                        startPreview(for: fallback)
                    } else {
                        selectedEntry = nil
                        previewState = .empty
                    }
                }
            } else {
                selectedEntryIDs.insert(entry.id)
                selectionAnchorID = entry.id
                selectedEntry = entry
                startPreview(for: entry)
            }
            return
        }

        selectedEntryIDs = [entry.id]
        selectionAnchorID = entry.id
        selectedEntry = entry
        startPreview(for: entry)
    }

    func applyMarqueeSelection(ids: Set<String>, in pane: PaneSide) {
        activePane = pane
        let visible = (pane == .left ? leftPane : rightPane).visibleEntries
        let validIDs = ids.intersection(Set(visible.map(\.id)))
        guard validIDs != selectedEntryIDs else { return }
        selectedEntryIDs = validIDs
        if let firstMatch = visible.first(where: { validIDs.contains($0.id) }) {
            if selectedEntry == nil || !validIDs.contains(selectedEntry?.id ?? "") {
                selectedEntry = firstMatch
                startPreview(for: firstMatch)
            }
            if selectionAnchorID == nil || !validIDs.contains(selectionAnchorID ?? "") {
                selectionAnchorID = firstMatch.id
            }
        } else {
            selectedEntry = nil
            previewState = .empty
        }
    }

    func selectAllInActivePane() {
        let visible = activePaneState.visibleEntries
        guard !visible.isEmpty else { return }
        selectedEntryIDs = Set(visible.map(\.id))
        if selectedEntry == nil || !selectedEntryIDs.contains(selectedEntry?.id ?? "") {
            selectedEntry = visible.first
            if let first = visible.first { startPreview(for: first) }
        }
        selectionAnchorID = visible.first?.id
    }

    func clearWorkspaceSelection(in pane: PaneSide? = nil) {
        if let pane { activePane = pane }
        selectedEntryIDs.removeAll()
        selectedEntry = nil
        selectionAnchorID = nil
        previewState = .empty
    }

    func escapeWorkspaceSelectionOrClipboard() -> Bool {
        if !selectedEntryIDs.isEmpty {
            clearWorkspaceSelection()
            return true
        }
        if workspaceClipboard != nil {
            workspaceClipboard = nil
            serviceMessage = "已取消待粘贴/剪切状态"
            return true
        }
        return false
    }

    func selectedEntries(in pane: PaneSide) -> [FileEntry] {
        guard activePane == pane, !selectedEntryIDs.isEmpty else { return [] }
        let visible = (pane == .left ? leftPane : rightPane).visibleEntries
        return visible.filter { selectedEntryIDs.contains($0.id) }
    }

    func selectionSummaryText(in pane: PaneSide) -> String? {
        let picked = selectedEntries(in: pane)
        guard !picked.isEmpty else { return nil }
        let totalBytes = picked.reduce(Int64(0)) { acc, item in
            acc + ((item.isDirectory && !item.isPackage) ? 0 : max(0, item.sizeBytes))
        }
        return "已选中 \(picked.count) 项（合计 \(FastFormatters.formatFileBytes(totalBytes))）"
    }

    func contextTargetEntries(for clickedEntry: FileEntry, in pane: PaneSide) -> [FileEntry] {
        if activePane == pane && selectedEntryIDs.contains(clickedEntry.id) {
            let current = selectedEntries(in: pane)
            if !current.isEmpty { return current }
        }
        return [clickedEntry]
    }

    func isCutPending(_ entry: FileEntry) -> Bool {
        guard let clip = workspaceClipboard, clip.mode == .cutMove else { return false }
        return clip.contains(entry.url)
    }

    func prepareDragURLs(for entry: FileEntry, in pane: PaneSide) -> [URL] {
        if activePane == pane && selectedEntryIDs.contains(entry.id) {
            let urls = selectedEntries(in: pane).map(\.url)
            if !urls.isEmpty {
                activeDragURLs = urls
                return urls
            }
        }
        activePane = pane
        selectedEntryIDs = [entry.id]
        selectionAnchorID = entry.id
        selectedEntry = entry
        activeDragURLs = [entry.url]
        return [entry.url]
    }

    func openEntry(_ entry: FileEntry, in pane: PaneSide) {
        if entry.isDirectory && !entry.isPackage {
            navigate(pane: pane, to: entry.url)
            return
        }
        PreviewPlaybackRegistry.shared.pauseAll()
        let visible = (pane == .left ? leftPane : rightPane).visibleEntries
        switch entry.mediaKind {
        case .image:
            openRoute(.imageViewer(entry.url, visible.filter { $0.mediaKind == .image }.map(\.url), false))
        case .video:
            openRoute(.videoPlayer(entry.url, visible.filter { $0.mediaKind == .video }.map(\.url), false))
        case .markdown, .text:
            openRoute(.documentReader(entry.url, visible.filter { $0.mediaKind == .markdown || $0.mediaKind == .text }.map(\.url)))
        default:
            NSWorkspace.shared.open(entry.url)
        }
    }

    func openEntries(_ entries: [FileEntry], in pane: PaneSide) {
        guard let first = entries.first else { return }
        if entries.count == 1 {
            openEntry(first, in: pane)
            return
        }
        for item in entries { NSWorkspace.shared.open(item.url) }
    }
}
