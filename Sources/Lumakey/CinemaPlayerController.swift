import AppKit
import AVFoundation
import CoreMedia
import Foundation
import LumakeyCore
import SwiftUI

@MainActor
final class CinemaPlayerController: ObservableObject {
    @Published var player: AVPlayer?
    @Published var rate: Float = 1.0
    @Published var currentURL: URL?
    @Published var playlistURLs: [URL] = []
    @Published var episodeFilter: String = ""
    @Published var autoPlayNext: Bool = true
    @Published var isLoading: Bool = true
    @Published var errorReason: String?
    @Published var metadata: VideoStreamMetadata?
    @Published var showHUD: Bool = true
    @Published var showEpisodeDrawer: Bool = false

    private var tempRemuxURL: URL?
    private var loadTask: Task<Void, Never>?
    private var hudHideTask: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?

    func configureAndLoad(initialURL: URL, providedSiblings: [URL], startCompact: Bool = false) {
        let resolvedList: [URL]
        if providedSiblings.count > 1 {
            resolvedList = providedSiblings.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
        } else {
            resolvedList = MediaClassifier.siblingMediaURLs(around: initialURL, matching: [.video])
        }
        playlistURLs = resolvedList.isEmpty ? [initialURL] : resolvedList
        showEpisodeDrawer = !startCompact && playlistURLs.count > 1
        load(url: initialURL)
    }

    var filteredPlaylist: [(index: Int, url: URL)] {
        let needle = episodeFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        return playlistURLs.enumerated().compactMap { idx, url in
            if !needle.isEmpty && !url.lastPathComponent.localizedCaseInsensitiveContains(needle) {
                return nil
            }
            return (idx, url)
        }
    }

    func load(url: URL) {
        PreviewPlaybackRegistry.shared.pauseAll()
        loadTask?.cancel()
        stopPlayerOnly()
        cleanupTempFile()

        currentURL = url
        isLoading = true
        errorReason = nil
        metadata = nil
        showHUD = true

        loadTask = Task { [weak self] in
            let resolved = await VideoPlaybackCompat.preparePlayback(for: url, allowFFmpegRemux: true)
            guard !Task.isCancelled, let self else {
                if case .ready(_, _, let temp) = resolved, let temp { try? FileManager.default.removeItem(at: temp) }
                return
            }
            switch resolved {
            case .ready(let item, let meta, let tempURL):
                self.tempRemuxURL = tempURL
                self.metadata = meta
                let avPlayer = AVPlayer(playerItem: item)
                self.installEndObserver(for: item)
                self.player = avPlayer
                avPlayer.play()
                avPlayer.rate = self.rate
                self.isLoading = false
                self.scheduleHUDHide()
            case .unsupported(let reason):
                self.isLoading = false
                self.errorReason = reason
            }
        }
    }

    func stepEpisode(by delta: Int) {
        guard playlistURLs.count > 1, let active = currentURL else { return }
        let idx = playlistURLs.firstIndex(of: active) ?? 0
        let next = (idx + delta + playlistURLs.count) % playlistURLs.count
        load(url: playlistURLs[next])
    }

    func seek(by seconds: Double) {
        pokeHUD()
        guard let player else { return }
        let target = CMTimeMaximum(.zero, CMTimeAdd(player.currentTime(), CMTime(seconds: seconds, preferredTimescale: 600)))
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setRate(_ newValue: Float) {
        rate = newValue
        pokeHUD()
        if player?.timeControlStatus == .playing { player?.rate = newValue }
    }

    func pokeHUD() {
        if !showHUD {
            withAnimation(.easeOut(duration: 0.16)) { showHUD = true }
        }
        scheduleHUDHide()
    }

    func toggleEpisodeDrawer() {
        withAnimation(.easeInOut(duration: 0.2)) { showEpisodeDrawer.toggle() }
        pokeHUD()
    }

    func openInExternalPlayer(fallback: URL) {
        player?.pause()
        PreviewPlaybackRegistry.shared.pauseAll()
        let target = currentURL ?? fallback
        let iinaURL = URL(fileURLWithPath: "/Applications/IINA.app")
        if FileManager.default.fileExists(atPath: iinaURL.path) {
            NSWorkspace.shared.open([target], withApplicationAt: iinaURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(target)
        }
    }

    func stop() {
        loadTask?.cancel(); loadTask = nil
        hudHideTask?.cancel(); hudHideTask = nil
        stopPlayerOnly()
        cleanupTempFile()
    }

    private func installEndObserver(for item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.autoPlayNext, self.playlistURLs.count > 1 else { return }
                self.stepEpisode(by: 1)
            }
        }
    }

    private func scheduleHUDHide() {
        hudHideTask?.cancel()
        hudHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled, let self else { return }
            if self.player?.timeControlStatus == .playing && !self.showEpisodeDrawer {
                withAnimation(.easeOut(duration: 0.28)) { self.showHUD = false }
            }
        }
    }

    private func stopPlayerOnly() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func cleanupTempFile() {
        if let tempRemuxURL {
            try? FileManager.default.removeItem(at: tempRemuxURL)
            self.tempRemuxURL = nil
        }
    }
}
