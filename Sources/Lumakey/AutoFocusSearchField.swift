import AppKit
import SwiftUI

enum OverlayKeyAction: Sendable {
    case moveUp
    case moveDown
    case submit
    case escape
    case cycleMode
    case togglePreview
    case revealInFinder
    case openSettings
}

private final class CrispSearchTextField: NSTextField {
    override var allowsVibrancy: Bool { false }
}

struct AutoFocusSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusToken: Int
    let onAction: (OverlayKeyAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = CrispSearchTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 18, weight: .medium)
        field.textColor = LiquidColors.primaryNSColor
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        applyPlaceholder(placeholder, to: field)
        context.coordinator.lastPlaceholder = placeholder
        context.coordinator.installMonitor(for: field)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if context.coordinator.lastPlaceholder != placeholder {
            applyPlaceholder(placeholder, to: nsView)
            context.coordinator.lastPlaceholder = placeholder
        }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                guard let window = nsView.window else { return }
                window.makeFirstResponder(nsView)
                if let editor = window.fieldEditor(false, for: nsView) as? NSTextView {
                    let len = (nsView.stringValue as NSString).length
                    editor.setSelectedRange(NSRange(location: len, length: 0))
                }
            }
        }
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    private func applyPlaceholder(_ text: String, to field: NSTextField) {
        field.placeholderAttributedString = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: LiquidColors.placeholderNSColor,
                .font: NSFont.systemFont(ofSize: 16, weight: .medium)
            ]
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AutoFocusSearchField
        var lastFocusToken: Int = -1
        var lastPlaceholder: String = ""
        private var keyMonitor: Any?

        init(parent: AutoFocusSearchField) {
            self.parent = parent
        }

        func installMonitor(for field: NSTextField) {
            removeMonitor()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self, weak field] event in
                guard let self, let field, let win = field.window, win.isKeyWindow, event.window === win else {
                    return event
                }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if event.type == .leftMouseDown, flags.contains(.command) {
                    win.performDrag(with: event)
                    return nil
                }
                if event.type == .keyDown, flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
                    switch key {
                    case "y":
                        self.parent.onAction(.togglePreview)
                        return nil
                    case "r":
                        self.parent.onAction(.revealInFinder)
                        return nil
                    case ",":
                        self.parent.onAction(.openSettings)
                        return nil
                    default:
                        break
                    }
                }
                return event
            }
        }

        func removeMonitor() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onAction(.moveUp)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onAction(.moveDown)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onAction(.submit)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onAction(.escape)
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onAction(.cycleMode)
                return true
            default:
                return false
            }
        }
    }
}
