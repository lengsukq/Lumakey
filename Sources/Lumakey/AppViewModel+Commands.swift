import AppKit
import Foundation
import LumakeyCore

extension AppViewModel {
    func executeCandidate(_ candidate: LauncherCandidate) {
        switch candidate.kind {
        case .app(let app):
            launchApp(app)
        case .calculator(_, let result, _):
            copyPlainText(result, message: "已复制结果：\(result)")
            if !isOverlayPinned { onHideOverlayRequest?() }
        case .devTool(let tool):
            if let pngURL = tool.previewImageURL {
                _ = DevToolkitEngine.copyQRImageToPasteboard(at: pngURL)
                capturePasteboardOnceIfChanged()
                serviceMessage = "二维码图片已复制到剪贴板，可直接 ⌘V 粘贴"
            } else {
                copyPlainText(tool.copyText, message: "已复制 \(tool.badge)：\(tool.title)")
            }
            if !isOverlayPinned { onHideOverlayRequest?() }
        case .snippet(let match):
            copyPlainText(match.expandedText, message: "已展开并复制短语：\(match.snippet.title)")
            if !isOverlayPinned { onHideOverlayRequest?() }
        case .fileHit(let hit):
            executeEverythingHit(hit)
        case .clipboard(let entry):
            executeClipboardEntry(entry)
        case .plugin(let plugin):
            let queryArg = stripMatchedPluginKeyword(from: overlayQuery, plugin: plugin)
            runPlugin(plugin, query: queryArg, showInline: true)
        case .command(let cmd):
            executeSystemCommand(cmd.command)
        }
    }

    func quickExecuteCandidate(at index: Int) {
        guard index >= 0, index < displayedCandidates.count else { return }
        overlaySelectedIndex = index
        executeCandidate(displayedCandidates[index])
    }

    func copySelectedCandidateValue() {
        guard let selected = selectedCandidate else { return }
        switch selected.kind {
        case .calculator(_, let result, _):
            copyPlainText(result, message: "已复制计算结果：\(result)")
        case .devTool(let tool):
            if let pngURL = tool.previewImageURL {
                _ = DevToolkitEngine.copyQRImageToPasteboard(at: pngURL)
                capturePasteboardOnceIfChanged()
                serviceMessage = "已复制二维码 PNG 图片"
            } else {
                copyPlainText(tool.copyText, message: "已复制 \(tool.badge)")
            }
        case .snippet(let match):
            copyPlainText(match.expandedText, message: "已复制展开短语：\(match.snippet.title)")
        case .clipboard(let entry):
            ClipboardService.copyToPasteboard(entry)
            serviceMessage = "已复制剪贴板项：\(entry.title)"
        case .fileHit(let hit):
            copyPlainText(hit.url.path, message: "已复制路径：\(hit.name)")
        case .app(let app):
            copyPlainText(app.url.path, message: "已复制应用路径：\(app.name)")
        case .plugin(let plugin):
            copyPlainText(plugin.directoryURL.path, message: "已复制插件目录路径")
        case .command(let cmd):
            copyPlainText(cmd.title, message: "已复制命令标题")
        }
    }

    func executeSecondaryCandidateAction() {
        guard let selected = selectedCandidate else { return }
        switch selected.kind {
        case .app(let app):
            NSWorkspace.shared.activateFileViewerSelecting([app.url])
            if !isOverlayPinned { onHideOverlayRequest?() }
        case .fileHit(let hit):
            if [.markdown, .text, .image, .video].contains(hit.mediaKind) {
                NSWorkspace.shared.activateFileViewerSelecting([hit.url])
            } else {
                openMediaWindow(for: hit.url, kind: hit.mediaKind)
            }
        case .clipboard(let clip):
            if case .image(let url, _) = clip.payloadKind {
                openMediaWindow(for: url, kind: .image, pinOnTop: true)
            } else if let url = clip.fileURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                executeClipboardEntry(clip)
            }
        case .devTool(let tool):
            if let url = tool.previewImageURL {
                openMediaWindow(for: url, kind: .image, pinOnTop: true)
            } else {
                copyPlainText(tool.copyText, message: "已复制 \(tool.badge)")
            }
        case .snippet:
            openRoute(.settings(.snippets))
        case .plugin:
            openRoute(.settings(.plugins))
        default:
            executeCandidate(selected)
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
        AppUsageTrackerController.shared.recordLumakeyLaunch(app)
        appLaunchCounts[app.id, default: 0] += 1
        NSWorkspace.shared.open(app.url)
        if !isOverlayPinned { onHideOverlayRequest?() }
    }

    func startGifRecording() {
        onHideOverlayRequest?()
        GifCaptureController.shared.startInteractiveCapture()
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
        case .devTool(let tool):
            if let url = tool.previewImageURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .plugin(let plugin):
            NSWorkspace.shared.activateFileViewerSelecting([plugin.directoryURL])
        default: break
        }
    }

    func executeSystemCommand(_ command: SystemCommandKind) {
        switch command {
        case .openWelcome: openRoute(.welcome)
        case .openWorkspace: openRoute(.workspace)
        case .openSettings: openRoute(.settings(.general))
        case .openClipboard: prepareOverlay(filter: .clipboard)
        case .openEverything: prepareOverlay(filter: .files)
        case .capturePin: captureAndPinScreenshot()
        case .captureOCR: captureAndAnalyzeOCR()
        case .recordGif: startGifRecording()
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
        case .openMosSettings: openRoute(.settings(.mos))
        case .toggleSystemMonitor:
            SystemPulseWindowController.shared.toggleFloatingWidget()
            if !isOverlayPinned { onHideOverlayRequest?() }
        case .openNetworkMonitor: openRoute(.networkMonitor)
        case .openCacheManager: openRoute(.settings(.cache))
        case .openBackupSettings: openRoute(.settings(.backup))
        case .quickBackup: BackupCoordinator.triggerQuickBackup(viewModel: self)
        case .openSnippetsSettings: openRoute(.settings(.snippets))
        case .openPluginsSettings: openRoute(.settings(.plugins))
        case .reclaimMemory: reclaimAllIdleMemoryNow()
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

    private func copyPlainText(_ value: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        serviceMessage = message
    }

    private func stripMatchedPluginKeyword(from raw: String, plugin: PluginDescriptor) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        for kw in plugin.keywordsLowercased.sorted(by: { $0.count > $1.count }) {
            if lower == kw { return "" }
            if lower.hasPrefix(kw + " ") {
                return String(trimmed.dropFirst(kw.count + 1)).trimmingCharacters(in: .whitespaces)
            }
        }
        return trimmed
    }

    private func runAppleScript(_ source: String) {
        if let script = NSAppleScript(source: source) { var err: NSDictionary?; script.executeAndReturnError(&err) }
    }
}
