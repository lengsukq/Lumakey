import AppKit
import AVKit
import PDFKit
import SwiftUI
import LumakeyCore

struct SideLivePreviewCard: View {
    let previewState: PreviewContentState

    var body: some View {
        Group {
            switch previewState {
            case .empty:
                ContentUnavailableView("选择文件即可实时预览", systemImage: "sidebar.right")
            case .loading(let entry):
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在加载 \(entry.name)...").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .image(_, let cgImage, let dimensions):
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                    if let dimensions {
                        Text("\(Int(dimensions.width)) × \(Int(dimensions.height)) px")
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.56), in: Capsule(style: .continuous))
                            .padding(6)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            case .videoOrAudio(let entry):
                ZStack {
                    InlineAVPlayerRepresentable(url: entry.url)
                        .id(entry.id)
                        .clipShape(RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            case .pdf(let entry):
                InlinePDFRepresentable(url: entry.url)
                    .id(entry.id)
                    .clipShape(RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
            case .markdown(_, let blocks, let truncated):
                VStack(alignment: .leading, spacing: 6) {
                    ScrollView {
                        MarkdownBlocksStackView(blocks: Array(blocks.prefix(24)), baseFontSize: 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if truncated || blocks.count > 24 {
                        Text("点击「独立窗口打开」查看完整排版与大纲")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            case .text(_, let content, let truncated):
                VStack(alignment: .leading, spacing: 4) {
                    ScrollView {
                        Text(content)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    if truncated {
                        Text("仅显示前 16 KB（安全有界预览）").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            case .folderOrGeneric(let entry):
                VStack(spacing: 10) {
                    Image(nsImage: IconCache.shared.icon(for: entry))
                        .resizable().frame(width: 56, height: 56)
                    Text(entry.name).font(.caption.weight(.medium)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }
}

struct InlineAVPlayerRepresentable: NSViewRepresentable {
    let url: URL

    @MainActor
    final class Coordinator {
        let registryToken = UUID()
        var currentURL: URL?
        var loadTask: Task<Void, Never>?

        func load(url: URL, into view: AVPlayerView) {
            if let existingPlayer = view.player {
                PreviewPlaybackRegistry.shared.register(token: registryToken, player: existingPlayer)
            }
            guard currentURL != url else { return }
            currentURL = url
            loadTask?.cancel()
            view.player?.pause()
            view.player?.replaceCurrentItem(with: nil)
            let epochAtStart = PreviewPlaybackRegistry.shared.pauseEpoch
            loadTask = Task { [weak self, weak view] in
                let resolved = await VideoPlaybackCompat.preparePlayback(for: url, allowFFmpegRemux: false)
                guard !Task.isCancelled, let self, let view, self.currentURL == url else {
                    if case .ready(_, _, let temp) = resolved, let temp {
                        try? FileManager.default.removeItem(at: temp)
                    }
                    return
                }
                let activePlayer: AVPlayer
                switch resolved {
                case .ready(let item, _, _):
                    if let existing = view.player {
                        existing.replaceCurrentItem(with: item)
                        activePlayer = existing
                    } else {
                        let created = AVPlayer(playerItem: item)
                        view.player = created
                        activePlayer = created
                    }
                case .unsupported:
                    let created = AVPlayer(url: url)
                    view.player = created
                    activePlayer = created
                }
                PreviewPlaybackRegistry.shared.register(token: self.registryToken, player: activePlayer)
                if PreviewPlaybackRegistry.shared.pauseEpoch != epochAtStart {
                    activePlayer.pause()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        context.coordinator.load(url: url, into: view)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        context.coordinator.load(url: url, into: nsView)
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        PreviewPlaybackRegistry.shared.unregister(token: coordinator.registryToken)
        coordinator.loadTask?.cancel()
        coordinator.loadTask = nil
        nsView.player?.pause()
        nsView.player?.replaceCurrentItem(with: nil)
        nsView.player = nil
    }
}

struct InlinePDFRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}
