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

    private var tiles: [BentoTileDescriptor] {
        [
            BentoTileDescriptor(id: "files", title: "全盘文件", subtitle: "极速检索 / ext:md", hotkey: "⌥F", symbol: "magnifyingglass", topColor: .cyan, bottomColor: .blue),
            BentoTileDescriptor(id: "clipboard", title: "剪贴板库", subtitle: "已记录 \(viewModel.clipboardHistoryCount) 条", hotkey: "⌥C", symbol: "doc.on.clipboard.fill", topColor: .orange, bottomColor: .pink),
            BentoTileDescriptor(id: "pin", title: "截图钉屏", subtitle: "选区悬浮对比置顶", hotkey: "⌥A", symbol: "camera.viewfinder", topColor: .mint, bottomColor: .teal),
            BentoTileDescriptor(id: "ocr", title: "离线识字", subtitle: "Vision OCR / 抠图", hotkey: "⌥O", symbol: "text.viewfinder", topColor: .purple, bottomColor: .indigo),
            BentoTileDescriptor(id: "network", title: "网络流量", subtitle: "本机进程 · 远端去向", hotkey: "⌥N", symbol: "network", topColor: .blue, bottomColor: .cyan),
            BentoTileDescriptor(id: "monitor", title: "系统脉搏", subtitle: "内存 · 频率 · 功耗 · 网速", hotkey: "⌥M", symbol: "waveform.path.ecg", topColor: .teal, bottomColor: .mint)
        ]
    }

    private let tryChips: [String] = ["128 * 48", "255 in hex", "流量", "缓存", "mos", "port 3000"]

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
                        Text(tile.hotkey)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidColors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7)
                            }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 76)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlassCard(cornerRadius: LiquidRadii.bento)
                    .contentShape(RoundedRectangle(cornerRadius: LiquidRadii.bento, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var quickAppDock: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("常用应用直达（支持全拼 / 首字母 / 磁盘与命令混搜）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                Spacer()
                Text("已索引 \(viewModel.installedApps.count) 应用")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 6) {
                ForEach(viewModel.cachedDockApps) { app in
                    Button {
                        viewModel.launchApp(app)
                    } label: {
                        VStack(spacing: 5) {
                            Image(nsImage: IconCache.shared.appIcon(for: app.url))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 38, height: 38)
                            Text(app.name)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(LiquidColors.textPrimary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 3)
                        .background(LiquidColors.pillSurface.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .liquidGlassCard(cornerRadius: LiquidRadii.bento)
        }
    }

    private var bottomUtilityStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
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
            Button { viewModel.openRoute(.settings(.mos)) } label: {
                HStack(spacing: 5) {
                    Circle().fill(viewModel.mosTapActive ? Color.mint : Color.orange).frame(width: 6, height: 6)
                    Text(viewModel.mosTapActive ? "Mos 运行中" : "Mos 鼠标")
                }
            }
            .buttonStyle(GlassPillButtonStyle())

            Button { viewModel.openRoute(.settings(.cache)) } label: {
                Label("应用缓存", systemImage: "internaldrive.fill")
            }
            .buttonStyle(GlassPillButtonStyle())
        }
    }

    private func handleTileTap(_ id: String) {
        switch id {
        case "files": viewModel.setOmniFilter(.files)
        case "clipboard": viewModel.setOmniFilter(.clipboard)
        case "pin": viewModel.captureAndPinScreenshot()
        case "ocr": viewModel.captureAndAnalyzeOCR()
        case "network": viewModel.openRoute(.networkMonitor)
        case "monitor": SystemPulseWindowController.shared.toggleFloatingWidget()
        default: break
        }
    }
}
