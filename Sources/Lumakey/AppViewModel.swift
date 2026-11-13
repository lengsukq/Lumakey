import AppKit
import Combine
import Foundation
import LumakeyCore
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var omniFilter: OmniFilter = .all
    @Published var overlayQuery: String = "" {
        didSet { handleOverlayQueryChanged() }
    }
    @Published var overlaySelectedIndex: Int = 0
    @Published var isOverlayPinned: Bool = false
    @Published var showOverlayLens: Bool = false
    @Published var focusToken: Int = 0
    @Published var everythingScope: EverythingScope = .allVolumes
    @Published var clipboardItems: [ClipboardEntry] = [] {
        didSet {
            if isOverlayVisible { refreshDisplayedCandidates() }
        }
    }
    @Published var clipboardCategory: ClipboardCategory = .all {
        didSet {
            overlaySelectedIndex = 0
            refreshDisplayedCandidates()
        }
    }
    @Published var inlineResultTitle: String = ""
    @Published var inlineResultBody: String?
    @Published var inlinePluginViewPayload: PluginViewPayload?
    @Published var activeInlinePlugin: PluginDescriptor?
    @Published var showDockIcon: Bool = false
    @Published var activeSettingsSection: SettingsSection = .general
    @Published var appLaunchCounts: [String: Int] = [:] {
        didSet { updateCachedDockApps() }
    }
    @Published var isCapturingScreen: Bool = false

    @Published var mosConfig: MosConfig = MosConfig.load()
    @Published var mosTapActive: Bool = false
    @Published var mosAccessibilityTrusted: Bool = false

    @Published var layoutMode: ExplorerLayoutMode = .single
    @Published var activePane: PaneSide = .left
    @Published var leftPane: PaneState
    @Published var rightPane: PaneState

    @Published var locations: [LocationItem] = []
    @Published var selectedEntry: FileEntry?
    @Published var selectedEntryIDs: Set<String> = []
    @Published var previewState: PreviewContentState = .empty
    @Published var computedSHA256: String?
    @Published var isComputingSHA256 = false

    @Published var installedApps: [InstalledAppItem] = [] {
        didSet {
            updateCachedDockApps()
            if isOverlayVisible { refreshDisplayedCandidates() }
        }
    }
    @Published var plugins: [PluginDescriptor] = [] {
        didSet {
            if isOverlayVisible { refreshDisplayedCandidates() }
        }
    }
    @Published var pluginOutputText: String = ""

    @Published var displayedCandidates: [LauncherCandidate] = []
    @Published var cachedVolumes: [VolumeSummary] = []
    @Published var cachedDockApps: [InstalledAppItem] = []
    @Published var everythingNodeCount: Int = 0
    @Published var isIndexingEverything = false

    @Published var toolingStatus = HostToolingStatus()
    @Published var latestCaptureURL: URL?
    @Published var ocrResultText: String = ""
    @Published var barcodeResults: [String] = []
    @Published var serviceMessage: String?
    @Published var diagnostic: UserFacingDiagnostic?

    @Published var showBatchRenameSheet = false
    @Published var renameRule = BatchRenameRule()
    @Published var workspaceClipboard: WorkspaceClipboardState?
    let workspacePrompt = WorkspacePromptController()
    var selectionAnchorID: String?
    var activeDragURLs: [URL] = []

    var isOverlayVisible: Bool = false
    var everythingIndex: EverythingIndex?
    var residentEverythingNodeCount: Int { everythingIndex?.nodes.count ?? 0 }
    var needsEverythingIndexResident: Bool {
        isOverlayVisible && (omniFilter == .files || !overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    var searchTask: Task<Void, Never>?
    var everythingIndexTask: Task<Void, Never>?
    var previewTask: Task<Void, Never>?
    var hashTask: Task<Void, Never>?
    var clipboardTask: Task<Void, Never>?
    var indexUnloadTask: Task<Void, Never>?
    var leftDirectoryTask: Task<Void, Never>?
    var rightDirectoryTask: Task<Void, Never>?
    var locationRefreshTask: Task<Void, Never>?
    var snapshotSaveTask: Task<Void, Never>?
    var pluginRunTask: Task<Void, Never>?
    var fsEventWatcher: EverythingFSEventWatcher?
    var pluginWatcher: PluginDirectoryWatcher?
    var usageCancellable: AnyCancellable?
    weak var hotKeyManager: GlobalHotKeyManager?
    var directoryCache = WorkspaceDirectoryCache(maxEntries: 48)
    var volumeObservers: [NSObjectProtocol] = []
    var lastPasteboardChangeCount: Int = -1
    var hasLoadedWorkspace: Bool = false

    var onRouteRequest: ((WindowRoute) -> Void)?
    var onHideOverlayRequest: (() -> Void)?
    var onShowOverlayRequest: ((OmniFilter) -> Void)?
    var onRecenterFloatingPanel: (() -> Void)?
    var onDockVisibilityChanged: ((Bool) -> Void)?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? home
        let leftTab = WorkspaceTab(directoryURL: home)
        let rightTab = WorkspaceTab(directoryURL: desktop)
        self.leftPane = PaneState(tabs: [leftTab], activeTabID: leftTab.id)
        self.rightPane = PaneState(tabs: [rightTab], activeTabID: rightTab.id)
    }

    func bootstrap() {
        refreshCachedVolumes()
        installVolumeObservers()
        configureLifecycleIntegrations()
        reloadAppsAndPlugins()
        primeEverythingIndexOnStartup(scope: everythingScope)
        MosEngine.shared.apply(config: mosConfig, persist: false)
        refreshMosStatus()
        startClipboardMonitor()
        BackupCoordinator.triggerAutoBackupOnLaunchIfNeeded(viewModel: self)
        Task { [weak self] in
            let detected = await Task.detached(priority: .utility) { HostToolingStatus.detect() }.value
            self?.toolingStatus = detected
        }
    }

    var effectiveLensVisible: Bool {
        omniFilter == .files || omniFilter == .clipboard || showOverlayLens || inlineResultBody != nil || inlinePluginViewPayload != nil
    }

    var activePaneState: PaneState {
        activePane == .left ? leftPane : rightPane
    }

    func mutatePane(_ pane: PaneSide, _ transform: (inout PaneState) -> Void) {
        if pane == .left { transform(&leftPane) } else { transform(&rightPane) }
    }

    var selectedCandidate: LauncherCandidate? {
        guard overlaySelectedIndex >= 0, overlaySelectedIndex < displayedCandidates.count else { return nil }
        return displayedCandidates[overlaySelectedIndex]
    }

    var clipboardHistoryCount: Int { clipboardItems.count }
    var activeProcessCount: Int { ProcessSupervisor.shared.activeCount }

    func updateCachedDockApps() {
        cachedDockApps = Array(AppUsageService.shared.rankApps(installedApps).prefix(8))
    }

    var availableEverythingScopes: [EverythingScope] {
        var list: [EverythingScope] = [.allVolumes, .quickUserFolders, .home]
        for vol in cachedVolumes where vol.mountPath != "/" {
            list.append(.volume(name: vol.name, mountPath: vol.mountPath))
        }
        return list
    }

    func navigate(pane: PaneSide, to url: URL, pushHistory: Bool = true) {
        let changed = (pane == .left ? leftPane : rightPane).currentDirectory.standardizedFileURL.path != url.standardizedFileURL.path
        mutatePane(pane) { state in
            if pushHistory, state.currentDirectory != url { state.history.append(state.currentDirectory) }
            state.currentDirectory = url
            state.diagnostic = nil
        }
        if changed && activePane == pane {
            clearWorkspaceSelection()
        }
        refreshDirectory(pane: pane)
    }

    func goBack(pane: PaneSide) {
        guard let previous = (pane == .left ? leftPane : rightPane).history.last else { return }
        mutatePane(pane) { $0.history.removeLast() }
        navigate(pane: pane, to: previous, pushHistory: false)
    }

    func addTab(pane: PaneSide) {
        let baseURL = (pane == .left ? leftPane : rightPane).currentDirectory
        let newTab = WorkspaceTab(directoryURL: baseURL)
        mutatePane(pane) { state in
            state.tabs.append(newTab)
            state.activeTabID = newTab.id
        }
        refreshDirectory(pane: pane)
    }

    func selectTab(_ tabID: UUID, in pane: PaneSide) {
        mutatePane(pane) { $0.activeTabID = tabID }
        if activePane == pane { clearWorkspaceSelection() }
        refreshDirectory(pane: pane)
    }

    func closeTab(_ tabID: UUID, in pane: PaneSide) {
        mutatePane(pane) { state in
            guard state.tabs.count > 1, let idx = state.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            state.tabs.remove(at: idx)
            if state.activeTabID == tabID { state.activeTabID = state.tabs[max(0, idx - 1)].id }
        }
        if activePane == pane { clearWorkspaceSelection() }
        refreshDirectory(pane: pane)
    }
}
