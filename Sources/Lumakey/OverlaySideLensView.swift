import AppKit
import LumakeyCore
import SwiftUI

struct OverlaySideLensView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var usageTracker = AppUsageTrackerController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let viewPayload = viewModel.inlinePluginViewPayload {
                PluginViewLensContainerCard(
                    payload: viewPayload,
                    onCopyText: { val in copyString(val, toast: "已复制：\(val)") },
                    onOpenURL: { url in NSWorkspace.shared.open(url) },
                    onRunCommandArgs: { args in
                        guard let plugin = viewModel.activeInlinePlugin else { return }
                        viewModel.runPlugin(plugin, query: viewModel.overlayQuery, arguments: args, showInline: true)
                    },
                    onClose: {
                        viewModel.inlinePluginViewPayload = nil
                        viewModel.activeInlinePlugin = nil
                    }
                )
            } else if let inline = viewModel.inlineResultBody {
                InlineOutputLensCard(
                    title: viewModel.inlineResultTitle,
                    outputText: inline,
                    onCopy: { copyString(inline, toast: "已复制输出内容") },
                    onClose: { viewModel.inlineResultBody = nil }
                )
            } else if let candidate = viewModel.selectedCandidate,
                      case .clipboard(let clip) = candidate.kind {
                clipboardDetailLens(clip)
            } else if let candidate = viewModel.selectedCandidate {
                candidateDetailLens(candidate)
            } else {
                SideLivePreviewCard(previewState: viewModel.previewState)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func clipboardDetailLens(_ clip: ClipboardEntry) -> some View {
        switch clip.payloadKind {
        case .colorHex(let hex):
            ColorSwatchLensCard(
                hex: hex,
                clip: clip,
                onCopyText: { value, toast in copyString(value, toast: toast) },
                onCopyClipboard: { viewModel.executeClipboardEntry(clip) },
                onTogglePin: { viewModel.toggleClipboardPin(clip) }
            )
        case .image(let url, let dims):
            ImageClipboardLensCard(
                url: url,
                dimensions: dims,
                clip: clip,
                onCopyImage: {
                    _ = ScreenshotCompositor.copyImageFileToPasteboard(at: url)
                    viewModel.serviceMessage = "图片已复制到剪贴板"
                },
                onPinOverlay: { PinWindowController.shared.pinImage(at: url) },
                onOpenViewer: { viewModel.openMediaWindow(for: url, kind: .image, pinOnTop: true) },
                onTogglePin: { viewModel.toggleClipboardPin(clip) },
                onCopyText: { value, toast in copyString(value, toast: toast) }
            )
        case .text, .file:
            TextClipboardLensCard(
                clip: clip,
                onCopyClipboard: { viewModel.executeClipboardEntry(clip) },
                onTogglePin: { viewModel.toggleClipboardPin(clip) }
            )
        }
    }

    @ViewBuilder
    private func candidateDetailLens(_ candidate: LauncherCandidate) -> some View {
        switch candidate.kind {
        case .fileHit(let hit):
            SideLivePreviewCard(previewState: viewModel.previewState)
                .frame(maxHeight: .infinity)
            fileActionStrip(for: hit)
        case .app(let app):
            appDetailCard(app: app, candidate: candidate)
        case .calculator(let expr, let resultText, let badge):
            CalculatorLensCard(expression: expr, resultText: resultText, badge: badge) {
                viewModel.executeCandidate(candidate)
            }
        case .devTool(let tool):
            DevToolLensCard(
                tool: tool,
                onExecute: { viewModel.executeCandidate(candidate) },
                onCopyText: { val, toast in copyString(val, toast: toast) },
                onPinImage: { url in PinWindowController.shared.pinImage(at: url) }
            )
        case .snippet(let match):
            SnippetLensCard(
                match: match,
                onExecute: { viewModel.executeCandidate(candidate) },
                onOpenSettings: { viewModel.openRoute(.settings(.snippets)) }
            )
        case .plugin(let plugin):
            pluginDetailCard(plugin: plugin, candidate: candidate)
        case .command(let cmd):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    SquircleBadge(symbol: cmd.symbol, topColor: .cyan, bottomColor: .blue, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cmd.title).font(.headline).foregroundStyle(LiquidColors.textPrimary)
                        LiquidStatusPill(title: cmd.badgeLabel, tint: .cyan)
                    }
                }
                Text(cmd.subtitle).font(.caption).foregroundStyle(LiquidColors.textSecondary)
                Spacer()
                Button("执行命令 ↩") { viewModel.executeCandidate(candidate) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
        case .clipboard:
            EmptyView()
        }
    }

    private func appDetailCard(app: InstalledAppItem, candidate: LauncherCandidate) -> some View {
        let pinned = usageTracker.isPinned(app)
        let summary = usageTracker.usageSummary(for: app)
        return VStack(spacing: 11) {
            Spacer(minLength: 0)
            Image(nsImage: IconCache.shared.appIcon(for: app.url))
                .resizable()
                .frame(width: 68, height: 68)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            Text(app.name).font(.headline).foregroundStyle(LiquidColors.textPrimary)
            LiquidStatusPill(title: summary, symbol: pinned ? "pin.fill" : "clock", tint: pinned ? .orange : .cyan)
            Text(app.url.path)
                .font(.caption2.monospaced())
                .foregroundStyle(LiquidColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Spacer(minLength: 0)
            VStack(spacing: 7) {
                HStack(spacing: 7) {
                    Button("启动应用 ↩") { viewModel.executeCandidate(candidate) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                    Button("访达 ⌘R") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                        .buttonStyle(GlassPillButtonStyle())
                }
                Button {
                    usageTracker.togglePin(app)
                } label: {
                    Label(pinned ? "取消钉住" : "钉在常用栏", systemImage: pinned ? "pin.slash" : "pin.fill")
                }
                .buttonStyle(GlassPillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func pluginDetailCard(plugin: PluginDescriptor, candidate: LauncherCandidate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SquircleBadge(symbol: plugin.manifest.icon ?? "puzzlepiece.extension.fill", topColor: .purple, bottomColor: .indigo, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.manifest.name).font(.headline).foregroundStyle(LiquidColors.textPrimary)
                    LiquidStatusPill(title: plugin.manifest.mode.rawValue.uppercased(), tint: .purple)
                }
            }
            Text(plugin.manifest.description).font(.caption).foregroundStyle(LiquidColors.textSecondary)
            LiquidSectionDivider()
            MetadataLabel(key: "ID", val: plugin.id)
            MetadataLabel(key: "关键词", val: plugin.manifest.keywords.joined(separator: ", "))
            Spacer()
            HStack(spacing: 8) {
                Button("运行插件 ↩") { viewModel.executeCandidate(candidate) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
                Button("配置") { viewModel.openRoute(.settings(.plugins)) }
                    .buttonStyle(GlassPillButtonStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    @ViewBuilder
    private func fileActionStrip(for hit: EverythingSearchHit) -> some View {
        let canDedicatedWindow = [.markdown, .text, .image, .video].contains(hit.mediaKind)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if canDedicatedWindow {
                    Button(hit.mediaKind == .video ? "影院播放" : "独立窗口") {
                        viewModel.openMediaWindow(for: hit.url, kind: hit.mediaKind)
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
                } else {
                    Button("打开 ↩") { viewModel.executeEverythingHit(hit) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                }
                if hit.mediaKind == .image {
                    Button("复制图片") {
                        _ = ScreenshotCompositor.copyImageFileToPasteboard(at: hit.url)
                        viewModel.serviceMessage = "图片已复制到剪贴板"
                    }
                    .buttonStyle(GlassPillButtonStyle())
                }
                Button("访达 ⌘R") { NSWorkspace.shared.activateFileViewerSelecting([hit.url]) }
                    .buttonStyle(GlassPillButtonStyle())
            }
            if hit.mediaKind == .image {
                HStack(spacing: 6) {
                    Button("贴图置顶") { PinWindowController.shared.pinImage(at: hit.url) }
                        .buttonStyle(GlassPillButtonStyle())
                    Button("看图置顶") { viewModel.openMediaWindow(for: hit.url, kind: .image, pinOnTop: true) }
                        .buttonStyle(GlassPillButtonStyle())
                }
            } else if hit.mediaKind == .video {
                Button("视频置顶") { viewModel.openMediaWindow(for: hit.url, kind: .video, pinOnTop: true) }
                    .buttonStyle(GlassPillButtonStyle())
            }
        }
    }

    private func copyString(_ value: String, toast: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        viewModel.serviceMessage = toast
    }
}

private struct MetadataLabel: View {
    let key: String
    let val: String
    var body: some View {
        HStack {
            Text(key).font(.caption).foregroundStyle(LiquidColors.textSecondary)
            Spacer()
            Text(val).font(.caption.monospaced()).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
        }
    }
}
