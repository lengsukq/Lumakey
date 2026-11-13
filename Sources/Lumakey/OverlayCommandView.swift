import AppKit
import LumakeyCore
import SwiftUI

struct OverlayCommandView: View {
    @ObservedObject var viewModel: AppViewModel

    private var showsBentoHome: Bool {
        viewModel.omniFilter == .all
            && viewModel.overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            topGrabberStrip
            searchCapsuleBar
            Divider().opacity(0.28)

            HStack(spacing: 0) {
                mainBodyColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.effectiveLensVisible && !showsBentoHome {
                    Divider().opacity(0.28)
                    OverlaySideLensView(viewModel: viewModel)
                        .frame(width: 320)
                } else if viewModel.inlineResultBody != nil {
                    Divider().opacity(0.28)
                    OverlaySideLensView(viewModel: viewModel)
                        .frame(width: 320)
                }
            }
            .animation(nil, value: viewModel.omniFilter)

            Divider().opacity(0.28)
            bottomFooterBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassShell(cornerRadius: LiquidRadii.panel)
    }

    private var topGrabberStrip: some View {
        ZStack {
            WindowDragRegion {
                viewModel.recenterFloatingPanel()
            }
            Capsule(style: .continuous)
                .fill(LiquidColors.textSecondary.opacity(0.32))
                .frame(width: 40, height: 4)
        }
        .frame(height: 14)
        .help("拖拽移动悬浮窗；双击居中重置位置")
    }

    private var searchCapsuleBar: some View {
        let searchShape = RoundedRectangle(cornerRadius: LiquidRadii.searchBar, style: .continuous)
        return ZStack {
            WindowDragRegion()
            HStack(alignment: .center, spacing: 10) {
                SquircleBadge(
                    symbol: viewModel.omniFilter.symbolName,
                    topColor: filterBadgeColors.0,
                    bottomColor: filterBadgeColors.1,
                    size: 36
                )

                AutoFocusSearchField(
                    text: $viewModel.overlayQuery,
                    placeholder: viewModel.omniFilter.placeholder,
                    focusToken: viewModel.focusToken,
                    onAction: { action in
                        viewModel.handleOverlayKeyAction(action)
                    }
                )
                .frame(height: 28)

                if !viewModel.overlayQuery.isEmpty {
                    Button {
                        viewModel.overlayQuery = ""
                        viewModel.inlineResultBody = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(LiquidColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    viewModel.showOverlayLens.toggle()
                    viewModel.syncOverlayPreviewToSelection()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(viewModel.effectiveLensVisible ? .cyan : LiquidColors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(viewModel.effectiveLensVisible ? Color.cyan.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("展开/收起右侧实时预览 (⌘Y)")

                filterCapsuleBar
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .background {
                ZStack {
                    searchShape.fill(.ultraThinMaterial)
                    searchShape.fill(LiquidColors.inputFieldSurface)
                }
            }
            .overlay { searchShape.strokeBorder(LiquidColors.inputFieldBorder, lineWidth: 1.0) }
            .padding(.horizontal, 16)
        }
        .frame(height: 58)
        .padding(.bottom, 2)
    }

    private var filterCapsuleBar: some View {
        let pillShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack(spacing: 3) {
            ForEach(OmniFilter.allCases) { filter in
                let active = viewModel.omniFilter == filter
                let segShape = RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                Button {
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    withTransaction(tx) {
                        viewModel.setOmniFilter(filter)
                    }
                } label: {
                    Text(filter.title)
                        .font(.caption.weight(active ? .semibold : .medium))
                        .foregroundStyle(active ? Color.white : LiquidColors.textPrimary.opacity(0.78))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            if active {
                                segShape.fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(LiquidColors.pillSurface, in: pillShape)
        .overlay { pillShape.strokeBorder(LiquidColors.pillBorder, lineWidth: 0.8) }
    }

    private var everythingFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.availableEverythingScopes) { scope in
                    let active = viewModel.everythingScope == scope
                    Button(scope.title) {
                        viewModel.rebuildEverythingIndex(scope: scope)
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: active))
                }
                Divider().frame(height: 16).opacity(0.35)
                ForEach(["ext:swift", "ext:md", "pic:", "video:", "folder:"], id: \.self) { token in
                    Button(token) {
                        viewModel.overlayQuery = viewModel.overlayQuery.isEmpty ? token : "\(viewModel.overlayQuery) \(token)"
                        viewModel.bumpFocusToken()
                    }
                    .buttonStyle(GlassPillButtonStyle())
                }
                if viewModel.isIndexingEverything {
                    ProgressView().controlSize(.small).padding(.leading, 4)
                } else {
                    Text("\(viewModel.everythingNodeCount) 节点")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(LiquidColors.textSecondary)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
    }

    private var clipboardCategoryStrip: some View {
        HStack(spacing: 6) {
            ForEach(ClipboardCategory.allCases) { cat in
                Button(cat.rawValue) {
                    viewModel.clipboardCategory = cat
                    viewModel.overlaySelectedIndex = 0
                }
                .buttonStyle(GlassPillButtonStyle(prominent: viewModel.clipboardCategory == cat))
            }
            Spacer()
            Button("清空非收藏") {
                viewModel.clearUnpinnedClipboard()
            }
            .buttonStyle(GlassPillButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var mainBodyColumn: some View {
        if showsBentoHome {
            OverlayBentoHomeView(viewModel: viewModel)
        } else {
            VStack(spacing: 0) {
                if viewModel.omniFilter == .files {
                    everythingFilterStrip
                    Divider().opacity(0.18)
                } else if viewModel.omniFilter == .clipboard {
                    clipboardCategoryStrip
                    Divider().opacity(0.18)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            OverlayUnifiedRowsView(viewModel: viewModel)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: viewModel.overlaySelectedIndex) { _, newIdx in
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo("row-\(newIdx)", anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var bottomFooterBar: some View {
        ZStack {
            WindowDragRegion()
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.caption).foregroundStyle(.cyan)
                Text(viewModel.serviceMessage ?? "拖拽顶部或空白处移动 · Tab 切换过滤")
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)
                Spacer()

                Button { viewModel.openRoute(.workspace) } label: {
                    Label("文件台 ⌥E", systemImage: "sidebar.squares.left").font(.caption2)
                }
                .buttonStyle(.plain).foregroundStyle(LiquidColors.textSecondary)

                Button { viewModel.openRoute(.networkMonitor) } label: {
                    Image(systemName: "network").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                }
                .buttonStyle(.plain).help("本机网络流量与去向监控 (⌥N)")

                Button { SystemPulseWindowController.shared.toggleFloatingWidget() } label: {
                    Image(systemName: "waveform.path.ecg").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                }
                .buttonStyle(.plain).help("系统脉搏悬浮监控 (⌥M)")

                Button { viewModel.openRoute(.settings(.cache)) } label: {
                    Image(systemName: "internaldrive.fill").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                }
                .buttonStyle(.plain).help("应用缓存与存储清理")

                Button { viewModel.openRoute(.settings(.mos)) } label: {
                    Image(systemName: "computermouse.fill").font(.caption)
                        .foregroundStyle(viewModel.mosTapActive ? .cyan : LiquidColors.textSecondary)
                }
                .buttonStyle(.plain).help("Mos 鼠标平滑与滚轮方向")

                Button { viewModel.openRoute(.settings(.general)) } label: {
                    Image(systemName: "gearshape.fill").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(LiquidColors.textSecondary).help("设置、内存与插件 (⌘,)")

                Button { viewModel.isOverlayPinned.toggle() } label: {
                    Image(systemName: viewModel.isOverlayPinned ? "pin.fill" : "pin").font(.caption)
                        .foregroundStyle(viewModel.isOverlayPinned ? .cyan : LiquidColors.textSecondary)
                }
                .buttonStyle(.plain).help("固定悬浮窗不被失焦收起")

                Divider().frame(height: 14).opacity(0.35)
                KeycapPill(title: "过滤", keyText: "⇥")
                KeycapPill(title: "预览", keyText: "⌘Y")
                KeycapPill(title: "执行", keyText: "↩", prominent: true)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 36)
        .background(LiquidColors.pillSurface.opacity(0.55))
    }

    private var filterBadgeColors: (Color, Color) {
        switch viewModel.omniFilter {
        case .all: (.cyan, .blue)
        case .files: (.teal, .indigo)
        case .clipboard: (.orange, .pink)
        case .plugins: (.purple, .indigo)
        }
    }
}
