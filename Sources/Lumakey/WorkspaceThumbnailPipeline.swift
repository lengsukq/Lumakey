import AppKit
import LumakeyCore
import SwiftUI

actor ThumbnailDecodeGate {
    static let shared = ThumbnailDecodeGate(maxConcurrent: 4)

    private let maxConcurrent: Int
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func acquire() async {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            activeCount = max(0, activeCount - 1)
        }
    }
}

@MainActor
final class WorkspaceThumbnailCache {
    static let shared = WorkspaceThumbnailCache()

    private let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 200
        c.totalCostLimit = 32 * 1024 * 1024
        return c
    }()

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: NSImage, for url: URL, costBytes: Int) {
        cache.setObject(image, forKey: url as NSURL, cost: max(1, costBytes))
    }

    func clearAll() {
        cache.removeAllObjects()
    }
}

@MainActor
private final class WorkspaceThumbLoader: ObservableObject {
    @Published var thumbnail: NSImage?
    private var task: Task<Void, Never>?

    func loadIfNeeded(for entry: FileEntry) {
        if let cached = WorkspaceThumbnailCache.shared.image(for: entry.url) {
            thumbnail = cached
            return
        }
        guard !entry.isDirectory, [.image, .video, .pdf].contains(entry.mediaKind) else {
            thumbnail = nil
            return
        }
        task?.cancel()
        let url = entry.url
        task = Task {
            await ThumbnailDecodeGate.shared.acquire()
            defer { Task { await ThumbnailDecodeGate.shared.release() } }
            guard !Task.isCancelled else { return }

            let loaded = await Task.detached(priority: .utility) {
                MediaClassifier.makeThumbnail(at: url, maxPixelSize: 220)
            }.value
            guard !Task.isCancelled, let loaded else { return }
            let cost = loaded.bytesPerRow * loaded.height
            let img = NSImage(cgImage: loaded, size: .zero)
            WorkspaceThumbnailCache.shared.store(img, for: url, costBytes: cost)
            self.thumbnail = img
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

struct WorkspaceThumbStage: View {
    let entry: FileEntry
    let size: CGFloat
    @StateObject private var loader = WorkspaceThumbLoader()

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LiquidColors.pillSurface.opacity(0.65))
                if let img = loader.thumbnail {
                    Image(nsImage: img).resizable().scaledToFit().padding(4)
                } else {
                    Image(nsImage: IconCache.shared.icon(for: entry))
                        .resizable().scaledToFit().frame(width: size * 0.56, height: size * 0.56)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer(minLength: 0)
        }
        .onAppear { loader.loadIfNeeded(for: entry) }
        .onChange(of: entry.id) { _, _ in loader.loadIfNeeded(for: entry) }
        .onDisappear { loader.cancel() }
    }
}
