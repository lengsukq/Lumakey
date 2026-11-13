import AppKit
import Foundation
import LumakeyCore

extension AppViewModel {
    func prepareOverlay(filter: OmniFilter) {
        indexUnloadTask?.cancel()
        indexUnloadTask = nil
        isOverlayVisible = true
        omniFilter = filter
        overlaySelectedIndex = 0
        inlineResultBody = nil
        inlinePluginViewPayload = nil
        activeInlinePlugin = nil
        capturePasteboardOnceIfChanged()
        IconCache.shared.prewarmDockIcons(cachedDockApps)
        let hasQuery = !overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if everythingIndex == nil && !isIndexingEverything && (filter == .files || hasQuery) {
            rebuildEverythingIndex(scope: everythingScope)
        }
        refreshDisplayedCandidates()
        bumpFocusToken()
    }

    func setOmniFilter(_ filter: OmniFilter) {
        prepareOverlay(filter: filter)
    }

    func bumpFocusToken() { focusToken += 1 }
    func showOverlay(filter: OmniFilter) { onShowOverlayRequest?(filter) }
    func recenterFloatingPanel() { onRecenterFloatingPanel?() }
    func openRoute(_ route: WindowRoute) {
        if case .workspace = route {} else { PreviewPlaybackRegistry.shared.pauseAll() }
        onRouteRequest?(route)
    }

    func setDockIconVisible(_ visible: Bool) {
        showDockIcon = visible
        onDockVisibilityChanged?(visible)
    }

    func handleOverlayHidden() {
        isOverlayVisible = false
        searchTask?.cancel(); previewTask?.cancel(); hashTask?.cancel(); pluginRunTask?.cancel()
        previewState = .empty; displayedCandidates = []
        inlinePluginViewPayload = nil; activeInlinePlugin = nil
        ProcessSupervisor.shared.terminateAll()

        indexUnloadTask?.cancel()
        indexUnloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled, let self, !self.isOverlayVisible, self.everythingIndex != nil else { return }
            self.stopIndexWatcher()
            self.everythingIndex = nil
            self.displayedCandidates = []
            MemoryStats.reclaimFreeHeapPages()
        }
    }

    func handleOverlayQueryChanged() {
        overlaySelectedIndex = 0
        if isOverlayVisible, everythingIndex == nil, !isIndexingEverything,
           !overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rebuildEverythingIndex(scope: everythingScope)
        }
        refreshDisplayedCandidates()
    }

    func refreshDisplayedCandidates() {
        guard isOverlayVisible else { return }
        searchTask?.cancel()
        let trimmed = overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentFilter = omniFilter
        let scopedClipboard = currentFilter == .clipboard
            ? ClipboardService.filter(clipboardItems, query: "", category: clipboardCategory)
            : clipboardItems

        if trimmed.isEmpty {
            let emptyHits: [LauncherCandidate]
            switch currentFilter {
            case .all:
                emptyHits = []
            case .clipboard:
                emptyHits = scopedClipboard.prefix(50).enumerated().map { idx, item in
                    LauncherCandidate(id: "clip:\(item.id.uuidString)", score: 9_300 - idx, kind: .clipboard(item))
                }
            case .plugins:
                emptyHits = plugins.filter { $0.isValid && $0.isEnabled }.prefix(50).enumerated().map { idx, plugin in
                    LauncherCandidate(id: "plugin:\(plugin.id)", score: 6_200 - idx, kind: .plugin(plugin))
                }
            case .files:
                emptyHits = (everythingIndex?.search(queryText: "", limit: 40) ?? []).enumerated().map { idx, hit in
                    LauncherCandidate(id: "file:\(hit.id)", score: 9_400 - idx, kind: .fileHit(hit))
                }
            }
            displayedCandidates = emptyHits
            overlaySelectedIndex = 0
            syncOverlayPreviewToSelection()
            return
        }

        let appsSnapshot = installedApps
        let pluginsSnapshot = plugins
        let volumesSnapshot = cachedVolumes
        let indexSnapshot = everythingIndex
        let countsSnapshot = appLaunchCounts
        let usageBoostsSnapshot = AppUsageTrackerController.shared.rankingBoosts(for: appsSnapshot)
        let clipTextSnapshot = clipboardItems.first(where: { $0.textValue != nil })?.textValue
            ?? NSPasteboard.general.string(forType: .string)

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }
            let ranked = await Task.detached(priority: .userInitiated) {
                LauncherEngine.rankCandidates(
                    query: trimmed,
                    filter: currentFilter,
                    apps: appsSnapshot,
                    plugins: pluginsSnapshot,
                    clipboardItems: scopedClipboard,
                    volumes: volumesSnapshot,
                    everythingIndex: indexSnapshot,
                    launchCounts: countsSnapshot,
                    usageBoosts: usageBoostsSnapshot,
                    clipboardText: clipTextSnapshot
                )
            }.value
            guard !Task.isCancelled else { return }
            self.displayedCandidates = Array(ranked.prefix(50))
            self.overlaySelectedIndex = 0
            self.syncOverlayPreviewToSelection()
        }
    }

    func handleOverlayKeyAction(_ action: OverlayKeyAction) {
        switch action {
        case .moveUp:
            overlaySelectedIndex = max(0, overlaySelectedIndex - 1)
            syncOverlayPreviewToSelection()
        case .moveDown:
            let maxIndex = max(0, min(displayedCandidates.count, 50) - 1)
            overlaySelectedIndex = min(maxIndex, overlaySelectedIndex + 1)
            syncOverlayPreviewToSelection()
        case .submit:
            guard let candidate = selectedCandidate else { return }
            executeCandidate(candidate)
        case .escape:
            if inlinePluginViewPayload != nil {
                inlinePluginViewPayload = nil
                activeInlinePlugin = nil
            } else if inlineResultBody != nil {
                inlineResultBody = nil
            } else if !overlayQuery.isEmpty {
                overlayQuery = ""
            } else if omniFilter != .all {
                setOmniFilter(.all)
            } else {
                onHideOverlayRequest?()
            }
        case .cycleMode:
            setOmniFilter(omniFilter.next)
        case .togglePreview:
            showOverlayLens.toggle()
            syncOverlayPreviewToSelection()
        case .revealInFinder:
            revealSelectedInFinder()
        case .openSettings:
            openRoute(.settings(.general))
        }
    }

    func syncOverlayPreviewToSelection() {
        guard effectiveLensVisible else { return }
        if let selected = selectedCandidate, case .fileHit(let hit) = selected.kind {
            startPreview(for: fileEntry(from: hit))
        } else {
            previewTask?.cancel()
            previewState = .empty
        }
    }

    func fileEntry(from hit: EverythingSearchHit) -> FileEntry {
        FileEntry(
            url: hit.url,
            name: hit.name,
            isDirectory: hit.isDirectory,
            sizeBytes: hit.sizeBytes,
            modifiedAt: hit.modifiedAt,
            extensionLowercased: hit.url.pathExtension.lowercased(),
            mediaKind: hit.mediaKind
        )
    }
}
