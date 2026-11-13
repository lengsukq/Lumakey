import Foundation
import LumakeyCore

extension AppViewModel {
    func primeEverythingIndexOnStartup(scope: EverythingScope) {
        everythingIndexTask?.cancel()
        stopIndexWatcher()
        everythingScope = scope
        isIndexingEverything = true

        everythingIndexTask = Task { [weak self] in
            guard let self else { return }
            let externals = await Task.detached(priority: .utility) { VolumeInspector.externalVolumes() }.value
            guard !Task.isCancelled else { return }
            let volumes = await Task.detached(priority: .utility) { VolumeInspector.mountedVolumes() }.value
            guard !Task.isCancelled else { return }
            self.cachedVolumes = volumes

            let rootSetup = Self.resolveIndexRoots(scope: scope, externals: externals)
            let scopeKey = Self.snapshotScopeKey(scope: scope, roots: rootSetup.allRoots)

            if let meta = await Task.detached(priority: .utility, operation: {
                EverythingSnapshotStore.readHeaderMetadata(scopeKey: scopeKey, expectedRoots: rootSetup.allRoots)
            }).value {
                guard !Task.isCancelled else { return }
                self.everythingNodeCount = meta.nodeCount
                self.isIndexingEverything = false
                if self.needsEverythingIndexResident {
                    self.loadOrBuildEverythingIndex(scope: scope, forceRebuild: false)
                }
                return
            }

            let built = await Self.buildScopedIndex(scope: scope, rootSetup: rootSetup, priority: .utility)
            guard !Task.isCancelled else { return }
            if let built {
                self.everythingNodeCount = built.nodes.count
                if self.needsEverythingIndexResident {
                    self.everythingIndex = built
                    self.refreshDisplayedCandidates()
                    self.startFSEventWatcherIfNeeded(for: built, scopeKey: scopeKey)
                    self.scheduleSnapshotSave(built, scopeKey: scopeKey)
                } else {
                    _ = await Task.detached(priority: .utility) {
                        EverythingSnapshotStore.save(built, scopeKey: scopeKey)
                    }.value
                    MemoryStats.reclaimFreeHeapPages()
                }
            }
            self.isIndexingEverything = false
        }
    }

    func rebuildEverythingIndex(scope: EverythingScope) {
        loadOrBuildEverythingIndex(scope: scope, forceRebuild: false)
    }

    func forceRebuildEverythingIndex(scope: EverythingScope? = nil) {
        loadOrBuildEverythingIndex(scope: scope ?? everythingScope, forceRebuild: true)
    }

    func loadOrBuildEverythingIndex(scope: EverythingScope, forceRebuild: Bool) {
        if !forceRebuild,
           everythingScope == scope,
           let existing = everythingIndex,
           !existing.nodes.isEmpty {
            startFSEventWatcherIfNeeded(for: existing)
            return
        }

        everythingIndexTask?.cancel()
        stopIndexWatcher()
        everythingScope = scope
        isIndexingEverything = true

        everythingIndexTask = Task { [weak self] in
            guard let self else { return }
            let externals = await Task.detached(priority: .userInitiated) { VolumeInspector.externalVolumes() }.value
            guard !Task.isCancelled else { return }
            self.cachedVolumes = await Task.detached(priority: .utility) { VolumeInspector.mountedVolumes() }.value
            guard !Task.isCancelled else { return }

            let rootSetup = Self.resolveIndexRoots(scope: scope, externals: externals)
            let scopeKey = Self.snapshotScopeKey(scope: scope, roots: rootSetup.allRoots)

            if !forceRebuild,
               let cached = await Task.detached(priority: .userInitiated, operation: {
                   EverythingSnapshotStore.load(scopeKey: scopeKey, expectedRoots: rootSetup.allRoots)
               }).value {
                guard !Task.isCancelled else { return }
                self.everythingIndex = cached
                self.everythingNodeCount = cached.nodes.count
                self.isIndexingEverything = false
                self.refreshDisplayedCandidates()
                self.startFSEventWatcherIfNeeded(for: cached, scopeKey: scopeKey)
                return
            }

            let finalIndex = await Self.buildScopedIndex(scope: scope, rootSetup: rootSetup, priority: .userInitiated) { [weak self] stage1 in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.everythingIndex = stage1
                    self.everythingNodeCount = stage1.nodes.count
                    self.refreshDisplayedCandidates()
                }
            }

            guard !Task.isCancelled else { return }
            if let finalIndex {
                self.everythingIndex = finalIndex
                self.everythingNodeCount = finalIndex.nodes.count
                self.refreshDisplayedCandidates()
                self.startFSEventWatcherIfNeeded(for: finalIndex, scopeKey: scopeKey)
                self.scheduleSnapshotSave(finalIndex, scopeKey: scopeKey)
            }
            self.isIndexingEverything = false
        }
    }

    private static func buildScopedIndex(
        scope: EverythingScope,
        rootSetup: (fastRoots: [URL], slowRoots: [URL], allRoots: [URL]),
        priority: TaskPriority,
        onStage1: (@Sendable (EverythingIndex) -> Void)? = nil
    ) async -> EverythingIndex? {
        if scope == .allVolumes {
            let stage1 = await Task.detached(priority: priority) {
                try? EverythingIndex.build(rootURLs: rootSetup.fastRoots, maxNodes: 140_000)
            }.value
            guard !Task.isCancelled else { return nil }
            if let stage1, let onStage1 { onStage1(stage1) }
            guard !rootSetup.slowRoots.isEmpty else { return stage1 }
            let stage2 = await Task.detached(priority: .utility) {
                try? EverythingIndex.build(rootURLs: rootSetup.slowRoots, maxNodes: 120_000)
            }.value
            guard !Task.isCancelled else { return stage1 }
            return stage2.map { stage1?.merging($0) ?? $0 } ?? stage1
        }
        return await Task.detached(priority: priority) {
            try? EverythingIndex.build(rootURLs: rootSetup.allRoots, maxNodes: 180_000)
        }.value
    }

    func startFSEventWatcherIfNeeded(for index: EverythingIndex, scopeKey: String? = nil) {
        stopIndexWatcher()
        let vols = cachedVolumes.sorted { $0.mountPath.count > $1.mountPath.count }
        let watchRoots = index.rootURLs.filter { root in
            let path = root.standardizedFileURL.path
            let summary = vols.first(where: { path == $0.mountPath || path.hasPrefix($0.mountPath == "/" ? "/" : $0.mountPath + "/") })
                ?? VolumeInspector.inspect(url: root)
            return summary.map { !VolumeInspector.isSlowOrRemoteVolume($0) } ?? true
        }
        guard !watchRoots.isEmpty else { return }
        let resolvedKey = scopeKey ?? Self.snapshotScopeKey(scope: everythingScope, roots: index.rootURLs)

        fsEventWatcher = EverythingFSEventWatcher(roots: watchRoots, debounceInterval: 0.9) { [weak self] changedDirs in
            Task { @MainActor [weak self] in
                guard let self, let current = self.everythingIndex else { return }
                let updated = await Task.detached(priority: .utility) {
                    current.applyingFSEventDirectories(changedDirs)
                }.value
                guard self.everythingIndex?.rootPaths == current.rootPaths else { return }
                self.everythingIndex = updated
                self.everythingNodeCount = updated.nodes.count
                if self.isOverlayVisible && (self.omniFilter == .files || !self.overlayQuery.isEmpty) {
                    self.refreshDisplayedCandidates()
                }
                self.scheduleSnapshotSave(updated, scopeKey: resolvedKey)
            }
        }
    }

    func stopIndexWatcher() {
        fsEventWatcher?.stop()
        fsEventWatcher = nil
        snapshotSaveTask?.cancel()
        snapshotSaveTask = nil
    }

    private func scheduleSnapshotSave(_ index: EverythingIndex, scopeKey: String) {
        snapshotSaveTask?.cancel()
        snapshotSaveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            _ = await Task.detached(priority: .utility) {
                EverythingSnapshotStore.save(index, scopeKey: scopeKey)
            }.value
        }
    }

    private static func resolveIndexRoots(
        scope: EverythingScope,
        externals: [VolumeSummary]
    ) -> (fastRoots: [URL], slowRoots: [URL], allRoots: [URL]) {
        if scope == .allVolumes {
            let nonSMB = externals.filter { $0.formatKind != .smb }
            let fast = [FileManager.default.homeDirectoryForCurrentUser]
                + nonSMB.filter { !VolumeInspector.isSlowOrRemoteVolume($0) }.map { URL(fileURLWithPath: $0.mountPath) }
            let slow = nonSMB.filter { VolumeInspector.isSlowOrRemoteVolume($0) }.map { URL(fileURLWithPath: $0.mountPath) }
            return (fast, slow, fast + slow)
        }
        let roots = scope.resolveRootURLs(volumes: externals)
        return (roots, [], roots)
    }

    private static func snapshotScopeKey(scope: EverythingScope, roots: [URL]) -> String {
        let joined = roots.map(\.standardizedFileURL.path).sorted().joined(separator: "|")
        return "\(scope.id)|\(joined)"
    }
}
