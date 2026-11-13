import AppKit
import Carbon
import Foundation

public enum HotKeyConflictSeverity: String, Codable, Sendable, Comparable {
    case none, warning, error
    private var rank: Int { switch self { case .none: 0; case .warning: 1; case .error: 2 } }
    public static func < (lhs: HotKeyConflictSeverity, rhs: HotKeyConflictSeverity) -> Bool { lhs.rank < rhs.rank }
}

public enum HotKeyConflictKind: String, Codable, Sendable, Equatable {
    case internalDuplicate
    case systemShortcut
    case externalAppOccupied
}

public struct ExternalPluginHotKey: Sendable, Equatable, Hashable {
    public let pluginID: String
    public let pluginName: String
    public let chord: HotKeyChord
    public init(pluginID: String, pluginName: String, chord: HotKeyChord) {
        self.pluginID = pluginID; self.pluginName = pluginName; self.chord = chord
    }
}

public struct SymbolicHotKeyEntry: Sendable, Equatable {
    public let id: Int
    public let title: String
    public let chord: HotKeyChord
    public init(id: Int, title: String, chord: HotKeyChord) {
        self.id = id; self.title = title; self.chord = chord
    }
}

public struct HotKeyConflictIssue: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(kind.rawValue):\(sourceTitle)" }
    public let kind: HotKeyConflictKind
    public let severity: HotKeyConflictSeverity
    public let sourceTitle: String
    public let detail: String
    public let suggestion: String
    public init(kind: HotKeyConflictKind, severity: HotKeyConflictSeverity, sourceTitle: String, detail: String, suggestion: String) {
        self.kind = kind; self.severity = severity; self.sourceTitle = sourceTitle
        self.detail = detail; self.suggestion = suggestion
    }
}

public struct HotKeyConflictReport: Codable, Sendable, Equatable {
    public let action: HotKeyActionID
    public let chord: HotKeyChord?
    public let isEnabled: Bool
    public let registrationSucceeded: Bool?
    public let severity: HotKeyConflictSeverity
    public let issues: [HotKeyConflictIssue]

    public var hasConflict: Bool { severity != .none && !issues.isEmpty }
    public var primaryIssue: HotKeyConflictIssue? { issues.max(by: { $0.severity < $1.severity }) ?? issues.first }
    public var summaryText: String {
        if !isEnabled { return "已停用" }
        guard chord != nil else { return "未绑定" }
        if let primary = primaryIssue { return primary.sourceTitle }
        return registrationSucceeded == true ? "已生效 · 无冲突" : "可用 · 无冲突"
    }
}

public enum HotKeyConflictDetector {
    private static let probeSignature: OSType = 0x4C4D_5052

    public static func analyzeAll(
        config: HotKeyBindingConfig, pluginHotKeys: [ExternalPluginHotKey] = [],
        registrationStatus: [HotKeyActionID: Bool] = [:], ownedChords: Set<HotKeyChord> = [],
        symbolicHotKeysPlist: [String: Any]? = nil, probeExternalProcesses: Bool = true
    ) -> [HotKeyActionID: HotKeyConflictReport] {
        let systemEntries = resolveSystemEntries(injectedPlist: symbolicHotKeysPlist)
        var effectiveOwned = ownedChords
        for (action, ok) in registrationStatus where ok {
            if let chord = config.effectiveChord(for: action) { effectiveOwned.insert(chord) }
        }
        var reports: [HotKeyActionID: HotKeyConflictReport] = [:]
        for action in HotKeyActionID.allCases {
            let entry = config.binding(for: action)
            guard entry.isEnabled, let chord = entry.chord else {
                reports[action] = HotKeyConflictReport(
                    action: action, chord: entry.chord, isEnabled: entry.isEnabled,
                    registrationSucceeded: nil, severity: .none, issues: []
                )
                continue
            }
            reports[action] = buildReport(
                chord: chord, action: action, config: config, pluginHotKeys: pluginHotKeys,
                registrationSucceeded: registrationStatus[action], ownedChords: effectiveOwned,
                systemEntries: systemEntries, probeExternal: probeExternalProcesses
            )
        }
        return reports
    }

    public static func analyzeChord(
        _ chord: HotKeyChord, for action: HotKeyActionID = .launcher,
        config: HotKeyBindingConfig = .defaultConfig, pluginHotKeys: [ExternalPluginHotKey] = [],
        registrationSucceeded: Bool? = nil, ownedChords: Set<HotKeyChord> = [],
        symbolicHotKeysPlist: [String: Any]? = nil, probeExternalProcesses: Bool = true
    ) -> HotKeyConflictReport {
        buildReport(
            chord: chord, action: action, config: config, pluginHotKeys: pluginHotKeys,
            registrationSucceeded: registrationSucceeded, ownedChords: ownedChords,
            systemEntries: resolveSystemEntries(injectedPlist: symbolicHotKeysPlist), probeExternal: probeExternalProcesses
        )
    }

    private static func resolveSystemEntries(injectedPlist: [String: Any]?) -> [SymbolicHotKeyEntry] {
        if let injectedPlist { return parseSymbolicHotKeys(from: injectedPlist, includeDefaultScreenshotsWhenMissing: false) }
        return parseSymbolicHotKeys(from: loadSystemSymbolicHotKeysPlist() ?? [:], includeDefaultScreenshotsWhenMissing: true)
    }

    private static func buildReport(
        chord: HotKeyChord, action: HotKeyActionID, config: HotKeyBindingConfig,
        pluginHotKeys: [ExternalPluginHotKey], registrationSucceeded: Bool?,
        ownedChords: Set<HotKeyChord>, systemEntries: [SymbolicHotKeyEntry], probeExternal: Bool
    ) -> HotKeyConflictReport {
        var issues: [HotKeyConflictIssue] = []
        if let validationErr = chord.validationError {
            issues.append(HotKeyConflictIssue(
                kind: .internalDuplicate, severity: .error, sourceTitle: "无效组合键",
                detail: validationErr, suggestion: "请使用包含 ⌘ / ⌥ / ⌃ 的组合键或 F1–F20 功能键。"
            ))
        }
        for other in HotKeyActionID.allCases where other != action && config.effectiveChord(for: other) == chord {
            issues.append(HotKeyConflictIssue(
                kind: .internalDuplicate, severity: .error, sourceTitle: "内部重复：\(other.title)",
                detail: "与 Lumakey「\(other.title)」使用了相同的快捷键 \(chord.displayString)",
                suggestion: "请修改其中一个动作的按键，或关闭另一项动作。"
            ))
        }
        for plugin in pluginHotKeys where plugin.chord == chord {
            issues.append(HotKeyConflictIssue(
                kind: .internalDuplicate, severity: .error, sourceTitle: "插件冲突：\(plugin.pluginName)",
                detail: "与扩展插件「\(plugin.pluginName)」的热键 \(chord.displayString) 重复",
                suggestion: "请更换该动作或对应扩展插件的快捷键。"
            ))
        }
        if let reservedName = reservedSystemShortcuts[chord] {
            issues.append(HotKeyConflictIssue(
                kind: .systemShortcut, severity: .error, sourceTitle: "系统保留键：\(reservedName)",
                detail: "\(chord.displayString) 属于 macOS 高危应用级保留快捷键（\(reservedName)）",
                suggestion: "强烈建议加入 ⌥ 或 ⌃ 修饰键（例如 ⌥\(chord.displayString)），避免拦截系统核心操作。"
            ))
        }
        for sys in systemEntries where sys.chord == chord {
            issues.append(HotKeyConflictIssue(
                kind: .systemShortcut, severity: .warning, sourceTitle: "与 \(sys.title) 冲突",
                detail: "macOS 系统快捷键「\(sys.title)」(#\(sys.id)) 当前已启用 \(chord.displayString)",
                suggestion: "更换其他组合键，或在「系统设置 → 键盘 → 键盘快捷键」中关闭对应系统热键。"
            ))
        }
        let hasInternalDup = issues.contains { $0.kind == .internalDuplicate }
        if !hasInternalDup && !ownedChords.contains(chord) && chord.isValidGlobalShortcut {
            if registrationSucceeded == false || (probeExternal && probeChordOccupiedByExternalProcess(chord, ownedChords: ownedChords)) {
                issues.append(HotKeyConflictIssue(
                    kind: .externalAppOccupied, severity: .warning, sourceTitle: "已被其他运行中应用占用",
                    detail: "Carbon 热键探测返回已存在 (-9878)，可能已被 Raycast / Alfred / Snipaste / uTools / Bob 等抢占",
                    suggestion: "请关闭外部工具中的同款全局热键，或为 Lumakey 换用未占用组合键。"
                ))
            }
        }
        return HotKeyConflictReport(
            action: action, chord: chord, isEnabled: true, registrationSucceeded: registrationSucceeded,
            severity: issues.map(\.severity).max() ?? .none, issues: issues
        )
    }

    public static func probeChordOccupiedByExternalProcess(_ chord: HotKeyChord, ownedChords: Set<HotKeyChord> = []) -> Bool {
        guard chord.isValidGlobalShortcut, !ownedChords.contains(chord) else { return false }
        let probeID = EventHotKeyID(signature: probeSignature, id: 0xFFFF)
        var tempRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(chord.keyCode), UInt32(chord.carbonModifiers), probeID, GetApplicationEventTarget(), 0, &tempRef
        )
        if let tempRef { UnregisterEventHotKey(tempRef) }
        return status == OSStatus(eventHotKeyExistsErr)
    }

    public static func loadSystemSymbolicHotKeysPlist() -> [String: Any]? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/com.apple.symbolichotkeys.plist")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    public static func parseSymbolicHotKeys(
        from plist: [String: Any], includeDefaultScreenshotsWhenMissing: Bool = false
    ) -> [SymbolicHotKeyEntry] {
        let table = (plist["AppleSymbolicHotKeys"] as? [String: Any]) ?? plist
        var entries: [SymbolicHotKeyEntry] = []
        var seenIDs = Set<Int>()
        for (key, rawVal) in table {
            guard let id = Int(key), let item = rawVal as? [String: Any] else { continue }
            seenIDs.insert(id)
            guard (item["enabled"] as? Bool) ?? (item["enabled"] as? NSNumber)?.boolValue ?? false else { continue }
            let title = symbolicHotKeyCatalog[id]?.title ?? "macOS 系统快捷键 #\(id)"
            if let valueDict = item["value"] as? [String: Any], let params = valueDict["parameters"] as? [Any],
               params.count >= 3, let rawKeyCode = asInt(params[1]), let rawFlags = asInt(params[2]),
               rawKeyCode >= 0 && rawKeyCode != 65535 {
                let chord = HotKeyChord(keyCode: rawKeyCode, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(max(0, rawFlags))))
                entries.append(SymbolicHotKeyEntry(id: id, title: title, chord: chord))
            } else if let fallback = symbolicHotKeyCatalog[id]?.defaultChord {
                entries.append(SymbolicHotKeyEntry(id: id, title: title, chord: fallback))
            }
        }
        if includeDefaultScreenshotsWhenMissing {
            for id in [28, 29, 30, 31, 184] where !seenIDs.contains(id) {
                if let meta = symbolicHotKeyCatalog[id], let fallback = meta.defaultChord {
                    entries.append(SymbolicHotKeyEntry(id: id, title: meta.title, chord: fallback))
                }
            }
        }
        return entries.sorted { $0.id < $1.id }
    }

    private static func asInt(_ value: Any) -> Int? { (value as? Int) ?? (value as? NSNumber)?.intValue }

    private static let reservedSystemShortcuts: [HotKeyChord: String] = [
        HotKeyChord(keyCode: kVK_ANSI_Q, carbonModifiers: Int(cmdKey)): "退出当前应用",
        HotKeyChord(keyCode: kVK_ANSI_W, carbonModifiers: Int(cmdKey)): "关闭当前窗口",
        HotKeyChord(keyCode: kVK_ANSI_H, carbonModifiers: Int(cmdKey)): "隐藏当前应用",
        HotKeyChord(keyCode: kVK_ANSI_M, carbonModifiers: Int(cmdKey)): "最小化当前窗口",
        HotKeyChord(keyCode: kVK_Tab, carbonModifiers: Int(cmdKey)): "系统应用切换器",
        HotKeyChord(keyCode: kVK_ANSI_Comma, carbonModifiers: Int(cmdKey)): "打开应用偏好设置"
    ]

    private static let symbolicHotKeyCatalog: [Int: (title: String, defaultChord: HotKeyChord?)] = [
        28: ("系统全屏截图保存为文件", HotKeyChord(keyCode: kVK_ANSI_3, carbonModifiers: Int(shiftKey | cmdKey))),
        29: ("系统全屏截图复制到剪贴板", HotKeyChord(keyCode: kVK_ANSI_3, carbonModifiers: Int(controlKey | shiftKey | cmdKey))),
        30: ("系统选区截图保存为文件", HotKeyChord(keyCode: kVK_ANSI_4, carbonModifiers: Int(shiftKey | cmdKey))),
        31: ("系统选区截图复制到剪贴板", HotKeyChord(keyCode: kVK_ANSI_4, carbonModifiers: Int(controlKey | shiftKey | cmdKey))),
        32: ("调度中心 (Mission Control)", HotKeyChord(keyCode: kVK_UpArrow, carbonModifiers: Int(controlKey))),
        33: ("应用程序窗口 (App Exposé)", HotKeyChord(keyCode: kVK_DownArrow, carbonModifiers: Int(controlKey))),
        34: ("调度中心（慢速）", nil), 35: ("应用程序窗口（慢速）", nil),
        36: ("显示桌面", HotKeyChord(keyCode: kVK_F11, carbonModifiers: 0)), 37: ("显示桌面（慢速）", nil),
        52: ("程序坞自动隐藏切换", HotKeyChord(keyCode: kVK_ANSI_D, carbonModifiers: Int(optionKey | cmdKey))),
        60: ("切换上一个输入法", HotKeyChord(keyCode: kVK_Space, carbonModifiers: Int(controlKey))),
        61: ("切换下一个输入源", HotKeyChord(keyCode: kVK_Space, carbonModifiers: Int(controlKey | optionKey))),
        64: ("Spotlight 聚焦搜索", HotKeyChord(keyCode: kVK_Space, carbonModifiers: Int(cmdKey))),
        65: ("访达聚焦搜索窗口", HotKeyChord(keyCode: kVK_Space, carbonModifiers: Int(optionKey | cmdKey))),
        79: ("向左切换桌面空间", HotKeyChord(keyCode: kVK_LeftArrow, carbonModifiers: Int(controlKey))),
        80: ("向右切换桌面空间", HotKeyChord(keyCode: kVK_RightArrow, carbonModifiers: Int(controlKey))),
        160: ("启动台 (Launchpad)", nil), 175: ("Siri 语音助手", nil),
        184: ("系统截图与录屏面板", HotKeyChord(keyCode: kVK_ANSI_5, carbonModifiers: Int(shiftKey | cmdKey))),
        190: ("快速备忘录", nil), 222: ("台前调度 (Stage Manager)", nil)
    ]
}
