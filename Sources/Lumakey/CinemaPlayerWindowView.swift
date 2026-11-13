import AppKit
import AVKit
import LumakeyCore
import SwiftUI

struct CinemaVideoPlayerSheet: View {
    let initialURL: URL
    let siblingURLs: [URL]
    let windowKey: String
    let onClose: () -> Void
    @StateObject private var state = CinemaPlayerController()
    @ObservedObject private var windowPins = WindowLevelStore.shared

    private var activeURL: URL { state.currentURL ?? initialURL }
    private var isCompact: Bool { windowPins.isCompact(windowKey) }
    private var hudVisible: Bool { state.showHUD || state.isLoading || state.errorReason != nil || state.showEpisodeDrawer }

    var body: some View {
        ZStack(alignment: .trailing) {
            Color(red: 0.04, green: 0.045, blue: 0.06).ignoresSafeArea()
            if let player = state.player { CinemaPlayerNSView(player: player) { state.pokeHUD() }.ignoresSafeArea() }
            if state.isLoading { loadingCard }
            if let reason = state.errorReason { errorCard(reason: reason) }
            VStack(spacing: 0) {
                if hudVisible { topHUDBar.transition(.opacity.combined(with: .move(edge: .top))) }
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(.container, edges: .top)
            if state.showEpisodeDrawer && !isCompact { episodeDrawer.transition(.move(edge: .trailing).combined(with: .opacity)) }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 460, minHeight: 260)
        .onAppear { state.configureAndLoad(initialURL: initialURL, providedSiblings: siblingURLs, startCompact: isCompact) }
        .onDisappear { state.stop(); _ = onClose }
    }

    private var topHUDBar: some View {
        let playlist = state.playlistURLs
        let idx = playlist.firstIndex(of: activeURL) ?? 0
        let subtitle = "\(activeURL.deletingLastPathComponent().lastPathComponent) · \(idx + 1)/\(max(1, playlist.count))"
        return HStack(spacing: isCompact ? 6 : 8) {
            SquircleBadge(symbol: "film.fill", topColor: .cyan, bottomColor: .indigo, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(activeURL.lastPathComponent).font(.callout.weight(.semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                    if !isCompact, let badge = state.metadata?.codecBadge {
                        Text(badge).font(.system(size: 10, weight: .semibold)).foregroundStyle(.cyan)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 7).padding(.vertical, 2).background(Color.cyan.opacity(0.16), in: Capsule())
                    }
                }
                if !isCompact { Text(subtitle).font(.caption2).foregroundStyle(.white.opacity(0.65)).lineLimit(1).truncationMode(.middle) }
            }
            .frame(minWidth: 60, maxWidth: .infinity, alignment: .leading).layoutPriority(-1)
            ViewThatFits(in: .horizontal) {
                topHUDControls(playlistCount: playlist.count, compactLabels: false)
                topHUDControls(playlistCount: playlist.count, compactLabels: true)
            }
            .layoutPriority(1)
        }
        .padding(.leading, 78).padding(.trailing, 14).padding(.top, 9).padding(.bottom, 16)
        .background(LinearGradient(colors: [Color.black.opacity(0.84), Color.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom))
    }

    private func topHUDControls(playlistCount: Int, compactLabels: Bool) -> some View {
        HStack(spacing: compactLabels ? 4 : 5) {
            if playlistCount > 1 && !isCompact { CinemaCapsuleButton(symbol: "backward.end.fill") { state.stepEpisode(by: -1) } }
            if !isCompact {
                CinemaCapsuleButton(symbol: "gobackward.10") { state.seek(by: -10) }
                CinemaCapsuleButton(symbol: "goforward.10") { state.seek(by: 10) }
            }
            if playlistCount > 1 && !isCompact { CinemaCapsuleButton(symbol: "forward.end.fill") { state.stepEpisode(by: 1) } }
            if !isCompact {
                rateMenuButton
                let listTitle = compactLabels ? "\(playlistCount)" : "播放列表 (\(playlistCount))"
                CinemaCapsuleButton(symbol: "list.bullet", label: listTitle, active: state.showEpisodeDrawer) { state.toggleEpisodeDrawer() }
            }
            WindowPinPillButton(key: windowKey, title: "置顶", darkAppearance: true)
            let pipTitle: String? = compactLabels && !isCompact ? nil : (isCompact ? "还原" : "小窗")
            CinemaCapsuleButton(symbol: isCompact ? "pip.exit" : "pip.enter", label: pipTitle, active: isCompact) {
                if !isCompact { state.showEpisodeDrawer = false }
                windowPins.toggleCompact(forKey: windowKey)
            }
            if !isCompact {
                CinemaCapsuleButton(symbol: "arrow.up.forward.app", label: compactLabels ? nil : "IINA") { state.openInExternalPlayer(fallback: initialURL) }
            }
        }
    }

    private var rateMenuButton: some View {
        Menu {
            ForEach([Float(0.5), 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                Button("\(String(format: "%g", r))×") { state.setRate(r) }
            }
        } label: {
            Text("\(String(format: "%g", state.rate))×")
                .font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.white)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Color.white.opacity(0.13), in: Capsule())
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.7) }
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text("正在准备硬件解码管线…").font(.callout.weight(.semibold)).foregroundStyle(.white)
            Text(activeURL.lastPathComponent).font(.caption).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
            Button("直接用 IINA / 外部播放器打开") { state.openInExternalPlayer(fallback: initialURL) }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.9) }
    }

    private func errorCard(reason: String) -> some View {
        VStack(spacing: 12) {
            SquircleBadge(symbol: "exclamationmark.triangle.fill", topColor: .orange, bottomColor: .red, size: 42)
            Text(reason).font(.callout).foregroundStyle(.white).multilineTextAlignment(.center).frame(maxWidth: 380)
            HStack(spacing: 10) {
                Button("使用 IINA / 外部播放器打开") { state.openInExternalPlayer(fallback: initialURL) }.buttonStyle(.borderedProminent)
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([activeURL]) }.buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.9) }
    }

    private var episodeDrawer: some View {
        let items = state.filteredPlaylist
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("同目录视频 (\(state.playlistURLs.count))")
                    .font(.callout.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 4)
                Button { state.autoPlayNext.toggle() } label: {
                    Text("连播").font(.caption2.weight(.semibold)).foregroundStyle(state.autoPlayNext ? .white : .white.opacity(0.6))
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(state.autoPlayNext ? Color.cyan.opacity(0.38) : Color.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain).fixedSize(horizontal: true, vertical: false).help("播完当前视频后自动播放同目录下一集")
                Button { state.toggleEpisodeDrawer() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.7)) }
                    .buttonStyle(.plain).fixedSize()
            }
            if state.playlistURLs.count > 4 {
                TextField("筛选同目录剧集…", text: $state.episodeFilter)
                    .textFieldStyle(.plain).font(.caption).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.7) }
            }
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(items, id: \.url) { item in
                        let selected = item.url == activeURL
                        Button { state.load(url: item.url) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selected ? "speaker.wave.2.fill" : "play.circle")
                                    .font(.caption).foregroundStyle(selected ? .cyan : .white.opacity(0.65))
                                Text("\(item.index + 1). \(item.url.lastPathComponent)")
                                    .font(.caption.weight(selected ? .semibold : .regular))
                                    .foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(selected ? Color.cyan.opacity(0.24) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay { if selected { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.cyan.opacity(0.45), lineWidth: 0.8) } }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14).padding(.top, 44).frame(width: 268).frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.12)).frame(width: 0.8) }
    }
}

private struct CinemaCapsuleButton: View {
    var symbol: String? = nil
    var label: String? = nil
    var active: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                if let label { Text(label).font(.caption.weight(.medium)).lineLimit(1) }
            }
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.white).padding(.horizontal, label == nil ? 9 : 10).padding(.vertical, 5)
            .background(active ? Color.cyan.opacity(0.32) : Color.white.opacity(0.13), in: Capsule())
            .overlay { Capsule().strokeBorder(active ? Color.cyan.opacity(0.55) : Color.white.opacity(0.18), lineWidth: 0.7) }
        }
        .buttonStyle(.plain).fixedSize(horizontal: true, vertical: false)
    }
}

private struct CinemaPlayerNSView: NSViewRepresentable {
    let player: AVPlayer
    let onMouseActivity: () -> Void
    func makeNSView(context: Context) -> TrackingAVPlayerView {
        let view = TrackingAVPlayerView()
        view.controlsStyle = .floating; view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = true; view.showsFullScreenToggleButton = true
        view.onMouseActivity = onMouseActivity; view.player = player
        return view
    }
    func updateNSView(_ nsView: TrackingAVPlayerView, context: Context) {
        nsView.onMouseActivity = onMouseActivity
        if nsView.player !== player { nsView.player = player }
    }
    static func dismantleNSView(_ nsView: TrackingAVPlayerView, coordinator: ()) {
        nsView.player?.pause(); nsView.player = nil
    }
}

private final class TrackingAVPlayerView: AVPlayerView {
    var onMouseActivity: (() -> Void)?
    private var tracker: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracker { removeTrackingArea(tracker) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracker = area
    }
    override func mouseMoved(with event: NSEvent) { onMouseActivity?(); super.mouseMoved(with: event) }
    override func mouseEntered(with event: NSEvent) { onMouseActivity?(); super.mouseEntered(with: event) }
}
