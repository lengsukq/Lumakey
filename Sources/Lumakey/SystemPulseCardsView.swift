import AppKit
import LumakeyCore
import SwiftUI

extension SystemPulseState {
    var shellCornerRadius: CGFloat {
        if isTuckedToEdge { return config.dockedEdge == .top ? 17 : 18 }
        return showsFullDashboard ? 22 : 19
    }

    var targetPanelSize: NSSize {
        if isTuckedToEdge {
            return config.dockedEdge == .top ? NSSize(width: 356, height: 34) : NSSize(width: 58, height: 182)
        }
        return showsFullDashboard ? NSSize(width: 354, height: 318) : NSSize(width: 416, height: 38)
    }

    func applyDisplayMode(_ mode: TelemetryDisplayMode) {
        config.displayMode = mode
        if mode == .edgeAutoHide {
            if config.dockedEdge == .none { config.dockedEdge = .right }
            isPinnedExpanded = false
        } else {
            config.dockedEdge = .none
            isPinnedExpanded = (mode == .alwaysExpanded)
        }
    }

    func applyDockEdge(_ edge: PulseDockEdge) {
        config.dockedEdge = (edge == .none) ? .right : edge
        config.displayMode = .edgeAutoHide
        isPinnedExpanded = false
        isHovered = false
    }

    func applyDragOutcome(frame: NSRect, visibleFrame: NSRect, mouseInside: Bool) {
        let snapped = PulseDockEdge.detectSnapEdge(frame: frame, visibleFrame: visibleFrame)
        if snapped != .none {
            config.dockedEdge = snapped
            config.displayMode = .edgeAutoHide
            if snapped == .top { config.savedOriginX = Double(frame.midX) } else { config.savedOriginY = Double(frame.maxY) }
        } else {
            config.dockedEdge = .none
            if config.displayMode == .edgeAutoHide { config.displayMode = .compactHoverExpand }
            config.savedOriginX = Double(frame.origin.x)
            config.savedOriginY = Double(frame.maxY)
        }
        config.save()
        if isHovered != mouseInside { isHovered = mouseInside }
    }

    func syncPresentationFlags(panelFrame: NSRect?, visibleFrame: NSRect) {
        if config.displayMode == .edgeAutoHide {
            if config.dockedEdge == .none {
                let ref = panelFrame ?? NSRect(x: visibleFrame.maxX - 60, y: visibleFrame.midY, width: 58, height: 182)
                config.dockedEdge = PulseDockEdge.nearestEdge(for: ref, visibleFrame: visibleFrame)
            }
            let nextTucked = !(isHovered || isPinnedExpanded)
            if isTuckedToEdge != nextTucked { isTuckedToEdge = nextTucked }
        } else {
            if isTuckedToEdge { isTuckedToEdge = false }
            if config.displayMode == .alwaysExpanded && !isPinnedExpanded { isPinnedExpanded = true }
        }
    }
}

struct PulseEdgeTabContentView: View, Equatable {
    let isTopStrip: Bool
    let cpuText: String
    let memoryText: String
    let powerText: String
    let shortWattsText: String
    let netDownShortText: String

    var body: some View {
        if isTopStrip {
            HStack(alignment: .center, spacing: 8) {
                SquircleBadge(symbol: "waveform.path.ecg", topColor: .mint, bottomColor: .cyan, size: 20)
                horizontalMetricItem(label: "CPU", value: cpuText, accent: .cyan)
                hairlineVDivider
                horizontalMetricItem(label: "内存", value: memoryText, accent: .indigo)
                hairlineVDivider
                Text(powerText).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.mint)
                hairlineVDivider
                Text(netDownShortText).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.orange)
            }
            .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack(alignment: .center, spacing: 6) {
                SquircleBadge(symbol: "waveform.path.ecg", topColor: .mint, bottomColor: .cyan, size: 24)
                Rectangle().fill(LiquidColors.textSecondary.opacity(0.24)).frame(width: 30, height: 0.8)
                verticalMetricCell(label: "CPU", value: cpuText, accent: .cyan)
                verticalMetricCell(label: "内存", value: memoryText, accent: .indigo)
                verticalMetricCell(label: "功耗", value: shortWattsText, accent: .mint)
                verticalMetricCell(label: "网速", value: netDownShortText, accent: .orange)
            }
            .padding(.vertical, 10).padding(.horizontal, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var hairlineVDivider: some View {
        Rectangle().fill(LiquidColors.textSecondary.opacity(0.25)).frame(width: 1, height: 11)
    }

    private func horizontalMetricItem(label: String, value: String, accent: Color) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(LiquidColors.textSecondary)
            Text(value).font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(accent == .indigo ? LiquidColors.textPrimary : accent)
        }
    }

    private func verticalMetricCell(label: String, value: String, accent: Color) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 8.5, weight: .medium)).foregroundStyle(LiquidColors.textSecondary)
            Text(value).font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.75)
        }
    }
}

struct PulseCompactPillContentView: View, Equatable {
    let cpuFreqText: String
    let memoryText: String
    let powerText: String
    let netDownShortText: String

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            SquircleBadge(symbol: "waveform.path.ecg", topColor: .mint, bottomColor: .cyan, size: 22)
            Text(cpuFreqText).foregroundStyle(LiquidColors.textPrimary)
            Text("·").foregroundStyle(LiquidColors.textSecondary)
            Text(memoryText).foregroundStyle(LiquidColors.textPrimary)
            Text(powerText).font(.system(size: 11.5, weight: .bold, design: .monospaced)).foregroundStyle(.mint)
            Text(netDownShortText).foregroundStyle(.orange)
            Spacer(minLength: 2)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(LiquidColors.textSecondary)
        }
        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
        .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct PulseMetricCardView: View, Equatable {
    let title: String
    let primary: String
    let secondary: String
    let accent: Color
    let history: [Double]
    var trailingButtonTitle: String? = nil
    var trailingAction: (() -> Void)? = nil

    nonisolated static func == (lhs: PulseMetricCardView, rhs: PulseMetricCardView) -> Bool {
        lhs.title == rhs.title && lhs.primary == rhs.primary && lhs.secondary == rhs.secondary
            && lhs.history == rhs.history && lhs.trailingButtonTitle == rhs.trailingButtonTitle
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(LiquidColors.textSecondary)
                    if let btnTitle = trailingButtonTitle, let action = trailingAction {
                        Button(btnTitle, action: action)
                            .buttonStyle(.plain).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1.5).background(accent, in: Capsule())
                    }
                }
                Text(primary).font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
                Text(secondary).font(.system(size: 9.8, design: .monospaced))
                    .foregroundStyle(LiquidColors.textSecondary).lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 4)
            SparklineView(values: history, accent: accent).frame(width: 58, height: 32)
        }
        .padding(.horizontal, 11).padding(.vertical, 6).frame(height: 56)
        .liquidGlassCard(cornerRadius: 13)
    }
}

struct PulseIconButton: View {
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
