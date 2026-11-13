import LumakeyCore
import SwiftUI

struct TelemetrySettingsView: View {
    @ObservedObject var pulseState = SystemPulseWindowController.shared.state

    private var config: SystemMonitorConfig { pulseState.config }
    private var snap: SystemTelemetrySnapshot { pulseState.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeroHeader(
                    symbol: "waveform.path.ecg", topColor: .mint, bottomColor: .cyan,
                    title: "系统监控悬浮窗与顶部状态栏",
                    subtitle: "刚安装默认关闭桌面悬浮窗与菜单栏读数（0 后台采样），开启后支持拖拽贴边隐藏与顶部精简展开。"
                ) {
                    Button("立即刷一次快照") {
                        SystemPulseWindowController.shared.refreshOnceForSettings()
                    }
                    .buttonStyle(GlassPillButtonStyle())
                }

                SettingsToggleCardRow(
                    symbol: "macwindow.on.rectangle", topColor: .cyan, bottomColor: .blue,
                    title: "启用系统脉搏桌面悬浮监控窗 (快捷键 ⌥M)",
                    subtitle: "支持拖拽至屏幕左 / 右 / 顶部边缘自动隐藏，悬停或点击即可滑出完整面板",
                    isOn: Binding(
                        get: { config.floatingEnabled },
                        set: { SystemPulseWindowController.shared.setFloatingEnabled($0) }
                    )
                )

                modeSelectorCard

                SettingsToggleCardRow(
                    symbol: "menubar.rectangle", topColor: .teal, bottomColor: .indigo,
                    title: "在 macOS 顶部菜单栏显示实时系统状态",
                    subtitle: config.showInMenuBar ? "当前菜单栏预览：\(config.formatMenuBarText(from: snap))" : "已关闭（菜单栏仅保留精致 ✦ 图标）",
                    isOn: Binding(
                        get: { config.showInMenuBar },
                        set: { SystemPulseWindowController.shared.setMenuBarEnabled($0) }
                    )
                )

                menuMetricsCard
                liveSnapshotCard
            }
        }
        .onAppear {
            SystemPulseWindowController.shared.refreshOnceForSettings()
        }
    }

    private var modeSelectorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("悬浮窗展示形态").font(.callout.weight(.semibold))
                Spacer()
                HStack(spacing: 6) {
                    Button("贴顶横排") {
                        SystemPulseWindowController.shared.dockToEdge(.top)
                    }
                    .buttonStyle(GlassPillButtonStyle())
                    Button("贴左竖排") {
                        SystemPulseWindowController.shared.dockToEdge(.left)
                    }
                    .buttonStyle(GlassPillButtonStyle())
                    Button("贴右竖排") {
                        SystemPulseWindowController.shared.dockToEdge(.right)
                    }
                    .buttonStyle(GlassPillButtonStyle())
                }
            }
            HStack(spacing: 8) {
                ForEach(TelemetryDisplayMode.allCases, id: \.rawValue) { mode in
                    let active = config.displayMode == mode
                    Button {
                        SystemPulseWindowController.shared.setDisplayMode(mode)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Image(systemName: modeSymbol(mode))
                                .font(.callout.weight(.semibold))
                            Text(mode.title)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(active ? Color.white : LiquidColors.textPrimary)
                        .background(
                            active ? Color.accentColor : LiquidColors.pillSurface,
                            in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                                .strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }

    private var menuMetricsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("顶部菜单栏显示项（点击切换，推荐勾选 2~4 项适配刘海屏）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                metricChip("CPU 负载", keyPath: \.menuShowCPU)
                metricChip("CPU 频率", keyPath: \.menuShowFreq)
                metricChip("内存占用", keyPath: \.menuShowMemory)
                metricChip("实时功耗 W", keyPath: \.menuShowPower)
                metricChip("下载网速", keyPath: \.menuShowNet)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }

    private func metricChip(_ title: String, keyPath: WritableKeyPath<SystemMonitorConfig, Bool>) -> some View {
        let on = config[keyPath: keyPath]
        return Button(title) {
            SystemPulseWindowController.shared.updateMenuMetrics { $0[keyPath: keyPath].toggle() }
        }
        .buttonStyle(GlassPillButtonStyle(prominent: on))
    }

    private var liveSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前硬件实时快照（\(snap.chipBrand) · \(snap.coreTopologyText)）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                snapshotTile("CPU 负载", value: String(format: "%.1f%%", snap.cpuTotalPercent), sub: snap.formattedFrequency, tint: .cyan)
                snapshotTile("物理内存", value: String(format: "%.0f%%", snap.memoryPercent), sub: snap.formattedMemory, tint: .indigo)
                snapshotTile("整机功耗", value: snap.formattedPower, sub: "热态：\(snap.thermalStateLabel)", tint: .mint)
                snapshotTile("实时网速", value: "↓ \(snap.formattedNetDown)", sub: "↑ \(snap.formattedNetUp)", tint: .orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }

    private func snapshotTile(_ label: String, value: String, sub: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.bold).monospacedDigit()).foregroundStyle(tint).lineLimit(1)
            Text(sub).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func modeSymbol(_ mode: TelemetryDisplayMode) -> String {
        switch mode {
        case .compactHoverExpand: "capsule.tophalf.filled"
        case .alwaysExpanded: "square.grid.2x2.fill"
        case .edgeAutoHide: "sidebar.right"
        }
    }
}
