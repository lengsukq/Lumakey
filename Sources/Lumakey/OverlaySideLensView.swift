import AppKit
import LumakeyCore
import SwiftUI

struct OverlaySideLensView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let inline = viewModel.inlineResultBody {
                inlineOutputLens(inline)
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
    private func candidateDetailLens(_ candidate: LauncherCandidate) -> some View {
        switch candidate.kind {
        case .fileHit(let hit):
            SideLivePreviewCard(previewState: viewModel.previewState)
                .frame(maxHeight: .infinity)
            fileActionStrip(for: hit)
        case .app(let app):
            VStack(spacing: 12) {
                Image(nsImage: IconCache.shared.appIcon(for: app.url))
                    .resizable().frame(width: 68, height: 68)
                Text(app.name).font(.headline).foregroundStyle(LiquidColors.textPrimary)
                Text(app.url.path).font(.caption2.monospaced()).foregroundStyle(LiquidColors.textSecondary).multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Button("启动应用") { viewModel.executeCandidate(candidate) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                    Button("访达") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                        .buttonStyle(GlassPillButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
        case .calculator(let expr, let resultText, let badge):
            VStack(spacing: 10) {
                Text(badge).font(.caption.weight(.semibold)).foregroundStyle(.cyan)
                Text(resultText).font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(LiquidColors.textPrimary)
                    .textSelection(.enabled)
                Text(expr).font(.caption.monospaced()).foregroundStyle(LiquidColors.textSecondary)
                Button("复制结果 ↩") { viewModel.executeCandidate(candidate) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
        case .plugin(let plugin):
            VStack(alignment: .leading, spacing: 10) {
                Text(plugin.manifest.name).font(.headline).foregroundStyle(LiquidColors.textPrimary)
                Text(plugin.manifest.description).font(.caption).foregroundStyle(LiquidColors.textSecondary)
                MetadataLabel(key: "ID", val: plugin.id)
                MetadataLabel(key: "关键词", val: plugin.manifest.keywords.joined(separator: ", "))
                Spacer()
                Button("运行插件 ↩") { viewModel.executeCandidate(candidate) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
        case .command(let cmd):
            VStack(alignment: .leading, spacing: 10) {
                SquircleBadge(symbol: cmd.symbol, topColor: .cyan, bottomColor: .blue, size: 40)
                Text(cmd.title).font(.headline).foregroundStyle(LiquidColors.textPrimary)
                Text(cmd.subtitle).font(.caption).foregroundStyle(LiquidColors.textSecondary)
                Spacer()
                Button("执行命令 ↩") { viewModel.executeCandidate(candidate) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
        case .clipboard:
            EmptyView()
        }
    }

    @ViewBuilder
    private func fileActionStrip(for hit: EverythingSearchHit) -> some View {
        let canDedicatedWindow = [.markdown, .text, .image, .video].contains(hit.mediaKind)
        HStack(spacing: 6) {
            if canDedicatedWindow {
                Button(hit.mediaKind == .video ? "影院播放" : "独立窗口") {
                    viewModel.openMediaWindow(for: hit.url, kind: hit.mediaKind)
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true))
            } else {
                Button("打开") { viewModel.executeEverythingHit(hit) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
            if hit.mediaKind == .image {
                Button("贴图置顶") { PinWindowController.shared.pinImage(at: hit.url) }
                    .buttonStyle(GlassPillButtonStyle())
                Button("看图置顶") { viewModel.openMediaWindow(for: hit.url, kind: .image, pinOnTop: true) }
                    .buttonStyle(GlassPillButtonStyle())
            } else if hit.mediaKind == .video {
                Button("视频置顶") { viewModel.openMediaWindow(for: hit.url, kind: .video, pinOnTop: true) }
                    .buttonStyle(GlassPillButtonStyle())
            }
            Button("访达") { NSWorkspace.shared.activateFileViewerSelecting([hit.url]) }
                .buttonStyle(GlassPillButtonStyle())
        }
    }

    private func inlineOutputLens(_ inline: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.inlineResultTitle).font(.callout.weight(.semibold))
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(inline, forType: .string)
                    viewModel.serviceMessage = "已复制输出内容"
                }
                .buttonStyle(GlassPillButtonStyle())
                Button {
                    viewModel.inlineResultBody = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(GlassPillButtonStyle())
            }
            ScrollView {
                Text(inline)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(10)
            .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
        }
    }

    @ViewBuilder
    private func clipboardDetailLens(_ clip: ClipboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .colorHex(let hex) = clip.payloadKind, let swatch = LiquidColors.color(fromHex: hex) {
                RoundedRectangle(cornerRadius: LiquidRadii.card, style: .continuous)
                    .fill(swatch)
                    .frame(height: 110)
                    .overlay(alignment: .bottomLeading) {
                        Text(hex).font(.headline.monospaced()).foregroundStyle(.white).padding(10)
                    }
            } else if case .image(let url, _) = clip.payloadKind, let img = NSImage(contentsOf: url) {
                ZStack {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                }
                .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 240, alignment: .center)
                .padding(6)
                .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
            }
            ScrollView {
                Text(clip.textValue ?? clip.fileURL?.path ?? clip.title)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(10)
            .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)

            HStack(spacing: 6) {
                Button("复制粘贴板") { viewModel.executeClipboardEntry(clip) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
                Button(clip.isPinned ? "取消收藏" : "收藏") { viewModel.toggleClipboardPin(clip) }
                    .buttonStyle(GlassPillButtonStyle())
                if case .image(let url, _) = clip.payloadKind {
                    Button("贴图置顶") { PinWindowController.shared.pinImage(at: url) }
                        .buttonStyle(GlassPillButtonStyle())
                    Button("看图置顶") { viewModel.openMediaWindow(for: url, kind: .image, pinOnTop: true) }
                        .buttonStyle(GlassPillButtonStyle())
                }
            }
        }
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
