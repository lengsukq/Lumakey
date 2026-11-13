import AppKit
import LumakeyCore
import SwiftUI

struct OverlayCommandView: View {
    @ObservedObject var viewModel: AppViewModel

    private var showsBentoHome: Bool {
        viewModel.omniFilter == .all
            && viewModel.overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowSideLens: Bool {
        (viewModel.effectiveLensVisible && !showsBentoHome)
            || viewModel.inlineResultBody != nil
            || viewModel.inlinePluginViewPayload != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            topGrabberStrip
            searchCapsuleBar
            Divider().opacity(0.28)

            HStack(spacing: 0) {
                mainBodyColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if shouldShowSideLens {
                    Divider().opacity(0.28)
                    OverlaySideLensView(viewModel: viewModel)
                        .frame(width: 320)
                }
            }
            .animation(nil, value: viewModel.omniFilter)

            Divider().opacity(0.28)
            OverlayBottomFooterBar(viewModel: viewModel)
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
                    },
                    onQuickSelectIndex: { index in
                        viewModel.quickExecuteCandidate(at: index)
                    },
                    onCopyCandidate: {
                        viewModel.copySelectedCandidateValue()
                    },
                    onSecondarySubmit: {
                        viewModel.executeSecondaryCandidateAction()
                    }
                )
                .frame(height: 28)

                if !viewModel.overlayQuery.isEmpty {
                    Button {
                        viewModel.overlayQuery = ""
                        viewModel.inlineResultBody = nil
                        viewModel.inlinePluginViewPayload = nil
                        viewModel.activeInlinePlugin = nil
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

    @ViewBuilder
    private var mainBodyColumn: some View {
        if showsBentoHome {
            OverlayBentoHomeView(viewModel: viewModel)
        } else {
            VStack(spacing: 0) {
                if viewModel.omniFilter == .files {
                    OverlayEverythingFilterStrip(viewModel: viewModel)
                    Divider().opacity(0.18)
                } else if viewModel.omniFilter == .clipboard {
                    OverlayClipboardCategoryStrip(viewModel: viewModel)
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

    private var filterBadgeColors: (Color, Color) {
        switch viewModel.omniFilter {
        case .all: (.cyan, .blue)
        case .files: (.teal, .indigo)
        case .clipboard: (.orange, .pink)
        case .plugins: (.purple, .indigo)
        }
    }
}
