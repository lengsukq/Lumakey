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

    var body: some View {
        let prefs = SystemDisplayPreferences.shared.snapshot
        let shape = RoundedRectangle(cornerRadius: state.shellCornerRadius, style: .continuous)
        let s = state.snapshot

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
                    PulseEdgeTabContentView(
                        isTopStrip: state.config.dockedEdge == .top,
                        cpuText: String(format: "%.0f%%", s.cpuTotalPercent),
                        memoryText: String(format: "%.0f%%", s.memoryPercent),
                        powerText: s.formattedPower,
                        shortWattsText: String(format: "%.1fW", s.systemWatts),
                        netDownShortText: "↓" + SystemTelemetrySnapshot.formatShortRate(s.netDownBytesPerSec)
                    )
                    .equatable()
                } else if state.showsFullDashboard {
                    fullDashboardView(s)
                } else {
                    PulseCompactPillContentView(
                        cpuFreqText: String(format: "CPU %.0f%% · %.2fGHz", s.cpuTotalPercent, s.estimatedFrequencyGHz),
                        memoryText: String(format: "内存 %.0f%%", s.memoryPercent),
                        powerText: s.formattedPower,
                        netDownShortText: "↓" + SystemTelemetrySnapshot.formatShortRate(s.netDownBytesPerSec)
                    )
                    .equatable()
                }
            }
            .allowsHitTesting(state.showsFullDashboard)
        }
        .background(shape.fill(prefs.reduceTransparency ? LiquidColors.solidCardSurface : LiquidColors.shellTint.opacity(0.65)))
        .clipShape(shape)
        .overlay {
            if prefs.increaseContrast {
                shape.strokeBorder(LiquidColors.subtleRim, lineWidth: 1.4)
            } else {
                shape.strokeBorder(LiquidColors.specularRimGradient, lineWidth: 1.0)
            }
        }
    }

    private func fullDashboardView(_ s: SystemTelemetrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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

            PulseMetricCardView(
                title: "处理器与频率",
                primary: String(format: "CPU %.0f%% · %@", s.cpuTotalPercent, s.formattedFrequency),
                secondary: String(format: "P核 %.0f%% · E核 %.0f%% · GPU %.0f%% · 峰 %.1fG", s.perfCorePercent, s.effCorePercent, s.gpuPercent, s.maxFrequencyGHz),
                accent: .cyan,
                history: s.cpuHistory
            )
            .equatable()

            PulseMetricCardView(
                title: "系统内存与交换区",
                primary: "\(s.formattedMemory) (\(Int(s.memoryPercent.rounded()))%)",
                secondary: String(format: "压缩 %.1f GB · Swap %.0f MB", Double(s.memoryCompressedBytes) / 1_073_741_824.0, s.swapUsedMB),
                accent: .indigo,
                history: s.memHistory,
                trailingButtonTitle: "释放",
                trailingAction: onPurgeMemory
            )
            .equatable()

            PulseMetricCardView(
                title: "实时功耗与电源",
                primary: s.formattedPower,
                secondary: s.batteryPercent.map { "电池 \($0)% · \(s.isCharging ? "充电中" : "放电")" } ?? "外接电源供电",
                accent: .mint,
                history: s.powerHistory
            )
            .equatable()

            PulseMetricCardView(
                title: "实时网速与磁盘",
                primary: "↓ \(s.formattedNetDown)  ·  ↑ \(s.formattedNetUp)",
                secondary: String(format: "系统卷可用 %.0f GB / %.0f GB", s.diskFreeGB, s.diskTotalGB),
                accent: .orange,
                history: s.netHistory
            )
            .equatable()

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
}
