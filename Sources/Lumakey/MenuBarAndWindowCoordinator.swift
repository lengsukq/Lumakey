import AppKit
import LumakeyCore
import SwiftUI

@MainActor
final class MenuBarAndWindowCoordinator: NSObject, NSWindowDelegate {
    let viewModel: AppViewModel
    private let panelController: FloatingPanelController
    private let hotKeyManager = GlobalHotKeyManager()
    private var statusItem: NSStatusItem?
    private var windows: [String: NSWindow] = [:]
    private var docWindowOrder: [String] = []
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        self.panelController = FloatingPanelController(viewModel: viewModel)
        super.init()
        wireCallbacks()
    }

    func start() {
        setupStatusItem()
        registerHotKeys()
        installMemoryPressureMonitor()
        viewModel.bootstrap()
        SystemPulseWindowController.shared.start(
            onPurgeMemory: { [weak self] in self?.viewModel.reclaimAllIdleMemoryNow() },
            onMenuBarUpdate: { [weak self] text in self?.statusItem?.button?.title = text.map { " " + $0 } ?? "" },
            onOpenNetworkMonitor: { [weak self] in self?.open(route: .networkMonitor) }
        )
        panelController.show(filter: .all)
    }

    func showLauncher(filter: OmniFilter = .all) {
        panelController.show(filter: filter)
    }

    func shutdown() {
        hotKeyManager.unregisterAll()
        viewModel.stopClipboardMonitor()
        viewModel.removeVolumeObservers()
        viewModel.stopIndexWatcher()
        viewModel.searchTask?.cancel()
        MosEngine.shared.stopTapAndReleaseAll()
        SystemPulseWindowController.shared.shutdown()
        ProcessSupervisor.shared.terminateAll()
        PinWindowController.shared.closeAll()
        VideoPlaybackCompat.cleanupTempDirectory()
        for (_, win) in windows {
            win.delegate = nil
            win.contentView = nil
            win.close()
        }
        windows.removeAll()
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
    }

    private func wireCallbacks() {
        viewModel.onRouteRequest = { [weak self] route in self?.open(route: route) }
        viewModel.onHideOverlayRequest = { [weak self] in self?.panelController.hide() }
        viewModel.onShowOverlayRequest = { [weak self] filter in self?.panelController.show(filter: filter) }
        viewModel.onRecenterFloatingPanel = { [weak self] in self?.panelController.resetPositionToCenter() }
        viewModel.onDockVisibilityChanged = { [weak self] _ in self?.syncDockPolicy() }
        OCRResultWindowController.shared.onVisibilityChanged = { [weak self] in self?.syncDockPolicy() }
    }

    func syncDockPolicy() {
        let hasOpenWindows = !windows.isEmpty || OCRResultWindowController.shared.isWindowVisible
        let target: NSApplication.ActivationPolicy = (viewModel.showDockIcon || hasOpenWindows) ? .regular : .accessory
        if NSApp.activationPolicy() != target { NSApp.setActivationPolicy(target) }
    }

    func handleDockReopen() {
        if !windows.isEmpty {
            for win in windows.values where win.isMiniaturized { win.deminiaturize(nil) }
            let preferred = windows["workspace"] ?? windows["videoPlayer"] ?? windows.values.first
            preferred?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if OCRResultWindowController.shared.bringToFrontIfVisible() {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        showLauncher(filter: .all)
    }

    func buildDockMenu() -> NSMenu {
        let menu = NSMenu()
        if !windows.isEmpty {
            for (_, win) in windows.sorted(by: { $0.key < $1.key }) {
                addMenuItem(to: menu, title: "前置：\(win.title)", key: "") {
                    if win.isMiniaturized { win.deminiaturize(nil) }
                    win.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            menu.addItem(.separator())
        }
        addMenuItem(to: menu, title: "文件与外置磁盘工作台", key: "⌥E") { [weak self] in self?.open(route: .workspace) }
        addMenuItem(to: menu, title: "本机网络流量与去向监控", key: "⌥N") { [weak self] in self?.open(route: .networkMonitor) }
        addMenuItem(to: menu, title: "统一搜索快捷台", key: "⌥Space") { [weak self] in self?.panelController.show(filter: .all) }
        addMenuItem(to: menu, title: "选区截图钉屏", key: "⌥A") { [weak self] in self?.viewModel.captureAndPinScreenshot() }
        addMenuItem(to: menu, title: "应用缓存管理", key: "") { [weak self] in self?.open(route: .settings(.cache)) }
        addMenuItem(to: menu, title: "设置中心", key: "⌘,") { [weak self] in self?.open(route: .settings(.general)) }
        return menu
    }

    private func registerHotKeys() {
        hotKeyManager.registerDefaultShortcuts(
            onLauncher: { [weak self] in self?.panelController.toggle(filter: .all) },
            onFiles: { [weak self] in self?.panelController.toggle(filter: .files) },
            onClipboard: { [weak self] in self?.panelController.toggle(filter: .clipboard) },
            onCapturePin: { [weak self] in self?.viewModel.captureAndPinScreenshot() },
            onCaptureOCR: { [weak self] in self?.viewModel.captureAndAnalyzeOCR() },
            onWorkspace: { [weak self] in self?.open(route: .workspace) },
            onToggleMonitor: { SystemPulseWindowController.shared.toggleFloatingWidget() },
            onNetworkMonitor: { [weak self] in self?.open(route: .networkMonitor) }
        )
    }

    private func installMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            self?.viewModel.reclaimAllIdleMemoryNow()
        }
        source.resume()
        memoryPressureSource = source
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "流光 Lumakey")
        item.button?.imagePosition = .imageLeading
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        item.button?.toolTip = "流光 Lumakey (⌥Space)"

        let menu = NSMenu()
        addMenuItem(to: menu, title: "呼出统一搜索快捷台", key: "⌥Space") { [weak self] in self?.panelController.show(filter: .all) }
        addMenuItem(to: menu, title: "文件极速过滤", key: "⌥F") { [weak self] in self?.panelController.show(filter: .files) }
        addMenuItem(to: menu, title: "剪贴板历史过滤", key: "⌥C") { [weak self] in self?.panelController.show(filter: .clipboard) }
        menu.addItem(.separator())
        addMenuItem(to: menu, title: "系统脉搏监控悬浮窗", key: "⌥M") { SystemPulseWindowController.shared.toggleFloatingWidget() }
        addMenuItem(to: menu, title: "系统脉搏：立即贴边自动隐藏", key: "") { SystemPulseWindowController.shared.snapToNearestEdge() }
        addMenuItem(to: menu, title: "菜单栏显示实时功耗与网速", key: "") { SystemPulseWindowController.shared.toggleMenuBarReadout() }
        addMenuItem(to: menu, title: "本机网络流量与去向监控", key: "⌥N") { [weak self] in self?.open(route: .networkMonitor) }
        menu.addItem(.separator())
        addMenuItem(to: menu, title: "选区截图钉屏", key: "⌥A") { [weak self] in self?.viewModel.captureAndPinScreenshot() }
        addMenuItem(to: menu, title: "选区截图离线识字", key: "⌥O") { [weak self] in self?.viewModel.captureAndAnalyzeOCR() }
        addMenuItem(to: menu, title: "关闭全部钉图", key: "") { PinWindowController.shared.closeAll() }
        menu.addItem(.separator())
        addMenuItem(to: menu, title: "应用缓存与存储清理", key: "") { [weak self] in self?.open(route: .settings(.cache)) }
        addMenuItem(to: menu, title: "Mos 鼠标平滑与反转", key: "") { [weak self] in self?.open(route: .settings(.mos)) }
        addMenuItem(to: menu, title: "立即释放空闲内存", key: "") { [weak self] in self?.viewModel.reclaimAllIdleMemoryNow() }
        addMenuItem(to: menu, title: "文件与外置磁盘工作台 · 附加", key: "⌥E") { [weak self] in self?.open(route: .workspace) }
        addMenuItem(to: menu, title: "欢迎引导", key: "") { [weak self] in self?.open(route: .welcome) }
        addMenuItem(to: menu, title: "设置与插件 MCP 中心", key: "⌘,") { [weak self] in self?.open(route: .settings(.general)) }
        menu.addItem(.separator())
        addMenuItem(to: menu, title: "退出 流光 Lumakey", key: "⌘Q") { NSApp.terminate(nil) }

        item.menu = menu
        self.statusItem = item
    }

    private func addMenuItem(to menu: NSMenu, title: String, key: String, action: @escaping () -> Void) {
        let label = key.isEmpty ? title : "\(title)   (\(key))"
        menu.addItem(CallbackMenuItem(title: label, callback: action))
    }

    func open(route: WindowRoute) {
        if case .workspace = route {} else {
            PreviewPlaybackRegistry.shared.pauseAll()
        }
        panelController.hide()
        NSApp.activate(ignoringOtherApps: true)
        switch route {
        case .welcome:
            presentWindow(key: "welcome", title: "欢迎使用 流光 Lumakey", size: NSSize(width: 820, height: 580)) {
                WelcomeGuideView(viewModel: viewModel)
            }
        case .workspace:
            viewModel.ensureWorkspaceLoaded()
            presentWindow(key: "workspace", title: "文件与外置磁盘工作台 · 附加", size: NSSize(width: 1180, height: 740)) {
                WorkspaceHostView(viewModel: viewModel)
            }
        case .networkMonitor:
            presentWindow(key: "networkMonitor", title: "本机网络流量与去向监控", size: NSSize(width: 1020, height: 660)) {
                NetworkMonitorWindowView()
            }
        case .settings(let section):
            viewModel.activeSettingsSection = section
            presentWindow(key: "settings", title: "流光 Lumakey 设置与插件", size: NSSize(width: 980, height: 640)) {
                SettingsCenterView(viewModel: viewModel)
            }
        case .documentReader(let url, let siblings):
            let key = "doc:\(url.standardizedFileURL.path)"
            presentWindow(key: key, title: "文档阅读 · \(url.lastPathComponent)", size: NSSize(width: 920, height: 660), isDocumentSlot: true) {
                DocumentReaderWindowView(initialURL: url, siblingURLs: siblings, windowKey: key) { [weak self] in self?.windows[key]?.close() }
            }
        case .imageViewer(let url, let siblings, let pinOnTop):
            let key = "img:\(url.standardizedFileURL.path)"
            presentWindow(key: key, title: "只读看图 · \(url.lastPathComponent)", size: NSSize(width: 880, height: 640), isDocumentSlot: true, pinOnTop: pinOnTop) {
                ReadOnlyImageViewerSheet(initialURL: url, siblingURLs: siblings, windowKey: key) { [weak self] in self?.windows[key]?.close() }
            }
        case .videoPlayer(let url, let siblings, let pinOnTop):
            presentWindow(key: "videoPlayer", title: "影院播片 · \(url.lastPathComponent)", size: NSSize(width: 1080, height: 660), darkCinema: true, pinOnTop: pinOnTop) {
                CinemaVideoPlayerSheet(initialURL: url, siblingURLs: siblings, windowKey: "videoPlayer") { [weak self] in self?.windows["videoPlayer"]?.close() }
            }
        }
    }

    private func presentWindow<Content: View>(
        key: String, title: String, size: NSSize, isDocumentSlot: Bool = false, darkCinema: Bool = false, pinOnTop: Bool = false, @ViewBuilder content: () -> Content
    ) {
        if let existing = windows[key] {
            existing.title = title
            applyAppearance(to: existing, darkCinema: darkCinema)
            existing.contentView = NSHostingView(rootView: content())
            WindowLevelStore.shared.attach(window: existing, key: key, initialPinned: pinOnTop)
            if existing.isMiniaturized { existing.deminiaturize(nil) }
            syncDockPolicy(); existing.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            return
        }
        if isDocumentSlot {
            docWindowOrder.append(key)
            while docWindowOrder.count > 6 { windows[docWindowOrder.removeFirst()]?.close() }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = title; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.minSize = darkCinema ? NSSize(width: 460, height: 260) : NSSize(width: 680, height: 460)
        applyAppearance(to: window, darkCinema: darkCinema)
        window.isReleasedWhenClosed = false; window.delegate = self; window.center()
        window.contentView = NSHostingView(rootView: content())
        windows[key] = window
        WindowLevelStore.shared.attach(window: window, key: key, initialPinned: pinOnTop)
        syncDockPolicy(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    private func applyAppearance(to window: NSWindow, darkCinema: Bool) {
        if darkCinema {
            window.appearance = NSAppearance(named: .darkAqua); window.isOpaque = true
            window.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.045, blue: 0.06, alpha: 1.0)
        } else {
            window.appearance = nil; window.isOpaque = false; window.backgroundColor = .clear
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow,
              let key = windows.first(where: { $0.value === closedWindow })?.key else { return }
        windows.removeValue(forKey: key)
        docWindowOrder.removeAll { $0 == key }
        WindowLevelStore.shared.detach(key: key)
        closedWindow.delegate = nil; closedWindow.contentView = nil
        if key == "workspace" { viewModel.releaseWorkspaceMemory() }
        syncDockPolicy(); MemoryStats.reclaimFreeHeapPages()
    }
}

@MainActor
private final class CallbackMenuItem: NSMenuItem {
    private let callback: () -> Void
    init(title: String, callback: @escaping () -> Void) {
        self.callback = callback
        super.init(title: title, action: #selector(handleTap), keyEquivalent: "")
        self.target = self
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func handleTap() { callback() }
}
