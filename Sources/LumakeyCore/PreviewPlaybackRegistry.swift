import AVFoundation
import Foundation

public final class PreviewPlaybackRegistry: @unchecked Sendable {
    public static let shared = PreviewPlaybackRegistry()

    private struct WeakPlayerBox {
        weak var player: AVPlayer?
    }

    private let lock = NSLock()
    private var boxes: [UUID: WeakPlayerBox] = [:]
    private var currentPauseEpoch: UInt64 = 0

    private init() {}

    public var pauseEpoch: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return currentPauseEpoch
    }

    public var activeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        boxes = boxes.filter { $0.value.player != nil }
        return boxes.count
    }

    public func register(token: UUID, player: AVPlayer) {
        lock.lock()
        boxes[token] = WeakPlayerBox(player: player)
        lock.unlock()
    }

    public func unregister(token: UUID) {
        lock.lock()
        boxes.removeValue(forKey: token)
        lock.unlock()
    }

    public func pauseAll() {
        lock.lock()
        currentPauseEpoch &+= 1
        boxes = boxes.filter { $0.value.player != nil }
        let players = boxes.values.compactMap(\.player)
        lock.unlock()
        for player in players {
            player.pause()
        }
    }
}
