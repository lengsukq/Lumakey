import AppKit
import Foundation
import LumakeyCore

extension AppViewModel {
    func startPreview(for entry: FileEntry) {
        previewTask?.cancel(); hashTask?.cancel()
        computedSHA256 = nil; isComputingSHA256 = false; ocrResultText = ""; barcodeResults = []
        previewState = .loading(entry)
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(65))
            guard !Task.isCancelled else { return }
            switch entry.mediaKind {
            case .image:
                let loaded = await Task.detached(priority: .userInitiated) {
                    (MediaClassifier.makeThumbnail(at: entry.url), MediaClassifier.readImageDimensions(at: entry.url))
                }.value
                guard !Task.isCancelled else { return }
                previewState = loaded.0.map { .image(entry, $0, loaded.1) } ?? .folderOrGeneric(entry)
            case .video, .audio: previewState = .videoOrAudio(entry)
            case .pdf: previewState = .pdf(entry)
            case .markdown:
                let loaded = await Task.detached(priority: .userInitiated) {
                    let doc = MediaClassifier.loadDocumentText(at: entry.url, maxBytes: 32_768)
                    let parsed = MarkdownDocumentParser.parse(doc.text)
                    return (parsed, doc.isTruncated)
                }.value
                guard !Task.isCancelled else { return }
                previewState = .markdown(entry, loaded.0, loaded.1)
            case .text:
                let loaded = await Task.detached(priority: .userInitiated) { MediaClassifier.loadTextPreview(at: entry.url) }.value
                guard !Task.isCancelled else { return }
                previewState = .text(entry, loaded.text, loaded.isTruncated)
            case .folder, .archive, .other: previewState = .folderOrGeneric(entry)
            }
        }
    }

    func computeSHA256ForSelection() {
        guard let entry = selectedEntry, !entry.isDirectory else { return }
        hashTask?.cancel(); isComputingSHA256 = true; computedSHA256 = nil
        let targetURL = entry.url
        hashTask = Task {
            let result = await Task.detached(priority: .utility) { try? DirectoryScanner.computeSHA256(for: targetURL) }.value
            guard !Task.isCancelled else { return }
            isComputingSHA256 = false; computedSHA256 = result ?? "计算失败"
        }
    }

    var batchRenameTargets: [FileEntry] {
        let visible = activePaneState.visibleEntries
        let picked = visible.filter { selectedEntryIDs.contains($0.id) }
        if !picked.isEmpty { return picked }
        if let selectedEntry { return [selectedEntry] }
        return Array(visible.prefix(20))
    }

    var batchRenamePreview: [BatchRenamePreviewItem] {
        BatchRenamePlanner.plan(entries: batchRenameTargets, rule: renameRule)
    }

    func applyBatchRename() {
        do {
            try BatchRenamePlanner.apply(batchRenamePreview)
            showBatchRenameSheet = false
            refreshDirectory(pane: activePane)
            serviceMessage = "已完成批量重命名。"
        } catch let err as LumakeyError { diagnostic = err.diagnostic }
        catch { diagnostic = UserFacingDiagnostic(title: "重命名失败", reason: error.localizedDescription, dataSafety: "请检查权限。", nextStep: "重试。") }
    }

    func refreshLocations() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Desktop")
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Downloads")
        let seedVolumes = cachedVolumes.filter { $0.mountPath != "/" }
        locations = Self.buildLocationItems(home: home, desktop: desktop, downloads: downloads, volumes: seedVolumes)

        locationRefreshTask?.cancel()
        locationRefreshTask = Task { [weak self] in
            let detected = await Task.detached(priority: .userInitiated) {
                (volumes: VolumeInspector.mountedVolumes(), tooling: HostToolingStatus.detect())
            }.value
            guard !Task.isCancelled, let self else { return }
            self.cachedVolumes = detected.volumes
            self.toolingStatus = detected.tooling
            self.locations = Self.buildLocationItems(
                home: home,
                desktop: desktop,
                downloads: downloads,
                volumes: detected.volumes.filter { $0.mountPath != "/" }
            )
        }
    }

    private static func buildLocationItems(
        home: URL,
        desktop: URL,
        downloads: URL,
        volumes: [VolumeSummary]
    ) -> [LocationItem] {
        var items: [LocationItem] = [
            LocationItem(name: "个人目录", url: home, kind: .home, volumeSummary: VolumeInspector.inspect(url: home)),
            LocationItem(name: "桌面", url: desktop, kind: .desktop),
            LocationItem(name: "下载", url: downloads, kind: .downloads)
        ]
        for volume in volumes {
            let url = URL(fileURLWithPath: volume.mountPath)
            let kind: LocationKind = volume.formatKind == .smb ? .network : .external
            items.append(LocationItem(name: volume.name, url: url, kind: kind, volumeSummary: volume))
        }
        return items
    }

    func refreshDirectory(pane: PaneSide, forceRescan: Bool = false) {
        let state = pane == .left ? leftPane : rightPane
        let url = state.currentDirectory
        let includeHidden = state.showHidden
        let sortField = state.sortField
        let sortOrder = state.sortOrder
        let foldersFirst = state.foldersFirst

        (pane == .left ? leftDirectoryTask : rightDirectoryTask)?.cancel()

        if !forceRescan, let cached = directoryCache.lookup(for: url, includeHidden: includeHidden) {
            let sorted = DirectoryScanner.sortEntries(cached.entries, by: sortField, order: sortOrder, foldersFirst: foldersFirst)
            mutatePane(pane) { $0.entries = sorted; $0.volumeSummary = cached.volumeSummary; $0.diagnostic = nil }
            if !directoryCache.needsBackgroundRevalidation(for: url, cached: cached) {
                mutatePane(pane) { $0.isScanning = false }
                return
            }
        }

        mutatePane(pane) { $0.isScanning = true; $0.diagnostic = nil }
        let cache = directoryCache
        let task = Task { [weak self] in
            let outcome: Result<([FileEntry], VolumeSummary?, Date?), Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let summary = VolumeInspector.inspect(url: url)
                    let skipTags = summary.map { VolumeInspector.isSlowOrRemoteVolume($0) } ?? false
                    let scanned = try DirectoryScanner.scanDirectory(
                        at: url, includeHidden: includeHidden, skipExtendedTags: skipTags
                    )
                    let mtime = DirectoryScanner.directoryModificationDate(at: url)
                    let sorted = DirectoryScanner.sortEntries(scanned, by: sortField, order: sortOrder, foldersFirst: foldersFirst)
                    return .success((sorted, summary, mtime))
                } catch {
                    return .failure(error)
                }
            }.value

            guard !Task.isCancelled, let self else { return }
            let latest = pane == .left ? self.leftPane : self.rightPane
            guard latest.currentDirectory.standardizedFileURL.path == url.standardizedFileURL.path else { return }

            switch outcome {
            case .success(let (sorted, summary, mtime)):
                cache.store(entries: sorted, volumeSummary: summary, for: url, includeHidden: includeHidden, directoryMTime: mtime)
                self.mutatePane(pane) { $0.entries = sorted; $0.volumeSummary = summary; $0.diagnostic = nil; $0.isScanning = false }
            case .failure(let err as LumakeyError):
                self.mutatePane(pane) { $0.entries = []; $0.diagnostic = err.diagnostic; $0.isScanning = false }
            case .failure(let err):
                self.mutatePane(pane) {
                    $0.entries = []
                    $0.isScanning = false
                    $0.diagnostic = UserFacingDiagnostic(title: "读取目录失败", reason: err.localizedDescription, dataSafety: "未改动原文件。", nextStep: "请检查路径权限或重试。")
                }
            }
        }
        if pane == .left { leftDirectoryTask = task } else { rightDirectoryTask = task }
    }

    func ensureWorkspaceLoaded() {
        guard !hasLoadedWorkspace else { return }
        hasLoadedWorkspace = true
        refreshLocations()
        refreshDirectory(pane: .left)
        refreshDirectory(pane: .right)
    }

    func releaseWorkspaceMemory() {
        previewTask?.cancel(); hashTask?.cancel()
        leftDirectoryTask?.cancel(); rightDirectoryTask?.cancel(); locationRefreshTask?.cancel()
        previewState = .empty; selectedEntry = nil; selectedEntryIDs = []
        directoryCache.trimKeepingRecent(16)
        WorkspaceThumbnailCache.shared.clearAll()
        leftPane.entries = []; rightPane.entries = []
        leftPane.isScanning = false; rightPane.isScanning = false
        hasLoadedWorkspace = false
        MemoryStats.reclaimFreeHeapPages()
    }

    func reclaimAllIdleMemoryNow() {
        ProcessSupervisor.shared.terminateAll()
        stopIndexWatcher()
        everythingIndexTask?.cancel(); searchTask?.cancel(); previewTask?.cancel(); hashTask?.cancel()
        leftDirectoryTask?.cancel(); rightDirectoryTask?.cancel(); locationRefreshTask?.cancel()
        previewState = .empty
        everythingIndex = nil; displayedCandidates = []
        directoryCache.clear()
        WorkspaceThumbnailCache.shared.clearAll()
        IconCache.shared.clearAll()
        MemoryStats.reclaimFreeHeapPages()
        let mb = String(format: "%.1f MB", MemoryStats.currentPhysicalFootprintMB())
        serviceMessage = "已释放空闲内存 · 当前物理占用 \(mb)"
    }

    func refreshCachedVolumes(triggerReindexIfAllVolumes: Bool = false) {
        Task {
            let vols = await Task.detached(priority: .utility) { VolumeInspector.mountedVolumes() }.value
            let changed = Set(vols.map(\.mountPath)) != Set(self.cachedVolumes.map(\.mountPath))
            self.cachedVolumes = vols
            if self.hasLoadedWorkspace { self.refreshLocations() }
            if triggerReindexIfAllVolumes && changed && self.everythingScope == .allVolumes {
                if self.needsEverythingIndexResident || self.everythingIndex != nil {
                    self.rebuildEverythingIndex(scope: .allVolumes)
                } else {
                    self.primeEverythingIndexOnStartup(scope: .allVolumes)
                }
            }
        }
    }

    func installVolumeObservers() {
        removeVolumeObservers()
        let center = NSWorkspace.shared.notificationCenter
        let mountObs = center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshCachedVolumes(triggerReindexIfAllVolumes: true) }
        }
        let unmountObs = center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshCachedVolumes(triggerReindexIfAllVolumes: true) }
        }
        volumeObservers = [mountObs, unmountObs]
    }

    func removeVolumeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for obs in volumeObservers { center.removeObserver(obs) }
        volumeObservers.removeAll()
    }
}
