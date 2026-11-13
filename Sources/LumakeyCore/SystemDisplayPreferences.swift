import AppKit
import Foundation
import os

public final class SystemDisplayPreferences: Sendable {
    public struct Snapshot: Sendable, Equatable {
        public let reduceTransparency: Bool
        public let increaseContrast: Bool

        public init(reduceTransparency: Bool, increaseContrast: Bool) {
            self.reduceTransparency = reduceTransparency
            self.increaseContrast = increaseContrast
        }
    }

    public static let shared = SystemDisplayPreferences()

    private let stateLock: OSAllocatedUnfairLock<Snapshot>
    private let reader: @Sendable () -> Snapshot
    private let notificationCenter: NotificationCenter
    private nonisolated(unsafe) var observerToken: NSObjectProtocol?

    public convenience init() {
        self.init(
            notificationCenter: NSWorkspace.shared.notificationCenter,
            reader: {
                Snapshot(
                    reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                    increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                )
            }
        )
    }

    public init(
        notificationCenter: NotificationCenter,
        reader: @escaping @Sendable () -> Snapshot
    ) {
        let initial = reader()
        self.stateLock = OSAllocatedUnfairLock(initialState: initial)
        self.reader = reader
        self.notificationCenter = notificationCenter
        self.observerToken = notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let observerToken {
            notificationCenter.removeObserver(observerToken)
        }
    }

    public var reduceTransparency: Bool {
        stateLock.withLock { $0.reduceTransparency }
    }

    public var increaseContrast: Bool {
        stateLock.withLock { $0.increaseContrast }
    }

    public var snapshot: Snapshot {
        stateLock.withLock { $0 }
    }

    @discardableResult
    public func refresh() -> Snapshot {
        let next = reader()
        stateLock.withLock { $0 = next }
        return next
    }
}
