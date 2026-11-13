import AppKit
import Carbon
import Foundation
import LumakeyCore

func testV070HotKeyConflict() throws {
    // 1. HotKeyActionID metadata & defaults coverage
    check(HotKeyActionID.allCases.count == 10, "HotKeyActionID has all 10 global actions")
    let uniqueNumericIDs = Set(HotKeyActionID.allCases.map(\.carbonHotKeyNumericID))
    check(uniqueNumericIDs.count == HotKeyActionID.allCases.count, "HotKeyActionID numeric Carbon IDs are unique")
    for action in HotKeyActionID.allCases {
        check(!action.title.isEmpty && !action.subtitle.isEmpty && !action.symbolName.isEmpty, "HotKeyActionID \(action) metadata non-empty")
    }
    check(HotKeyActionID.launcher.defaultChord?.displayString == "⌥Space", "launcher defaults to ⌥Space")
    check(HotKeyActionID.gifRecord.defaultChord?.displayString == "⌥G", "gifRecord defaults to ⌥G")
    check(HotKeyActionID.quickBackup.defaultChord == nil, "quickBackup defaults to nil (optional)")

    // 2. HotKeyChord formatting, NSEvent.ModifierFlags conversion & legality validation
    let ctrlOptCmdSpace = HotKeyChord(keyCode: kVK_Space, modifierFlags: [.control, .option, .command])
    check(ctrlOptCmdSpace.displayString == "⌃⌥⌘Space", "⌃⌥⌘Space display formatting, got \(ctrlOptCmdSpace.displayString)")
    check(ctrlOptCmdSpace.modifierFlags == [.control, .option, .command], "NSEvent.ModifierFlags bidirectional roundtrip")
    check(ctrlOptCmdSpace.isValidGlobalShortcut, "⌃⌥⌘Space is valid global shortcut")
    check(HotKeyChord.parse("⌃⌥⌘Space") == ctrlOptCmdSpace, "HotKeyChord.parse parses ⌃⌥⌘Space")

    let shiftCmd4 = HotKeyChord(keyCode: kVK_ANSI_4, modifierFlags: [.shift, .command])
    check(shiftCmd4.displayString == "⇧⌘4", "⇧⌘4 display formatting, got \(shiftCmd4.displayString)")
    check(HotKeyChord.parse("⇧⌘4") == shiftCmd4, "HotKeyChord.parse parses ⇧⌘4")

    let bareLetterA = HotKeyChord(keyCode: kVK_ANSI_A, carbonModifiers: 0)
    check(!bareLetterA.isValidGlobalShortcut && bareLetterA.validationError != nil, "bare letter single key rejected")
    let shiftOnlyA = HotKeyChord(keyCode: kVK_ANSI_A, carbonModifiers: Int(shiftKey))
    check(!shiftOnlyA.isValidGlobalShortcut, "Shift+letter without ⌘/⌥/⌃ rejected to prevent typing accidents")
    let pureCmdKey = HotKeyChord(keyCode: kVK_Command, carbonModifiers: Int(cmdKey))
    check(!pureCmdKey.isValidGlobalShortcut, "pure modifier keyCode rejected")
    let bareF12 = HotKeyChord(keyCode: kVK_F12, carbonModifiers: 0)
    check(bareF12.isValidGlobalShortcut && bareF12.displayString == "F12", "function key F1..F20 valid without modifiers")

    // 3. HotKeyBindingConfig JSON persistence roundtrip & restoreDefaults
    let tmp = try makeTempDir("v070-hotkeys")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let jsonURL = tmp.appendingPathComponent("hotkeys.json")

    var cfg = HotKeyBindingConfig.defaultConfig
    let customBackupChord = HotKeyChord(keyCode: kVK_ANSI_B, modifierFlags: [.control, .option])
    cfg.setChord(customBackupChord, for: .quickBackup)
    cfg.setEnabled(false, for: .files)
    check(cfg.effectiveChord(for: .files) == nil, "disabled action returns nil effectiveChord")
    check(cfg.effectiveChord(for: .quickBackup) == customBackupChord, "custom quickBackup chord active")

    cfg.save(to: jsonURL)
    let loaded = HotKeyBindingConfig.load(from: jsonURL)
    check(loaded == cfg, "HotKeyBindingConfig JSON roundtrip matches")
    var restored = loaded
    restored.restoreDefaults()
    check(restored == .defaultConfig, "restoreDefaults resets to defaultConfig")

    // 4. Layer 1: Internal duplicate & plugin hotkey conflict detection
    var dupCfg = HotKeyBindingConfig.defaultConfig
    let optG = HotKeyChord(keyCode: kVK_ANSI_G, carbonModifiers: Int(optionKey))
    dupCfg.setChord(optG, for: .launcher)
    let pluginChord = HotKeyChord(keyCode: kVK_ANSI_C, carbonModifiers: Int(optionKey))
    let pluginList = [ExternalPluginHotKey(pluginID: "fast-trans", pluginName: "极速翻译", chord: pluginChord)]

    let mockEmptyPlist: [String: Any] = ["AppleSymbolicHotKeys": [:]]
    let dupReports = HotKeyConflictDetector.analyzeAll(
        config: dupCfg, pluginHotKeys: pluginList,
        symbolicHotKeysPlist: mockEmptyPlist, probeExternalProcesses: false
    )
    check(dupReports[.launcher]?.issues.contains(where: { $0.kind == .internalDuplicate }) == true, "launcher detects internal duplicate with gifRecord")
    check(dupReports[.gifRecord]?.issues.contains(where: { $0.kind == .internalDuplicate }) == true, "gifRecord detects internal duplicate with launcher")
    check(dupReports[.launcher]?.severity == .error, "internal duplicate has .error severity")
    check(
        dupReports[.clipboard]?.issues.contains(where: { $0.kind == .internalDuplicate && $0.sourceTitle.contains("极速翻译") }) == true,
        "clipboard detects duplicate conflict with plugin hotkey"
    )

    dupCfg.setEnabled(false, for: .gifRecord)
    let afterDisableReports = HotKeyConflictDetector.analyzeAll(
        config: dupCfg, symbolicHotKeysPlist: mockEmptyPlist, probeExternalProcesses: false
    )
    check(afterDisableReports[.launcher]?.hasConflict == false, "disabling conflicting action clears internal duplicate")

    // 5. Layer 2: macOS com.apple.symbolichotkeys & high-risk reserved shortcuts
    let mockSymbolicPlist: [String: Any] = [
        "AppleSymbolicHotKeys": [
            "64": [
                "enabled": true,
                "value": ["type": "standard", "parameters": [65535, kVK_Space, Int(NSEvent.ModifierFlags.command.rawValue)]]
            ],
            "30": [
                "enabled": true,
                "value": ["type": "standard", "parameters": [52, kVK_ANSI_4, Int(NSEvent.ModifierFlags([.shift, .command]).rawValue)]]
            ],
            "60": [
                "enabled": false,
                "value": ["type": "standard", "parameters": [32, kVK_Space, Int(NSEvent.ModifierFlags.control.rawValue)]]
            ],
            "79": [
                "enabled": true
            ]
        ]
    ]

    let cmdSpace = HotKeyChord(keyCode: kVK_Space, modifierFlags: [.command])
    let spotlightRep = HotKeyConflictDetector.analyzeChord(
        cmdSpace, symbolicHotKeysPlist: mockSymbolicPlist, probeExternalProcesses: false
    )
    check(
        spotlightRep.issues.contains(where: { $0.kind == .systemShortcut && $0.sourceTitle.contains("Spotlight") }),
        "detects Spotlight (⌘Space) conflict from symbolichotkeys #64"
    )

    let shotRep = HotKeyConflictDetector.analyzeChord(
        shiftCmd4, symbolicHotKeysPlist: mockSymbolicPlist, probeExternalProcesses: false
    )
    check(
        shotRep.issues.contains(where: { $0.kind == .systemShortcut && $0.sourceTitle.contains("截图") }),
        "detects macOS Screenshot (⇧⌘4) conflict from symbolichotkeys #30"
    )

    let ctrlSpace = HotKeyChord(keyCode: kVK_Space, modifierFlags: [.control])
    let disabledInputRep = HotKeyConflictDetector.analyzeChord(
        ctrlSpace, symbolicHotKeysPlist: mockSymbolicPlist, probeExternalProcesses: false
    )
    check(!disabledInputRep.hasConflict, "disabled symbolichotkeys entry (#60 enabled=false) does NOT false-report")

    let ctrlLeft = HotKeyChord(keyCode: kVK_LeftArrow, modifierFlags: [.control])
    let spaceSwitchRep = HotKeyConflictDetector.analyzeChord(
        ctrlLeft, symbolicHotKeysPlist: mockSymbolicPlist, probeExternalProcesses: false
    )
    check(spaceSwitchRep.hasConflict, "enabled symbolichotkeys entry without value dict (#79) resolves default ⌃← conflict")

    let reservedChords: [HotKeyChord] = [
        HotKeyChord(keyCode: kVK_ANSI_Q, modifierFlags: [.command]),
        HotKeyChord(keyCode: kVK_ANSI_W, modifierFlags: [.command]),
        HotKeyChord(keyCode: kVK_ANSI_H, modifierFlags: [.command]),
        HotKeyChord(keyCode: kVK_ANSI_M, modifierFlags: [.command]),
        HotKeyChord(keyCode: kVK_Tab, modifierFlags: [.command]),
        HotKeyChord(keyCode: kVK_ANSI_Comma, modifierFlags: [.command])
    ]
    for rc in reservedChords {
        let rep = HotKeyConflictDetector.analyzeChord(rc, symbolicHotKeysPlist: mockEmptyPlist, probeExternalProcesses: false)
        check(rep.severity == .error && rep.issues.contains(where: { $0.kind == .systemShortcut }), "high-risk reserved key \(rc.displayString) flagged as .error")
    }

    // 6. Layer 3: External app occupied diagnosis & zero-leak Carbon probe
    let failedRegReports = HotKeyConflictDetector.analyzeAll(
        config: .defaultConfig,
        registrationStatus: [.launcher: false],
        symbolicHotKeysPlist: mockEmptyPlist,
        probeExternalProcesses: false
    )
    check(
        failedRegReports[.launcher]?.issues.contains(where: { $0.kind == .externalAppOccupied }) == true,
        "failed Carbon registration reports .externalAppOccupied"
    )

    let rareChord = HotKeyChord(keyCode: kVK_F19, modifierFlags: [.control, .option, .shift, .command])
    let probe1 = HotKeyConflictDetector.probeChordOccupiedByExternalProcess(rareChord)
    let probe2 = HotKeyConflictDetector.probeChordOccupiedByExternalProcess(rareChord)
    check(probe1 == probe2, "Carbon probe immediately unregisters temporary EventHotKeyRef without leaking handle")
    check(
        HotKeyConflictDetector.probeChordOccupiedByExternalProcess(rareChord, ownedChords: [rareChord]) == false,
        "ownedChords bypasses self-conflict during Carbon probe"
    )
    check(HotKeyChord.parse("ctrl+opt+g")?.displayString == "⌃⌥G", "HotKeyChord.parse supports textual modifier aliases")
    check(HotKeyChord.parse("") == nil && HotKeyChord.parse("invalidkey") == nil, "HotKeyChord.parse rejects invalid input")
    check(failedRegReports[.quickBackup]?.summaryText == "未绑定", "unbound action summaryText is 未绑定")

    print("[ok] v0.7.0 HotKeyModels + 3-Layer HotKeyConflictDetector + Carbon Probe")
}
