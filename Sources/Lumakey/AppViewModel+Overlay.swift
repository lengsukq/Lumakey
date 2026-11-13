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
        searchTask?.cancel(); previewTask?.cancel(); hashTask?.cancel()
        previewState = .empty; displayedCandidates = []
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
                emptyHits = plugins.filter(\.isValid).prefix(50).enumerated().map { idx, plugin in
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
                    launchCounts: countsSnapshot
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
            if inlineResultBody != nil {
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

    func executeCandidate(_ candidate: LauncherCandidate) {
        switch candidate.kind {
        case .app(let app):
            launchApp(app)
        case .calculator(_, let result, _):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result, forType: .string)
            serviceMessage = "已复制结果：\(result)"
            if !isOverlayPinned { onHideOverlayRequest?() }
        case .fileHit(let hit):
            executeEverythingHit(hit)
        case .clipboard(let entry):
            executeClipboardEntry(entry)
        case .plugin(let plugin):
            runPlugin(plugin, query: overlayQuery, showInline: true)
        case .command(let cmd):
            executeSystemCommand(cmd.command)
        }
    }

    func openCandidateInDedicatedWindow(_ candidate: LauncherCandidate) {
        if case .fileHit(let hit) = candidate.kind {
            openMediaWindow(for: hit.url, kind: hit.mediaKind)
        } else if case .clipboard(let clip) = candidate.kind, case .image(let url, _) = clip.payloadKind {
            openMediaWindow(for: url, kind: .image)
        }
    }

    func openMediaWindow(for url: URL, kind: PreviewMediaKind, siblings: [URL]? = nil, pinOnTop: Bool = false) {
        PreviewPlaybackRegistry.shared.pauseAll()
        switch kind {
        case .markdown, .text:
            let list = siblings ?? MediaClassifier.siblingMediaURLs(around: url, matching: [.markdown, .text])
            openRoute(.documentReader(url, list))
        case .image:
            let list = siblings ?? MediaClassifier.siblingMediaURLs(around: url, matching: [.image])
            openRoute(.imageViewer(url, list, pinOnTop))
        case .video:
            let list = siblings ?? MediaClassifier.siblingMediaURLs(around: url, matching: [.video])
            openRoute(.videoPlayer(url, list, pinOnTop))
        default:
            NSWorkspace.shared.open(url)
            if !isOverlayPinned { onHideOverlayRequest?() }
        }
    }

    func launchApp(_ app: InstalledAppItem) {
        appLaunchCounts[app.id, default: 0] += 1
        NSWorkspace.shared.open(app.url)
        if !isOverlayPinned { onHideOverlayRequest?() }
    }

    func executeEverythingHit(_ hit: EverythingSearchHit) {
        if hit.isDirectory {
            navigate(pane: activePane, to: hit.url)
            openRoute(.workspace)
        } else if [.markdown, .text, .image, .video].contains(hit.mediaKind) {
            openMediaWindow(for: hit.url, kind: hit.mediaKind)
        } else {
            NSWorkspace.shared.open(hit.url)
            if !isOverlayPinned { onHideOverlayRequest?() }
        }
    }

    func revealSelectedInFinder() {
        guard let selected = selectedCandidate else { return }
        switch selected.kind {
        case .fileHit(let hit): NSWorkspace.shared.activateFileViewerSelecting([hit.url])
        case .app(let app): NSWorkspace.shared.activateFileViewerSelecting([app.url])
        case .clipboard(let clip):
            if let url = clip.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        default: break
        }
    }

    private func executeSystemCommand(_ command: SystemCommandKind) {
        switch command {
        case .openWelcome: openRoute(.welcome)
        case .openWorkspace: openRoute(.workspace)
        case .openSettings: openRoute(.settings(.general))
        case .openClipboard: prepareOverlay(filter: .clipboard)
        case .openEverything: prepareOverlay(filter: .files)
        case .capturePin: captureAndPinScreenshot()
        case .captureOCR: captureAndAnalyzeOCR()
        case .openTrash: NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
        case .emptyTrash: runAppleScript("tell application \"Finder\" to empty the trash")
        case .lockScreen: runAppleScript("tell application \"System Events\" to keystroke \"q\" using {command down, control down}")
        case .toggleMosEnabled:
            var next = mosConfig; next.enabled.toggle(); applyMosConfig(next)
            serviceMessage = next.enabled ? "Mos 鼠标插件已开启" : "Mos 鼠标插件已关闭"
        case .toggleMosReverse:
            var next = mosConfig; next.reverseWheelDirection.toggle(); applyMosConfig(next)
            serviceMessage = next.reverseWheelDirection ? "已开启物理鼠标滚轮反转" : "已恢复默认滚轮方向"
        case .toggleMosSmooth:
            var next = mosConfig; next.smoothScroll.toggle(); applyMosConfig(next)
            serviceMessage = next.smoothScroll ? "已开启 120Hz 平滑滚动" : "已关闭平滑滚动"
        case .openMosSettings:
            openRoute(.settings(.mos))
        case .toggleSystemMonitor:
            SystemPulseWindowController.shared.toggleFloatingWidget()
            if !isOverlayPinned { onHideOverlayRequest?() }
        case .openNetworkMonitor:
            openRoute(.networkMonitor)
        case .openCacheManager:
            openRoute(.settings(.cache))
        case .reclaimMemory:
            reclaimAllIdleMemoryNow()
        case .inspectPort(let port):
            Task {
                let text = await Task.detached(priority: .userInitiated) { UnitAndCommandEngine.inspectListeningPort(port) }.value
                self.inlineResultTitle = "端口 :\(port) 监听探测"
                self.inlineResultBody = text
            }
        case .openVolume(let url):
            navigate(pane: activePane, to: url); openRoute(.workspace)
        case .webSearch(let engine, let url):
            NSWorkspace.shared.open(url); serviceMessage = "已在浏览器打开 \(engine)"
        }
    }

    private func runAppleScript(_ source: String) {
        if let script = NSAppleScript(source: source) { var err: NSDictionary?; script.executeAndReturnError(&err) }
    }

    func fileEntry(from hit: EverythingSearchHit) -> FileEntry {
        FileEntry(url: hit.url, name: hit.name, isDirectory: hit.isDirectory, sizeBytes: hit.sizeBytes, modifiedAt: hit.modifiedAt, extensionLowercased: hit.url.pathExtension.lowercased(), mediaKind: hit.mediaKind)
    }
}
