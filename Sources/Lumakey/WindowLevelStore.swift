import AppKit
import SwiftUI

@MainActor
final class WindowLevelStore: ObservableObject {
    static let shared = WindowLevelStore()

    @Published private(set) var pinnedKeys: Set<String> = []
    @Published private(set) var compactKeys: Set<String> = []

    private var windowBoxes: [String: WeakWindowBox] = [:]
    private var savedNormalFrames: [String: NSRect] = [:]

    private init() {}

    func attach(window: NSWindow, key: String, initialPinned: Bool = false) {
        windowBoxes[key] = WeakWindowBox(window: window)
        if initialPinned {
            setPinned(true, forKey: key)
        } else {
            applyState(to: window, pinned: pinnedKeys.contains(key))
        }
    }

    func detach(key: String) {
        windowBoxes.removeValue(forKey: key)
        pinnedKeys.remove(key)
        compactKeys.remove(key)
        savedNormalFrames.removeValue(forKey: key)
    }

    func isPinned(_ key: String) -> Bool {
        pinnedKeys.contains(key)
    }

    func isCompact(_ key: String) -> Bool {
        compactKeys.contains(key)
    }

    func setPinned(_ pinned: Bool, forKey key: String) {
        if pinned { pinnedKeys.insert(key) } else { pinnedKeys.remove(key) }
        if let win = windowBoxes[key]?.window {
            applyState(to: win, pinned: pinned)
        }
    }

    func togglePinned(forKey key: String) {
        setPinned(!isPinned(key), forKey: key)
    }

    func toggleCompact(forKey key: String, compactSize: NSSize = NSSize(width: 520, height: 300)) {
        guard let win = windowBoxes[key]?.window else { return }
        if compactKeys.contains(key) {
            compactKeys.remove(key)
            if let restored = savedNormalFrames.removeValue(forKey: key) {
                win.setFrame(restored, display: true, animate: true)
            }
        } else {
            savedNormalFrames[key] = win.frame
            compactKeys.insert(key)
            setPinned(true, forKey: key)
            let visible = (win.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let origin = NSPoint(x: visible.maxX - compactSize.width - 20, y: visible.minY + 24)
            win.setFrame(NSRect(origin: origin, size: compactSize), display: true, animate: true)
        }
    }

    private func applyState(to window: NSWindow, pinned: Bool) {
        window.level = pinned ? .floating : .normal
        if pinned {
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        } else {
            window.collectionBehavior.remove(.canJoinAllSpaces)
        }
    }

    private struct WeakWindowBox {
        weak var window: NSWindow?
    }
}

struct WindowPinPillButton: View {
    let key: String
    var title: String = "窗口置顶"
    var darkAppearance: Bool = false
    @ObservedObject private var store = WindowLevelStore.shared

    var body: some View {
        let pinned = store.isPinned(key)
        Button {
            store.togglePinned(forKey: key)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                Text(pinned ? "已置顶" : title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(pinned ? .white : (darkAppearance ? .white.opacity(0.9) : LiquidColors.textPrimary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if pinned {
                    Capsule(style: .continuous).fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    Capsule(style: .continuous).fill(darkAppearance ? Color.white.opacity(0.13) : LiquidColors.pillSurface)
                }
            }
            .overlay {
                Capsule(style: .continuous).strokeBorder(pinned ? Color.white.opacity(0.35) : (darkAppearance ? Color.white.opacity(0.18) : LiquidColors.pillBorder), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .help("切换当前窗口全桌面置顶 (Always on Top)")
    }
}
