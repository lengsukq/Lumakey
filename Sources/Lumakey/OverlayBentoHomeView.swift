import AppKit
import LumakeyCore
import SwiftUI

private struct BentoTileDescriptor: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let hotkey: String
    let symbol: String
    let topColor: Color
    let bottomColor: Color
}

struct OverlayBentoHomeView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var usageTracker = AppUsageTrackerController.shared

    private var tiles: [BentoTileDescriptor] {
        [
            BentoTileDescriptor(id: "files", title: "全盘文件", subtitle: "极速检索 / ext:md", hotkey: "⌥F", symbol: "magnifyingglass", topColor: .cyan, bottomColor: .blue),
            BentoTileDescriptor(id: "clipboard", title: "剪贴板库", subtitle: "已记录 \(viewModel.clipboardHistoryCount) 条", hotkey: "⌥C", symbol: "doc.on.clipboard.fill", topColor: .orange, bottomColor: .pink),
            BentoTileDescriptor(id: "pin", title: "截图钉屏", subtitle: "选区标注悬浮置顶", hotkey: "⌥A", symbol: "camera.viewfinder", topColor: .mint, bottomColor: .teal),
            BentoTileDescriptor(id: "gif", title: "动图录屏", subtitle: "区域/窗口高帧率 GIF", hotkey: "⌥G", symbol: "record.circle.fill", topColor: .pink, bottomColor: .red),
            BentoTileDescriptor(id: "ocr", title: "离线识字", subtitle: "Vision OCR / 抠图", hotkey: "⌥O", symbol: "text.viewfinder", topColor: .purple, bottomColor: .indigo),
            BentoTileDescriptor(id: "network", title: "网络流量", subtitle: "本机进程 · 远端去向", hotkey: "⌥N", symbol: "network", topColor: .blue, bottomColor: .cyan)
        ]
    }

    private let tryChips: [String] = ["128 * 48", "ts", "uuid", ";date", "qr Lumakey", "port 3000"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            bentoGrid
            quickAppDock
            bottomUtilityStrip
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WindowDragRegion())
        .onAppear { usageTracker.ensureSystemProbe(for: viewModel.installedApps) }
        .onChange(of: viewModel.installedApps) { _, apps in
            usageTracker.ensureSystemProbe(for: apps)
        }
    }

    private var bentoGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(tiles) { tile in
                Button {
                    handleTileTap(tile.id)
                } label: {
                    HStack(alignment: .center, spacing: 13) {
                        SquircleBadge(symbol: tile.symbol, topColor: tile.topColor, bottomColor: tile.bottomColor, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tile.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(LiquidColors.textPrimary)
                                .lineLimit(1)
                            Text(tile.subtitle)
                                .font(.caption2)
                                .foregroundStyle(LiquidColors.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        LiquidKeyHintBadge(keyText: tile.hotkey)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 76)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlassCard(cornerRadius: LiquidRadii.bento)
                    .contentShape(RoundedRectangle(cornerRadius: LiquidRadii.bento, style: .continuous))
                }
                .buttonStyle(LiquidBentoTileStyle(cornerRadius: LiquidRadii.bento))
            }
        }
    }

    private var quickAppDock: some View {
        let dockApps = usageTracker.rankedDockApps(from: viewModel.installedApps, limit: 8)
        let pinnedCount = usageTracker.pinnedCount

        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("常用应用直达（右键钉应用 · 自动统计时长与系统使用频率）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                Spacer()
                Text(pinnedCount > 0 ? "已钉 \(pinnedCount) · 已索引 \(viewModel.installedApps.count) 应用" : "已索引 \(viewModel.installedApps.count) 应用")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 6) {
                ForEach(dockApps) { app in
                    dockAppTile(app)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .liquidGlassCard(cornerRadius: LiquidRadii.bento)
        }
    }

    private func dockAppTile(_ app: InstalledAppItem) -> some View {
        let pinned = usageTracker.isPinned(app)
        let summary = usageTracker.usageSummary(for: app)
        let badge = usageTracker.compactUsageBadge(for: app)
        let tileShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return Button {
            viewModel.launchApp(app)
        } label: {
            VStack(spacing: 4) {
                Image(nsImage: IconCache.shared.appIcon(for: app.url))
                    .resizable().scaledToFit().frame(width: 38, height: 38)
                Text(app.name)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .lineLimit(1)
                Text(badge ?? (pinned ? "已钉住" : " "))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(pinned ? Color.orange : LiquidColors.textSecondary.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 3)
            .background(LiquidColors.pillSurface.opacity(pinned ? 0.50 : 0.35), in: tileShape)
            .overlay {
                if pinned { tileShape.strokeBorder(Color.orange.opacity(0.38), lineWidth: 0.85) }
            }
            .overlay(alignment: .topTrailing) {
                if pinned { pinnedIndicatorBadge }
            }
            .contentShape(tileShape)
        }
        .buttonStyle(LiquidBentoTileStyle(cornerRadius: 12))
        .help("\(app.name) · \(summary)")
        .contextMenu { dockAppContextMenu(for: app, isPinned: pinned) }
    }

    private var pinnedIndicatorBadge: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(3.5)
            .background(
                LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle()
            )
            .overlay { Circle().strokeBorder(.white.opacity(0.45), lineWidth: 0.6) }
            .shadow(color: .orange.opacity(0.32), radius: 2.5, y: 1)
            .padding(4)
    }

    @ViewBuilder
    private func dockAppContextMenu(for app: InstalledAppItem, isPinned: Bool) -> some View {
        Button { usageTracker.togglePin(app) } label: {
            Label(isPinned ? "取消钉住" : "钉在常用栏", systemImage: isPinned ? "pin.slash" : "pin.fill")
        }
        if isPinned {
            Button { usageTracker.movePin(app, delta: -1) } label: {
                Label("左移", systemImage: "arrow.left")
            }
            .disabled(!usageTracker.canMovePin(app, delta: -1))
            Button { usageTracker.movePin(app, delta: 1) } label: {
                Label("右移", systemImage: "arrow.right")
            }
            .disabled(!usageTracker.canMovePin(app, delta: 1))
        }
        Divider()
        Button { NSWorkspace.shared.activateFileViewerSelecting([app.url]) } label: {
            Label("在访达中显示", systemImage: "folder")
        }
        Button(role: .destructive) { usageTracker.resetStats(for: app.id) } label: {
            Label("重置该应用使用记录", systemImage: "arrow.counterclockwise")
        }
    }

    private var bottomUtilityStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("试试输入")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LiquidColors.textSecondary)
                    ForEach(tryChips, id: \.self) { chip in
                        Button(chip) {
                            viewModel.overlayQuery = chip
                            viewModel.bumpFocusToken()
                        }
                        .buttonStyle(GlassPillButtonStyle())
                    }
                }
            }
            Spacer(minLength: 6)
            Button { SystemPulseWindowController.shared.toggleFloatingWidget() } label: {
                Label("脉搏 ⌥M", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(GlassPillButtonStyle())

            Button { viewModel.openRoute(.settings(.plugins)) } label: {
                Label("插件", systemImage: "puzzlepiece.extension.fill")
            }
            .buttonStyle(GlassPillButtonStyle())

            Button { viewModel.openRoute(.settings(.backup)) } label: {
                Label("备份", systemImage: "externaldrive.badge.icloud")
            }
            .buttonStyle(GlassPillButtonStyle())
        }
    }

    private func handleTileTap(_ id: String) {
        switch id {
        case "files": viewModel.setOmniFilter(.files)
        case "clipboard": viewModel.setOmniFilter(.clipboard)
        case "pin": viewModel.captureAndPinScreenshot()
        case "gif": viewModel.startGifRecording()
        case "ocr": viewModel.captureAndAnalyzeOCR()
        case "network": viewModel.openRoute(.networkMonitor)
        default: break
        }
    }
}
