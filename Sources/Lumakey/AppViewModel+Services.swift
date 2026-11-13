import AppKit
import Combine
import Foundation
import LumakeyCore

extension AppViewModel {
    func configureLifecycleIntegrations() {
        let tracker = AppUsageTrackerController.shared
        usageCancellable = tracker.$revision.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateCachedDockApps()
                if self.isOverlayVisible { self.refreshDisplayedCandidates() }
            }
        }

        pluginWatcher?.stop()
        pluginWatcher = PluginDirectoryWatcher { [weak self] in
            Task { @MainActor [weak self] in
                self?.plugins = PluginSystem.listPlugins()
            }
        }

        GifCaptureController.shared.onRecordingCompleted = { [weak self] result in
            guard let self else { return }
            self.capturePasteboardOnceIfChanged()
            let sizeStr = FastFormatters.formatFileBytes(result.fileSizeBytes)
            self.serviceMessage = "GIF 动图已复制 (\(sizeStr) · \(result.frameCount) 帧)，可直接 ⌘V 粘贴"
        }
        GifCaptureController.shared.onStatusMessage = { [weak self] msg in
            self?.serviceMessage = msg
        }
        GifCaptureController.shared.onDiagnostic = { [weak self] diag in
            self?.diagnostic = diag
        }
    }

    func stopPluginWatcher() {
        pluginWatcher?.stop()
        pluginWatcher = nil
        pluginRunTask?.cancel()
        pluginRunTask = nil
    }

    var externalPluginHotKeys: [ExternalPluginHotKey] {
        plugins.compactMap { plugin in
            guard plugin.isValid, plugin.isEnabled,
                  let raw = plugin.manifest.hotkey,
                  let chord = HotKeyChord.parse(raw) else { return nil }
            return ExternalPluginHotKey(pluginID: plugin.id, pluginName: plugin.manifest.name, chord: chord)
        }
    }

    func reloadAppsAndPlugins() {
        plugins = PluginSystem.listPlugins()
        _ = (hotKeyManager ?? GlobalHotKeyManager.activeInstance)?.reapplyConfig(HotKeyBindingConfig.load(), persist: false)
        Task {
            let apps = await Task.detached(priority: .userInitiated) { LauncherEngine.discoverInstalledApps() }.value
            self.installedApps = apps
            AppUsageTrackerController.shared.ensureSystemProbe(for: apps)
            if self.isOverlayVisible {
                IconCache.shared.prewarmDockIcons(self.cachedDockApps)
            }
        }
    }

    func runPlugin(_ plugin: PluginDescriptor, query: String, arguments: [String] = [], showInline: Bool = false) {
        pluginRunTask?.cancel()
        let clipText = clipboardItems.first(where: { $0.textValue != nil })?.textValue
            ?? NSPasteboard.general.string(forType: .string)
            ?? ""
        serviceMessage = "正在运行插件：\(plugin.manifest.name)…"
        pluginRunTask = Task { [weak self] in
            do {
                let resolved = try await PluginSystem.runPluginAsync(
                    plugin,
                    query: query,
                    clipboardText: clipText,
                    arguments: arguments
                )
                guard !Task.isCancelled, let self else { return }
                self.pluginOutputText = resolved.plainText
                if showInline {
                    if let payload = resolved.viewPayload {
                        self.activeInlinePlugin = plugin
                        self.inlinePluginViewPayload = payload
                        self.inlineResultBody = nil
                    } else {
                        self.inlinePluginViewPayload = nil
                        self.inlineResultTitle = "插件：\(plugin.manifest.name)"
                        self.inlineResultBody = resolved.plainText.isEmpty ? "(无输出)" : resolved.plainText
                    }
                }
                self.serviceMessage = resolved.execution.exitCode == 0
                    ? "插件 \(plugin.manifest.name) 完成 (\(resolved.execution.durationMs) ms)"
                    : "插件返回退出码 \(resolved.execution.exitCode)"
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.pluginOutputText = error.localizedDescription
                self.serviceMessage = error.localizedDescription
            }
        }
    }

    func scaffoldExamplePlugin(id: String, name: String, keywordsCSV: String) {
        let keywords = keywordsCSV.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        do {
            let created = try PluginSystem.scaffoldPlugin(id: id, name: name, keywords: keywords, description: "通过 Lumakey 插件中心创建")
            reloadAppsAndPlugins(); serviceMessage = "已创建插件：\(created.manifest.name)"
        } catch let err as LumakeyError { diagnostic = err.diagnostic }
        catch { serviceMessage = error.localizedDescription }
    }

    func captureAndPinScreenshot() {
        runScreenCapture(mode: .interactiveAnnotate)
    }

    func captureAndAnalyzeOCR() {
        runScreenCapture(mode: .quickOCR)
    }

    private func runScreenCapture(mode: ScreenshotMode) {
        isCapturingScreen = true; onHideOverlayRequest?()
        Task {
            defer { self.isCapturingScreen = false }
            do {
                let result = try await ScreenCaptureCoordinator.shared.capture(mode: mode)
                self.isCapturingScreen = false
                switch result {
                case .cancelled:
                    self.capturePasteboardOnceIfChanged()
                case .copied(let url):
                    self.capturePasteboardOnceIfChanged()
                    latestCaptureURL = url; serviceMessage = "截图已自动复制到剪贴板，可直接 ⌘V 粘贴"
                case .saved(let url):
                    self.capturePasteboardOnceIfChanged()
                    latestCaptureURL = url; serviceMessage = "截图已保存并复制到剪贴板：\(url.lastPathComponent)"
                case .pinned(let url, let screenRect):
                    self.capturePasteboardOnceIfChanged()
                    latestCaptureURL = url; PinWindowController.shared.pinImage(at: url, screenRect: screenRect)
                    serviceMessage = "已钉在屏幕并自动复制到剪贴板"
                case .ocrRequested(let url):
                    await executeCaptureOCR(at: url)
                case .cutoutRequested(let url):
                    latestCaptureURL = url; liftSubject(at: url)
                }
            } catch let err as LumakeyError {
                diagnostic = err.diagnostic; serviceMessage = err.diagnostic.reason
                if err.diagnostic.reason.contains("屏幕录制"), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            } catch {
                serviceMessage = error.localizedDescription
            }
        }
    }

    private func executeCaptureOCR(at url: URL) async {
        latestCaptureURL = url
        do {
            let analysis = try await Task.detached(priority: .userInitiated) { try VisionService.analyzeTextAndBarcodes(at: url) }.value
            let combined = ([analysis.recognizedText] + analysis.barcodes).filter { !$0.isEmpty }.joined(separator: "\n")
            serviceMessage = combined.isEmpty ? "未检测到文本" : "OCR 结果已复制到剪贴板"
            OCRResultWindowController.shared.present(imageURL: url, analysis: analysis) { [weak self] in
                self?.captureAndAnalyzeOCR()
            }
        } catch let err as LumakeyError {
            serviceMessage = err.diagnostic.reason
        } catch {
            serviceMessage = error.localizedDescription
        }
    }

    func analyzeImageWithVision(at url: URL) {
        Task {
            if let analysis = try? await Task.detached(priority: .userInitiated, operation: { try VisionService.analyzeTextAndBarcodes(at: url) }).value {
                ocrResultText = analysis.recognizedText.isEmpty ? "未识别到文本内容。" : analysis.recognizedText
                barcodeResults = analysis.barcodes
            }
        }
    }

    func liftSubject(at url: URL) {
        Task {
            if let outURL = try? await Task.detached(priority: .userInitiated, operation: { try VisionService.liftForegroundSubject(from: url) }).value {
                _ = ScreenshotCompositor.copyImageFileToPasteboard(at: outURL)
                capturePasteboardOnceIfChanged()
                PinWindowController.shared.pinImage(at: outURL)
                serviceMessage = "主体抠图已钉在屏幕并自动复制到剪贴板"
            }
        }
    }

    func applyMosConfig(_ next: MosConfig) {
        mosConfig = next
        MosEngine.shared.apply(config: next, persist: true)
        refreshMosStatus()
    }

    func requestMosAccessibilityPermission() {
        _ = MosEngine.shared.requestAccessibilityPermission()
        refreshMosStatus()
    }

    func refreshMosStatus() {
        mosAccessibilityTrusted = MosEngine.shared.isAccessibilityTrusted
        mosTapActive = MosEngine.shared.isTapActive
    }

    func executeClipboardEntry(_ entry: ClipboardEntry) {
        ClipboardService.copyToPasteboard(entry)
        serviceMessage = "已复制：\(entry.title)"
        if !isOverlayPinned { onHideOverlayRequest?() }
    }

    func toggleClipboardPin(_ entry: ClipboardEntry) {
        guard let idx = clipboardItems.firstIndex(where: { $0.id == entry.id }) else { return }
        clipboardItems[idx].isPinned.toggle()
    }

    func clearUnpinnedClipboard() {
        let removed = clipboardItems.filter { !$0.isPinned }
        ClipboardService.removeTempFiles(for: removed)
        clipboardItems.removeAll { !$0.isPinned }
    }

    func capturePasteboardOnceIfChanged() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = pb.changeCount
        if let entry = ClipboardService.captureCurrent(from: pb) {
            clipboardItems = ClipboardService.insert(entry, into: clipboardItems)
        }
    }

    func startClipboardMonitor() {
        stopClipboardMonitor()
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        clipboardTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1500), tolerance: .milliseconds(250))
                guard !Task.isCancelled, let self else { break }
                if self.isCapturingScreen { continue }
                self.capturePasteboardOnceIfChanged()
            }
        }
    }

    func stopClipboardMonitor() {
        clipboardTask?.cancel()
        clipboardTask = nil
    }
}
