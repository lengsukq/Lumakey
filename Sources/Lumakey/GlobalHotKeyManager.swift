import Carbon
import Foundation

@MainActor
final class GlobalHotKeyManager {
    nonisolated static let signature: OSType = 0x4C4D_4B59
    static weak var activeInstance: GlobalHotKeyManager?

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actions: [Int: () -> Void] = [:]

    init() {
        Self.activeInstance = self
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr && hotKeyID.signature == GlobalHotKeyManager.signature {
                    let id = Int(hotKeyID.id)
                    Task { @MainActor in
                        GlobalHotKeyManager.activeInstance?.actions[id]?()
                    }
                }
                return noErr
            },
            1,
            &spec,
            nil,
            &handlerRef
        )
    }

    func registerDefaultShortcuts(
        onLauncher: @escaping () -> Void,
        onFiles: @escaping () -> Void,
        onClipboard: @escaping () -> Void,
        onCapturePin: @escaping () -> Void,
        onCaptureOCR: @escaping () -> Void,
        onWorkspace: @escaping () -> Void,
        onToggleMonitor: @escaping () -> Void,
        onNetworkMonitor: @escaping () -> Void
    ) {
        unregisterHotKeysOnly()
        register(id: 1, keyCode: kVK_Space, modifiers: optionKey, action: onLauncher)
        register(id: 2, keyCode: kVK_ANSI_F, modifiers: optionKey, action: onFiles)
        register(id: 3, keyCode: kVK_ANSI_C, modifiers: optionKey, action: onClipboard)
        register(id: 4, keyCode: kVK_ANSI_A, modifiers: optionKey, action: onCapturePin)
        register(id: 5, keyCode: kVK_ANSI_O, modifiers: optionKey, action: onCaptureOCR)
        register(id: 6, keyCode: kVK_ANSI_E, modifiers: optionKey, action: onWorkspace)
        register(id: 7, keyCode: kVK_ANSI_M, modifiers: optionKey, action: onToggleMonitor)
        register(id: 8, keyCode: kVK_ANSI_N, modifiers: optionKey, action: onNetworkMonitor)
    }

    func register(id: Int, keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        actions[id] = action
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(id))
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
        }
    }

    private func unregisterHotKeysOnly() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        actions.removeAll()
    }

    func unregisterAll() {
        unregisterHotKeysOnly()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
