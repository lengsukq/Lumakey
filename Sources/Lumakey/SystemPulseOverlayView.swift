import AppKit
import LumakeyCore
import SwiftUI

struct SystemPulseOverlayView: View {
    @ObservedObject var state: SystemPulseState
    let onPurgeMemory: () -> Void
    let onTogglePin: () -> Void
    let onDockEdge: (PulseDockEdge) -> Void
    let onSnapSide: () -> Void
    let onSnapNearest: () -> Void
    let onToggleMenuBar: () -> Void
    let onOpenNetwork: () -> Void
    let onHideWidget: () -> Void
    let onSelectMode: (TelemetryDisplayMode) -> Void
    let onHoverChanged: (Bool) -> Void
    let onDragEnded: () -> Void

    private var shellCornerRadius: CGFloat {
        if state.isTuckedToEdge {
            return state.config.dockedEdge == .top ? 17 : 18
        }
        return state.showsFullDashboard ? 22 : 19
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: shellCornerRadius, style: .continuous)
        ZStack {
            PulseInteractionLayer(
                onTap: onTogglePin,
                onHoverChanged: onHoverChanged,
                onDragEnded: onDragEnded,
                onSelectMode: onSelectMode,
                onDockEdge: onDockEdge,
                onSnapNearest: onSnapNearest,
                onToggleMenuBar: onToggleMenuBar,
                onHide: onHideWidget
            )
            Group {
                if state.isTuckedToEdge {
                    edgeTabView
                } else if state.showsFullDashboard {
                    fullDashboardView
                } else {
                    compactPillView
                }
            }
            .allowsHitTesting(state.showsFullDashboard)
        }
        .background(shape.fill(LiquidColors.shellTint.opacity(0.65)))
        .clipShape(shape)
        .overlay { shape.strokeBorder(LiquidColors.specularRimGradient, lineWidth: 1.0) }
    }

    @ViewBuilder
    private var edgeTabView: some View {
        let s = state.snapshot
        if state.config.dockedEdge == .top {
            HStack(alignment: .center, spacing: 8) {
                SquircleBadge(symbol: "waveform.path.ecg", topColor: .mint, bottomColor: .cyan, size: 20)
                horizontalMetricItem(label: "CPU", value: String(format: "%.0f%%", s.cpuTotalPercent), accent: .cyan)
                hairlineVDivider
                horizontalMetricItem(label: "内存", value: String(format: "%.0f%%", s.memoryPercent), accent: .indigo)
                hairlineVDivider
                Text(s.formattedPower)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.mint)
                hairlineVDivider
                Text("↓" + SystemTelemetrySnapshot.formatShortRate(s.netDownBytesPerSec))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.orange)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack(alignment: .center, spacing: 6) {
                SquircleBadge(symbol: "waveform.path.ecg", topColor: .mint, bottomColor: .cyan, size: 24)
                Rectangle()
                    .fill(LiquidColors.textSecondary.opacity(0.24))
                    .frame(width: 30, height: 0.8)
                verticalMetricCell(label: "CPU", value: String(format: "%.0f%%", s.cpuTotalPercent), accent: .cyan)
                verticalMetricCell(label: "内存", value: String(format: "%.0f%%", s.memoryPercent), accent: .indigo)
                verticalMetricCell(label: "功耗", value: String(format: "%.1fW", s.systemWatts), accent: .mint)
                verticalMetricCell(label: "网速", value: "↓" + SystemTelemetrySnapshot.formatShortRate(s.netDownBytesPerSec), accent: .orange)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var hairlineVDivider: some View {
        Rectangle()
            .fill(LiquidColors.textSecondary.opacity(0.25))
            .frame(width: 1, height: 11)
    }

    private func horizontalMetricItem(label: String, value: String, accent: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(LiquidColors.textSecondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(accent == .indigo ? LiquidColors.textPrimary : accent)
        }
    }

    private func verticalMetricCell(label: String, value: String, accent: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(LiquidColors.textSecondary)
            Text(value)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var compactPillView: some View {
        let s = state.snapshot
        return HStack(alignment: .center, spacing: 7) {
            SquircleBadge(symbol: "waveform.path.ecg", topColor: .mint, bottomColor: .cyan, size: 22)
            Text(String(format: "CPU %.0f%% · %.2fGHz", s.cpuTotalPercent, s.estimatedFrequencyGHz))
                .foregroundStyle(LiquidColors.textPrimary)
            Text("·").foregroundStyle(LiquidColors.textSecondary)
            Text(String(format: "内存 %.0f%%", s.memoryPercent))
                .foregroundStyle(LiquidColors.textPrimary)
            Text(s.formattedPower)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.mint)
            Text("↓" + SystemTelemetrySnapshot.formatShortRate(s.netDownBytesPerSec))
                .foregroundStyle(.orange)
            Spacer(minLength: 2)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(LiquidColors.textSecondary)
        }
        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var fullDashboardView: some View {
        let s = state.snapshot
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                SquircleBadge(symbol: "waveform.path.ecg", topColor: .mint, bottomColor: .cyan, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.chipBrand)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LiquidColors.textPrimary)
                        .lineLimit(1)
                    Text("\(s.coreTopologyText) · 热态 \(s.thermalStateLabel)")
                        .font(.system(size: 10))
                        .foregroundStyle(LiquidColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    PulseIconButton(symbol: "network", active: false, tip: "本机网络流量与去向监控 (⌥N)", action: onOpenNetwork)
                    PulseIconButton(symbol: state.isPinnedExpanded ? "pin.fill" : "pin", active: state.isPinnedExpanded, tip: "固定展开 / 移开收起", action: onTogglePin)
                    PulseIconButton(symbol: "menubar.dock.rectangle", active: state.config.displayMode == .edgeAutoHide && state.config.dockedEdge == .top, tip: "贴靠顶部 · 横向排列", action: { onDockEdge(.top) })
                    PulseIconButton(symbol: "sidebar.right", active: state.config.displayMode == .edgeAutoHide && state.config.dockedEdge.isVerticalColumn, tip: "贴靠侧边 · 竖行排列", action: onSnapSide)
                    PulseIconButton(symbol: "xmark", active: false, tip: "关闭悬浮窗 (⌥M)", action: onHideWidget)
                }
            }
            .frame(height: 30)

            metricCard(
                title: "处理器与频率",
                primary: String(format: "CPU %.0f%% · %@", s.cpuTotalPercent, s.formattedFrequency),
                secondary: String(format: "P核 %.0f%% · E核 %.0f%% · GPU %.0f%% · 峰 %.1fG", s.perfCorePercent, s.effCorePercent, s.gpuPercent, s.maxFrequencyGHz),
                accent: .cyan,
                history: s.cpuHistory
            )
            metricCard(
                title: "系统内存与交换区",
                primary: "\(s.formattedMemory) (\(Int(s.memoryPercent.rounded()))%)",
                secondary: String(format: "压缩 %.1f GB · Swap %.0f MB", Double(s.memoryCompressedBytes) / 1_073_741_824.0, s.swapUsedMB),
                accent: .indigo,
                history: s.memHistory,
                trailingButton: ("释放", onPurgeMemory)
            )
            metricCard(
                title: "实时功耗与电源",
                primary: s.formattedPower,
                secondary: s.batteryPercent.map { "电池 \($0)% · \(s.isCharging ? "充电中" : "放电")" } ?? "外接电源供电",
                accent: .mint,
                history: s.powerHistory
            )
            metricCard(
                title: "实时网速与磁盘",
                primary: "↓ \(s.formattedNetDown)  ·  ↑ \(s.formattedNetUp)",
                secondary: String(format: "系统卷可用 %.0f GB / %.0f GB", s.diskFreeGB, s.diskTotalGB),
                accent: .orange,
                history: s.netHistory
            )

            Text("拖至顶部横排 · 拖至左右侧竖排 · 悬停展开 · ⌥M")
                .font(.system(size: 9.5))
                .foregroundStyle(LiquidColors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 13)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contextMenu {
            Button("贴靠顶部 · 横向排列") { onDockEdge(.top) }
            Button("贴靠左侧 · 竖行排列") { onDockEdge(.left) }
            Button("贴靠右侧 · 竖行排列") { onDockEdge(.right) }
            Divider()
            Button("切换顶部菜单栏显示") { onToggleMenuBar() }
            Button("隐藏悬浮窗 (⌥M)") { onHideWidget() }
        }
    }

    private func metricCard(
        title: String,
        primary: String,
        secondary: String,
        accent: Color,
        history: [Double],
        trailingButton: (String, () -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(LiquidColors.textSecondary)
                    if let btn = trailingButton {
                        Button(btn.0, action: btn.1)
                            .buttonStyle(.plain)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(accent, in: Capsule())
                    }
                }
                Text(primary)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .lineLimit(1)
                Text(secondary)
                    .font(.system(size: 9.8, design: .monospaced))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 4)
            SparklineView(values: history, accent: accent)
                .frame(width: 58, height: 32)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .frame(height: 56)
        .liquidGlassCard(cornerRadius: 13)
    }
}

private struct PulseIconButton: View {
    let symbol: String
    let active: Bool
    let tip: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(active ? Color.white : LiquidColors.textSecondary)
                .frame(width: 21, height: 21)
                .background(active ? Color.accentColor : LiquidColors.pillSurface, in: Circle())
                .overlay { Circle().strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
        }
        .buttonStyle(.plain)
        .help(tip)
    }
}
