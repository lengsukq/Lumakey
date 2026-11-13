import AppKit
import Carbon
import Foundation

public enum HotKeyActionID: String, CaseIterable, Codable, Sendable, Identifiable {
    case launcher
    case files
    case clipboard
    case screenshotPin
    case screenshotOCR
    case gifRecord
    case workspace
    case systemPulse
    case networkMonitor
    case quickBackup

    public var id: String { rawValue }
    public var carbonHotKeyNumericID: UInt32 { meta.numID }
    public var title: String { meta.title }
    public var subtitle: String { meta.subtitle }
    public var symbolName: String { meta.symbol }
    public var defaultChord: HotKeyChord? { meta.defaultChord }

    private var meta: (numID: UInt32, title: String, subtitle: String, symbol: String, defaultChord: HotKeyChord?) {
        let opt = Int(optionKey)
        return switch self {
        case .launcher: (1, "全局统一快捷中枢", "毫秒呼出应用启动、文件检索、算式换算与快捷指令", "sparkles", HotKeyChord(keyCode: kVK_Space, carbonModifiers: opt))
        case .files: (2, "Everything 极速搜文件", "直达全盘与外置磁盘文件秒搜及右侧预览", "magnifyingglass", HotKeyChord(keyCode: kVK_ANSI_F, carbonModifiers: opt))
        case .clipboard: (3, "智能剪贴板历史库", "检索历史文本、#HEX 色值、图片与文件路径", "doc.on.clipboard.fill", HotKeyChord(keyCode: kVK_ANSI_C, carbonModifiers: opt))
        case .screenshotPin: (4, "选区截图与标注钉屏", "窗口自动吸附、放大镜取色、涂鸦马赛克与桌面钉图", "camera.viewfinder", HotKeyChord(keyCode: kVK_ANSI_A, carbonModifiers: opt))
        case .screenshotOCR: (5, "选区截图离线识字", "Apple Vision 离线极速识别中英文本与二维码", "text.viewfinder", HotKeyChord(keyCode: kVK_ANSI_O, carbonModifiers: opt))
        case .workspace: (6, "双栏文件与磁盘工作台", "多标签双栏文件浏览、批量重命名与只读媒体预览", "externaldrive.fill", HotKeyChord(keyCode: kVK_ANSI_E, carbonModifiers: opt))
        case .systemPulse: (7, "系统脉搏监控悬浮窗", "开启或隐藏 CPU、频率、内存、功耗与实时网速浮窗", "waveform.path.ecg", HotKeyChord(keyCode: kVK_ANSI_M, carbonModifiers: opt))
        case .networkMonitor: (8, "本机网络流量与去向", "实时拆解进程网速、远端 IP 域名去向与连接状态", "network", HotKeyChord(keyCode: kVK_ANSI_N, carbonModifiers: opt))
        case .gifRecord: (9, "区域 / 窗口 GIF 录制", "框选区域或吸附窗口录制高帧率轻量 GIF 动图", "record.circle.fill", HotKeyChord(keyCode: kVK_ANSI_G, carbonModifiers: opt))
        case .quickBackup: (10, "一键快速备份设置", "可选绑定 · 按下即触发配置快照导出或云端同步备份", "externaldrive.badge.icloud", nil)
        }
    }
}

public struct HotKeyChord: Codable, Sendable, Hashable, Equatable {
    public static let supportedCarbonMask: Int = Int(cmdKey | optionKey | controlKey | shiftKey)
    private static let primaryCarbonMask: Int = Int(cmdKey | optionKey | controlKey)

    public var keyCode: Int
    public var carbonModifiers: Int

    public init(keyCode: Int, carbonModifiers: Int) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers & Self.supportedCarbonMask
    }

    public init(keyCode: Int, modifierFlags: NSEvent.ModifierFlags) {
        self.init(keyCode: keyCode, carbonModifiers: Self.carbonModifiers(from: modifierFlags))
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        let clean = flags.intersection(.deviceIndependentFlagsMask)
        var mask = 0
        if clean.contains(.command) { mask |= Int(cmdKey) }
        if clean.contains(.option) { mask |= Int(optionKey) }
        if clean.contains(.control) { mask |= Int(controlKey) }
        if clean.contains(.shift) { mask |= Int(shiftKey) }
        return mask
    }

    public var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if (carbonModifiers & Int(cmdKey)) != 0 { flags.insert(.command) }
        if (carbonModifiers & Int(optionKey)) != 0 { flags.insert(.option) }
        if (carbonModifiers & Int(controlKey)) != 0 { flags.insert(.control) }
        if (carbonModifiers & Int(shiftKey)) != 0 { flags.insert(.shift) }
        return flags
    }

    public var isFunctionKey: Bool { Self.functionKeyMap[keyCode] != nil }
    public var isPureModifierKey: Bool { Self.modifierOnlyKeyCodes.contains(keyCode) }

    public var isValidGlobalShortcut: Bool {
        guard keyCode >= 0, !isPureModifierKey, Self.keyLabel(for: keyCode) != nil else { return false }
        return isFunctionKey || (carbonModifiers & Self.primaryCarbonMask) != 0
    }

    public var validationError: String? {
        if isPureModifierKey || keyCode < 0 || Self.keyLabel(for: keyCode) == nil {
            return "请按下完整的主键组合（不能只按修饰键）"
        }
        if !isFunctionKey && (carbonModifiers & Self.primaryCarbonMask) == 0 {
            return "普通按键必须包含 ⌘、⌥ 或 ⌃ 至少一个修饰键，防止打字误触"
        }
        return nil
    }

    public var displayString: String {
        var out = ""
        if (carbonModifiers & Int(controlKey)) != 0 { out.append("⌃") }
        if (carbonModifiers & Int(optionKey)) != 0 { out.append("⌥") }
        if (carbonModifiers & Int(shiftKey)) != 0 { out.append("⇧") }
        if (carbonModifiers & Int(cmdKey)) != 0 { out.append("⌘") }
        out.append(Self.keyLabel(for: keyCode) ?? "Key\(keyCode)")
        return out
    }

    public static func parse(_ raw: String) -> HotKeyChord? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        var mods = 0
        let tokens: [(String, Int)] = [
            ("⌃", Int(controlKey)), ("ctrl+", Int(controlKey)), ("control+", Int(controlKey)),
            ("⌥", Int(optionKey)), ("opt+", Int(optionKey)), ("alt+", Int(optionKey)), ("option+", Int(optionKey)),
            ("⇧", Int(shiftKey)), ("shift+", Int(shiftKey)), ("⌘", Int(cmdKey)), ("cmd+", Int(cmdKey)), ("command+", Int(cmdKey))
        ]
        while let match = tokens.first(where: { s.lowercased().hasPrefix($0.0) }) {
            mods |= match.1
            s = String(s.dropFirst(match.0.count)).trimmingCharacters(in: .whitespaces)
        }
        let target = s.uppercased()
        guard let (code, _) = allKeyLabels.first(where: { $0.value.uppercased() == target }) else { return nil }
        return HotKeyChord(keyCode: code, carbonModifiers: mods)
    }

    public static func keyLabel(for keyCode: Int) -> String? { allKeyLabels[keyCode] }

    private static let modifierOnlyKeyCodes: Set<Int> = [
        kVK_Command, kVK_Shift, kVK_CapsLock, kVK_Option, kVK_Control,
        kVK_RightCommand, kVK_RightShift, kVK_RightOption, kVK_RightControl, kVK_Function
    ]

    private static let functionKeyMap: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]

    private static let allKeyLabels: [Int: String] = {
        var map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
            kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
            kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
            kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "Tab", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "Esc",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "PgUp", kVK_PageDown: "PgDn",
            kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Semicolon: ";",
            kVK_ANSI_Quote: "'", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Backslash: "\\", kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_Grave: "`"
        ]
        map.merge(functionKeyMap) { lhs, _ in lhs }
        return map
    }()
}

public struct HotKeyActionBinding: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var chord: HotKeyChord?

    public init(isEnabled: Bool = true, chord: HotKeyChord?) {
        self.isEnabled = isEnabled
        self.chord = chord
    }
}

public struct HotKeyBindingConfig: Codable, Sendable, Equatable {
    public var schemaVersion: Int = 1
    public var rawBindings: [String: HotKeyActionBinding]

    public static let defaultConfig = HotKeyBindingConfig()

    public init() {
        var initial: [String: HotKeyActionBinding] = [:]
        for action in HotKeyActionID.allCases {
            initial[action.rawValue] = HotKeyActionBinding(isEnabled: true, chord: action.defaultChord)
        }
        self.rawBindings = initial
    }

    public func binding(for action: HotKeyActionID) -> HotKeyActionBinding {
        rawBindings[action.rawValue] ?? HotKeyActionBinding(isEnabled: true, chord: action.defaultChord)
    }

    public func effectiveChord(for action: HotKeyActionID) -> HotKeyChord? {
        let entry = binding(for: action)
        guard entry.isEnabled, let chord = entry.chord, chord.isValidGlobalShortcut else { return nil }
        return chord
    }

    public mutating func setChord(_ chord: HotKeyChord?, for action: HotKeyActionID) {
        var entry = binding(for: action)
        entry.chord = chord
        if chord != nil { entry.isEnabled = true }
        rawBindings[action.rawValue] = entry
    }

    public mutating func setEnabled(_ isEnabled: Bool, for action: HotKeyActionID) {
        var entry = binding(for: action)
        entry.isEnabled = isEnabled
        rawBindings[action.rawValue] = entry
    }

    public mutating func restoreDefault(for action: HotKeyActionID) {
        rawBindings[action.rawValue] = HotKeyActionBinding(isEnabled: true, chord: action.defaultChord)
    }

    public mutating func restoreDefaults() { self = .defaultConfig }

    public static func defaultConfigURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Lumakey", isDirectory: true).appendingPathComponent("hotkeys.json")
    }

    public static func load(from url: URL = defaultConfigURL()) -> HotKeyBindingConfig {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(HotKeyBindingConfig.self, from: data)
        else { return .defaultConfig }
        var merged = HotKeyBindingConfig.defaultConfig
        for action in HotKeyActionID.allCases {
            if let saved = decoded.rawBindings[action.rawValue] { merged.rawBindings[action.rawValue] = saved }
        }
        return merged
    }

    public func save(to url: URL = defaultConfigURL()) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: url, options: .atomic) }
    }
}
