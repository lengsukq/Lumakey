import AppKit
import Carbon
import LumakeyCore
import SwiftUI

private final class LocalKeyEventMonitorBox {
    var token: Any?
    func stop() { if let token { NSEvent.removeMonitor(token); self.token = nil } }
    deinit { if let token { NSEvent.removeMonitor(token) } }
}

@MainActor
final class HotKeySettingsViewState: ObservableObject {
    @Published var config: HotKeyBindingConfig
    @Published var reports: [HotKeyActionID: HotKeyConflictReport] = [:]
    @Published var recordingAction: HotKeyActionID?
    @Published var transientMessage: String?

    private let monitorBox = LocalKeyEventMonitorBox()
    private weak var customManager: GlobalHotKeyManager?
    var pluginHotKeys: [ExternalPluginHotKey]
    var onConfigChanged: ((HotKeyBindingConfig) -> Void)?

    init(hotKeyManager: GlobalHotKeyManager? = nil, pluginHotKeys: [ExternalPluginHotKey] = [], onConfigChanged: ((HotKeyBindingConfig) -> Void)? = nil) {
        self.customManager = hotKeyManager; self.pluginHotKeys = pluginHotKeys; self.onConfigChanged = onConfigChanged
        self.config = (hotKeyManager ?? GlobalHotKeyManager.activeInstance)?.currentConfig ?? HotKeyBindingConfig.load()
    }

    var activeBoundCount: Int { HotKeyActionID.allCases.filter { config.effectiveChord(for: $0) != nil }.count }
    var conflictActions: [HotKeyActionID] { HotKeyActionID.allCases.filter { reports[$0]?.hasConflict == true } }

    func onViewAppear() {
        config = (customManager ?? GlobalHotKeyManager.activeInstance)?.currentConfig ?? HotKeyBindingConfig.load()
        scanAllConflicts(announce: false)
    }

    func scanAllConflicts(announce: Bool) {
        let mgr = customManager ?? GlobalHotKeyManager.activeInstance
        reports = HotKeyConflictDetector.analyzeAll(
            config: config, pluginHotKeys: pluginHotKeys,
            registrationStatus: mgr?.registrationResults ?? [:], ownedChords: mgr?.ownedChords ?? [],
            probeExternalProcesses: true
        )
        if announce {
            transientMessage = conflictActions.isEmpty
                ? "全面扫描完成：全部 \(activeBoundCount) 项启用热键均无冲突"
                : "扫描完成：检测到 \(conflictActions.count) 项按键冲突，请按提示调整"
        }
    }

    func toggleRecording(for action: HotKeyActionID) {
        if recordingAction == action { stopRecording() } else { startRecording(for: action) }
    }

    func startRecording(for action: HotKeyActionID) {
        monitorBox.stop()
        recordingAction = action
        transientMessage = "正在录制「\(action.title)」· 按 Esc 取消，按 ⌫ 清空绑定"
        monitorBox.token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = Int(event.keyCode)
            let rawFlags = event.modifierFlags
            let consumed = MainActor.assumeIsolated { self?.handleKeyDown(code: code, rawFlags: rawFlags) ?? false }
            return consumed ? nil : event
        }
    }

    func stopRecording() { monitorBox.stop(); recordingAction = nil }

    private func handleKeyDown(code: Int, rawFlags: NSEvent.ModifierFlags) -> Bool {
        guard let action = recordingAction else { return false }
        if HotKeyChord(keyCode: code, carbonModifiers: 0).isPureModifierKey { return true }
        let flags = rawFlags.intersection([.command, .option, .control, .shift])
        if code == kVK_Escape && flags.isEmpty {
            stopRecording(); transientMessage = "已取消快捷键录制"; return true
        }
        if (code == kVK_Delete || code == kVK_ForwardDelete) && flags.intersection([.command, .option, .control]).isEmpty {
            stopRecording()
            var next = config; next.setChord(nil, for: action)
            applyAndPersist(next, feedback: "已清空「\(action.title)」的快捷键")
            return true
        }
        let chord = HotKeyChord(keyCode: code, modifierFlags: flags)
        if let err = chord.validationError { transientMessage = err; return true }
        stopRecording()
        var next = config; next.setChord(chord, for: action)
        applyAndPersist(next, feedback: "已将「\(action.title)」绑定为 \(chord.displayString)")
        return true
    }

    func setActionEnabled(_ enabled: Bool, for action: HotKeyActionID) {
        stopRecording(); var next = config; next.setEnabled(enabled, for: action); applyAndPersist(next, feedback: nil)
    }

    func restoreSingleDefault(for action: HotKeyActionID) {
        stopRecording(); var next = config; next.restoreDefault(for: action)
        applyAndPersist(next, feedback: "已恢复「\(action.title)」默认快捷键")
    }

    func restoreAllDefaults() { stopRecording(); applyAndPersist(.defaultConfig, feedback: "已恢复全部默认全局热键配置") }

    private func applyAndPersist(_ next: HotKeyBindingConfig, feedback: String?) {
        config = next; next.save()
        _ = (customManager ?? GlobalHotKeyManager.activeInstance)?.reapplyConfig(next, persist: false)
        onConfigChanged?(next)
        scanAllConflicts(announce: false)
        if let feedback { transientMessage = feedback }
    }
}

struct HotKeySettingsView: View {
    @StateObject private var state: HotKeySettingsViewState

    init(hotKeyManager: GlobalHotKeyManager? = nil, pluginHotKeys: [ExternalPluginHotKey] = [], onConfigChanged: ((HotKeyBindingConfig) -> Void)? = nil) {
        _state = StateObject(wrappedValue: HotKeySettingsViewState(hotKeyManager: hotKeyManager, pluginHotKeys: pluginHotKeys, onConfigChanged: onConfigChanged))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeroHeader(
                    symbol: "command.square.fill", topColor: .mint, bottomColor: .teal,
                    title: "全局热键录制与冲突检测",
                    subtitle: "点击键帽胶囊直接录制新快捷键；内置应用内、macOS 系统热键与运行中外部应用三层冲突诊断。"
                ) {
                    HStack(spacing: 8) {
                        Button { state.scanAllConflicts(announce: true) } label: {
                            Label("全面扫描按键冲突", systemImage: "waveform.badge.magnifyingglass")
                        }.buttonStyle(GlassPillButtonStyle(prominent: true))
                        Button { state.restoreAllDefaults() } label: {
                            Label("恢复默认热键", systemImage: "arrow.counterclockwise")
                        }.buttonStyle(GlassPillButtonStyle())
                    }
                }
                healthBanner
                if let msg = state.transientMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill").foregroundStyle(.cyan)
                        Text(msg).font(.caption).foregroundStyle(LiquidColors.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8).liquidGlassCard(cornerRadius: LiquidRadii.row)
                }
                VStack(spacing: 9) { ForEach(HotKeyActionID.allCases) { hotKeyRow($0) } }
            }
        }
        .onAppear { state.onViewAppear() }
        .onDisappear { state.stopRecording() }
    }

    private var healthBanner: some View {
        let conflicts = state.conflictActions
        let healthy = conflicts.isEmpty
        return HStack(spacing: 12) {
            SquircleBadge(
                symbol: healthy ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                topColor: healthy ? .mint : .orange, bottomColor: healthy ? .green : .red, size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(healthy ? "全部 \(state.activeBoundCount) 项热键正常生效，0 冲突" : "检测到 \(conflicts.count) 项按键冲突：\(conflicts.map(\.title).joined(separator: "、"))")
                    .font(.callout.weight(.semibold)).foregroundStyle(healthy ? LiquidColors.textPrimary : .orange)
                Text(healthy ? "点击右侧键帽胶囊即时重录（Esc 取消 · ⌫ 清空），改动立即生效无需重启应用。" : "冲突热键可能被系统或其他软件优先拦截，建议点击对应键帽胶囊改绑组合键。")
                    .font(.caption2).foregroundStyle(LiquidColors.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11).liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func hotKeyRow(_ action: HotKeyActionID) -> some View {
        let binding = state.config.binding(for: action)
        let report = state.reports[action]
        let colors = badgeColors(for: action)
        let isDefault = binding == HotKeyActionBinding(isEnabled: true, chord: action.defaultChord)
        return HStack(alignment: .center, spacing: 12) {
            SquircleBadge(symbol: action.symbolName, topColor: colors.top, bottomColor: colors.bottom, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(action.title).font(.callout.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary)
                    diagnosticPill(binding: binding, report: report)
                }
                Text(action.subtitle).font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                if let issue = report?.primaryIssue, binding.isEnabled {
                    Text("\(issue.detail) · \(issue.suggestion)")
                        .font(.caption2).foregroundStyle(issueVisual(for: issue).tint).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if !isDefault {
                Button { state.restoreSingleDefault(for: action) } label: {
                    Image(systemName: "arrow.counterclockwise").font(.caption2.weight(.semibold))
                }.buttonStyle(GlassPillButtonStyle()).help("恢复此项默认快捷键")
            }
            recorderCapsule(action: action, binding: binding, isRecording: state.recordingAction == action)
            Toggle("", isOn: Binding(get: { binding.isEnabled }, set: { state.setActionEnabled($0, for: action) }))
                .toggleStyle(.switch).labelsHidden()
        }
        .padding(.horizontal, 14).padding(.vertical, 11).liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func recorderCapsule(action: HotKeyActionID, binding: HotKeyActionBinding, isRecording: Bool) -> some View {
        let text = isRecording ? "请按下快捷键…" : (binding.chord?.displayString ?? "点击录制")
        let fg = isRecording ? Color.white : (binding.isEnabled && binding.chord != nil ? LiquidColors.textPrimary : LiquidColors.textSecondary)
        return Button { state.toggleRecording(for: action) } label: {
            HStack(spacing: 5) {
                if isRecording { Image(systemName: "record.circle.fill").font(.caption2).foregroundStyle(.white) }
                Text(text).font(.system(size: 12, weight: .bold, design: isRecording ? .rounded : .monospaced)).foregroundStyle(fg)
            }
            .padding(.horizontal, 12).padding(.vertical, 6).frame(minWidth: 108)
            .background {
                if isRecording { Capsule(style: .continuous).fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)) }
                else { Capsule(style: .continuous).fill(LiquidColors.pillSurface) }
            }
            .overlay { Capsule(style: .continuous).strokeBorder(isRecording ? Color.white.opacity(0.55) : LiquidColors.pillBorder, lineWidth: 1.0) }
        }.buttonStyle(.plain)
    }

    private func diagnosticPill(binding: HotKeyActionBinding, report: HotKeyConflictReport?) -> some View {
        let meta: (icon: String, text: String, tint: Color) = {
            guard binding.isEnabled else { return ("pause.circle", "已停用", .secondary) }
            guard binding.chord != nil else { return ("minus.circle", "未绑定", .secondary) }
            if let issue = report?.primaryIssue { return issueVisual(for: issue) }
            return ("checkmark.circle.fill", report?.registrationSucceeded == true ? "已生效 · 无冲突" : "无冲突", .green)
        }()
        return HStack(spacing: 4) {
            Image(systemName: meta.icon).font(.system(size: 9.5, weight: .bold))
            Text(meta.text).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(meta.tint).padding(.horizontal, 8).padding(.vertical, 2.5)
        .background(meta.tint.opacity(0.14), in: Capsule(style: .continuous))
    }

    private func issueVisual(for issue: HotKeyConflictIssue) -> (icon: String, text: String, tint: Color) {
        switch issue.kind {
        case .internalDuplicate: ("xmark.octagon.fill", issue.sourceTitle, .red)
        case .systemShortcut: (issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill", issue.sourceTitle, issue.severity == .error ? .red : .orange)
        case .externalAppOccupied: ("app.badge.fill", issue.sourceTitle, Color(red: 0.88, green: 0.58, blue: 0.04))
        }
    }

    private func badgeColors(for action: HotKeyActionID) -> (top: Color, bottom: Color) {
        switch action {
        case .launcher: (.cyan, .blue); case .files: (.teal, .indigo); case .clipboard: (.orange, .pink)
        case .screenshotPin: (.mint, .teal); case .screenshotOCR: (.indigo, .purple); case .gifRecord: (.pink, .red)
        case .workspace: (.blue, .indigo); case .systemPulse: (.mint, .cyan); case .networkMonitor: (.cyan, .teal)
        case .quickBackup: (.purple, .blue)
        }
    }
}
