import AppKit
import SwiftUI
import LumakeyCore

struct SidePreviewPanelView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("侧边实时预览").font(.headline)
                Spacer()
                if let entry = viewModel.selectedEntry {
                    Text(entry.mediaKind.badgeTitle)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }

            SideLivePreviewCard(previewState: viewModel.previewState)
                .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity, alignment: .center)

            if let entry = viewModel.selectedEntry {
                entryMetadataCard(entry)
                if !viewModel.ocrResultText.isEmpty || !viewModel.barcodeResults.isEmpty {
                    visionResultCard
                }
                quickActionsRow(entry)
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }

    @ViewBuilder
    private func entryMetadataCard(_ entry: FileEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.name).font(.callout.weight(.semibold)).lineLimit(2)
            MetadataLine(label: "大小", value: entry.formattedSize)
            MetadataLine(label: "修改时间", value: entry.formattedDate)
            if !entry.tags.isEmpty {
                MetadataLine(label: "Finder 标签", value: entry.tags.joined(separator: ", "))
            }
            if !entry.isDirectory {
                HStack {
                    Text("SHA-256").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if viewModel.isComputingSHA256 {
                        ProgressView().controlSize(.small)
                    } else if let hash = viewModel.computedSHA256 {
                        Text(String(hash.prefix(16)) + "…")
                            .font(.caption2.monospaced())
                            .help(hash)
                    } else {
                        Button("计算校验") { viewModel.computeSHA256ForSelection() }
                            .buttonStyle(GlassPillButtonStyle())
                    }
                }
            }
        }
        .padding(10)
        .liquidGlassCard(cornerRadius: LiquidRadii.row, solidReadable: true)
    }

    @ViewBuilder
    private var visionResultCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("识别结果").font(.caption.weight(.semibold))
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.ocrResultText, forType: .string)
                }
                .buttonStyle(GlassPillButtonStyle())
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if !viewModel.ocrResultText.isEmpty {
                        Text(viewModel.ocrResultText)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    if !viewModel.barcodeResults.isEmpty {
                        Text("条码: \(viewModel.barcodeResults.joined(separator: ", "))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: 96)
        }
        .padding(8)
        .liquidGlassCard(cornerRadius: LiquidRadii.row, solidReadable: true)
    }

    @ViewBuilder
    private func quickActionsRow(_ entry: FileEntry) -> some View {
        let siblingsImages = viewModel.activePaneState.visibleEntries.filter { $0.mediaKind == .image }.map(\.url)
        let siblingsVideos = viewModel.activePaneState.visibleEntries.filter { $0.mediaKind == .video }.map(\.url)
        let siblingsDocs = viewModel.activePaneState.visibleEntries.filter { $0.mediaKind == .markdown || $0.mediaKind == .text }.map(\.url)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if entry.mediaKind == .image {
                    Button("大图查看") { viewModel.openRoute(.imageViewer(entry.url, siblingsImages, false)) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                    Button("看图置顶") { viewModel.openRoute(.imageViewer(entry.url, siblingsImages, true)) }
                        .buttonStyle(GlassPillButtonStyle())
                    Button("贴图置顶") { PinWindowController.shared.pinImage(at: entry.url) }
                        .buttonStyle(GlassPillButtonStyle())
                } else if entry.mediaKind == .video {
                    Button("独立窗口播放") {
                        PreviewPlaybackRegistry.shared.pauseAll()
                        viewModel.openRoute(.videoPlayer(entry.url, siblingsVideos, false))
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
                    Button("视频置顶") {
                        PreviewPlaybackRegistry.shared.pauseAll()
                        viewModel.openRoute(.videoPlayer(entry.url, siblingsVideos, true))
                    }
                    .buttonStyle(GlassPillButtonStyle())
                } else if entry.mediaKind == .audio {
                    Button("外部播放器打开") {
                        PreviewPlaybackRegistry.shared.pauseAll()
                        NSWorkspace.shared.open(entry.url)
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
                } else if entry.mediaKind == .markdown || entry.mediaKind == .text {
                    Button("独立窗口阅读") { viewModel.openRoute(.documentReader(entry.url, siblingsDocs)) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                }
                Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                    .buttonStyle(GlassPillButtonStyle())
            }
            if entry.mediaKind == .image {
                HStack(spacing: 8) {
                    Button("OCR 识字") { viewModel.analyzeImageWithVision(at: entry.url) }
                        .buttonStyle(GlassPillButtonStyle())
                    Button("主体抠图") { viewModel.liftSubject(at: entry.url) }
                        .buttonStyle(GlassPillButtonStyle())
                }
            }
        }
    }
}

private struct MetadataLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit()).lineLimit(1)
        }
    }
}
