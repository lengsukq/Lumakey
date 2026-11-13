import AppKit
import LumakeyCore
import SwiftUI

struct OverlayUnifiedRowsView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var usageTracker = AppUsageTrackerController.shared

    var body: some View {
        let items = viewModel.displayedCandidates
        if items.isEmpty {
            emptyStateCard
        } else {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, candidate in
                let isSelected = index == viewModel.overlaySelectedIndex
                Button {
                    if !viewModel.effectiveLensVisible || isSelected {
                        viewModel.overlaySelectedIndex = index
                        viewModel.executeCandidate(candidate)
                    } else {
                        viewModel.overlaySelectedIndex = index
                        viewModel.syncOverlayPreviewToSelection()
                    }
                } label: {
                    HStack(spacing: 12) {
                        candidateLeadingIcon(candidate)
                        candidateBody(candidate)
                        Spacer(minLength: 8)
                        candidateTrailingInfo(candidate, index: index, selected: isSelected)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8.5)
                    .overlayRowHighlight(selected: isSelected)
                }
                .buttonStyle(LiquidResultRowButtonStyle())
                .contextMenu { rowContextMenu(candidate) }
                .id("row-\(index)")
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: 10) {
            SquircleBadge(symbol: viewModel.omniFilter.symbolName, topColor: .cyan.opacity(0.85), bottomColor: .blue.opacity(0.85), size: 42)
            Text(emptyTitle).font(.callout.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary)
            Text("试试调整关键词，或按 Tab 切换搜索维度").font(.caption2).foregroundStyle(LiquidColors.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36).padding(.horizontal, 20)
        .liquidGlassCard(cornerRadius: LiquidRadii.card).padding(.top, 28)
    }

    private var emptyTitle: String {
        switch viewModel.omniFilter {
        case .all: "无匹配应用、文件、剪贴板或命令"
        case .files: "无匹配文件，尝试 ext:md / pic: / 关键词"
        case .clipboard: "暂无匹配的剪贴板记录"
        case .plugins: "未找到已启用插件，可在设置中心安装或启用"
        }
    }

    @ViewBuilder
    private func candidateLeadingIcon(_ candidate: LauncherCandidate) -> some View {
        switch candidate.kind {
        case .app(let app):
            Image(nsImage: IconCache.shared.appIcon(for: app.url)).resizable()
                .frame(width: 32, height: 32).shadow(color: .black.opacity(0.14), radius: 3, y: 1.5)
        case .calculator:
            SquircleBadge(symbol: "equal", topColor: .orange, bottomColor: .red, size: 32)
        case .devTool(let tool):
            if let hex = tool.colorHex {
                colorSwatchIcon(hex)
            } else {
                SquircleBadge(symbol: tool.symbol, topColor: .mint, bottomColor: .cyan, size: 32)
            }
        case .snippet:
            SquircleBadge(symbol: "text.quote", topColor: .cyan, bottomColor: .indigo, size: 32)
        case .fileHit(let hit):
            frostedIconBox(IconCache.shared.fileIcon(isDirectory: hit.isDirectory, extensionLowercased: hit.url.pathExtension.lowercased()))
        case .clipboard(let entry):
            clipboardLeadingBadge(entry)
        case .plugin(let plugin):
            SquircleBadge(symbol: plugin.manifest.icon ?? "puzzlepiece.extension.fill", topColor: .purple, bottomColor: .indigo, size: 32)
        case .command(let cmd):
            SquircleBadge(symbol: cmd.symbol, topColor: .cyan, bottomColor: .blue, size: 32)
        }
    }

    private func colorSwatchIcon(_ hex: String) -> some View {
        let swatch = LiquidColors.color(fromHex: hex) ?? .accentColor
        let shape = RoundedRectangle(cornerRadius: LiquidRadii.pill, style: .continuous)
        return shape.fill(swatch).frame(width: 32, height: 32)
            .overlay { shape.fill(LinearGradient(colors: [.white.opacity(0.32), .clear], startPoint: .topLeading, endPoint: .center)) }
            .overlay { shape.strokeBorder(.white.opacity(0.55), lineWidth: 0.95) }
            .shadow(color: swatch.opacity(0.28), radius: 4, y: 2)
    }

    private func frostedIconBox(_ image: NSImage) -> some View {
        let shape = RoundedRectangle(cornerRadius: LiquidRadii.pill, style: .continuous)
        return ZStack {
            shape.fill(LiquidColors.elevatedSurface)
            Image(nsImage: image).resizable().scaledToFit().frame(width: 23, height: 23)
        }
        .frame(width: 32, height: 32)
        .overlay { shape.strokeBorder(LiquidColors.softCardRimGradient, lineWidth: 0.75) }
    }

    @ViewBuilder
    private func clipboardLeadingBadge(_ entry: ClipboardEntry) -> some View {
        switch entry.payloadKind {
        case .colorHex(let hex): colorSwatchIcon(hex)
        case .image: SquircleBadge(symbol: "photo.fill", topColor: .pink, bottomColor: .purple, size: 32)
        case .file(let url): frostedIconBox(IconCache.shared.fileIcon(isDirectory: false, extensionLowercased: url.pathExtension.lowercased()))
        case .text: SquircleBadge(symbol: "doc.text.fill", topColor: .cyan, bottomColor: .blue, size: 32)
        }
    }

    @ViewBuilder
    private func candidateBody(_ candidate: LauncherCandidate) -> some View {
        switch candidate.kind {
        case .app(let app):
            let badge = usageTracker.compactUsageBadge(for: app)
            rowLabels(title: app.name, subtitle: badge.map { "\($0) · \(app.url.path)" } ?? app.url.path, boldTitle: true)
        case .calculator(let expr, let resultText, _):
            VStack(alignment: .leading, spacing: 2.5) {
                Text(resultText).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(LiquidColors.accentGradient).lineLimit(1)
                Text(expr).font(.caption2.monospaced()).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
            }
        case .devTool(let tool):
            rowLabels(title: tool.title, subtitle: tool.subtitle, boldTitle: true, monoSubtitle: true)
        case .snippet(let match):
            let preview = match.expandedText.replacingOccurrences(of: "\n", with: " ↵ ")
            rowLabels(title: "\(match.snippet.title)  \(match.snippet.keyword)", subtitle: preview, boldTitle: true, monoSubtitle: true)
        case .fileHit(let hit):
            rowLabels(title: hit.name, subtitle: hit.relativeParentPath, boldTitle: false, monoSubtitle: true)
        case .clipboard(let entry):
            rowLabels(title: entry.title, subtitle: entry.subtitle, boldTitle: false)
        case .plugin(let plugin):
            rowLabels(title: plugin.manifest.name, subtitle: plugin.manifest.description, boldTitle: true)
        case .command(let cmd):
            rowLabels(title: cmd.title, subtitle: cmd.subtitle, boldTitle: true)
        }
    }

    private func rowLabels(title: String, subtitle: String, boldTitle: Bool, monoSubtitle: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2.5) {
            Text(title).font(.callout.weight(boldTitle ? .semibold : .medium)).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
            Text(subtitle).font(monoSubtitle ? .caption2.monospaced() : .caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
        }
    }

    @ViewBuilder
    private func candidateTrailingInfo(_ candidate: LauncherCandidate, index: Int, selected: Bool) -> some View {
        HStack(spacing: 6) {
            if isPinnedCandidate(candidate) {
                Image(systemName: "pin.fill").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.orange)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.14), in: Capsule(style: .continuous))
                    .overlay { Capsule(style: .continuous).strokeBorder(Color.orange.opacity(0.30), lineWidth: 0.7) }
            }
            if case .fileHit(let hit) = candidate.kind {
                Text(hit.formattedSize).font(.caption2.monospacedDigit()).foregroundStyle(LiquidColors.textSecondary)
            }
            if index < 9 { LiquidKeyHintBadge(keyText: "⌘\(index + 1)", highlighted: selected) }
            if selected {
                Text(actionHint(for: candidate)).font(.caption2.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 3.5)
                    .background(LiquidColors.accentGradient, in: Capsule(style: .continuous))
                    .overlay { Capsule(style: .continuous).strokeBorder(.white.opacity(0.38), lineWidth: 0.75) }
                    .shadow(color: .cyan.opacity(0.24), radius: 5, y: 1.5)
            } else {
                Text(badgeText(for: candidate)).font(.caption2.weight(.medium)).foregroundStyle(LiquidColors.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 3.5)
                    .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
                    .overlay { Capsule(style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
            }
        }
    }

    private func isPinnedCandidate(_ candidate: LauncherCandidate) -> Bool {
        switch candidate.kind {
        case .app(let app): usageTracker.isPinned(app)
        case .clipboard(let entry): entry.isPinned
        default: false
        }
    }

    @ViewBuilder
    private func rowContextMenu(_ candidate: LauncherCandidate) -> some View {
        switch candidate.kind {
        case .app(let app):
            let pinned = usageTracker.isPinned(app)
            Button { usageTracker.togglePin(app) } label: {
                Label(pinned ? "取消钉住" : "钉在常用栏", systemImage: pinned ? "pin.slash" : "pin.fill")
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([app.url]) } label: {
                Label("在访达中显示", systemImage: "folder")
            }
            Button(role: .destructive) { usageTracker.resetStats(for: app.id) } label: {
                Label("重置使用记录", systemImage: "arrow.counterclockwise")
            }
        case .fileHit(let hit):
            Button { NSWorkspace.shared.activateFileViewerSelecting([hit.url]) } label: {
                Label("在访达中显示", systemImage: "folder")
            }
            Button {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hit.url.path, forType: .string)
            } label: { Label("复制完整路径", systemImage: "doc.on.doc") }
        case .clipboard(let entry):
            Button { viewModel.toggleClipboardPin(entry) } label: {
                Label(entry.isPinned ? "取消收藏" : "永久收藏", systemImage: entry.isPinned ? "pin.slash" : "pin.fill")
            }
        default:
            Button { viewModel.executeCandidate(candidate) } label: { Label("执行", systemImage: "play.fill") }
        }
    }

    private func actionHint(for candidate: LauncherCandidate) -> String {
        switch candidate.kind {
        case .calculator, .clipboard, .snippet: "复制 ↩"
        case .devTool(let t): t.previewImageURL != nil ? "复制图片 ↩" : "复制 ↩"
        case .plugin, .command: "执行 ↩"
        default: "打开 ↩"
        }
    }

    private func badgeText(for candidate: LauncherCandidate) -> String {
        switch candidate.kind {
        case .app: "应用"
        case .calculator(_, _, let b): b
        case .devTool(let t): t.badge
        case .snippet(let m): m.snippet.keyword.isEmpty ? "短语" : m.snippet.keyword
        case .fileHit(let hit): hit.mediaKind.badgeTitle
        case .clipboard(let entry): entry.payloadKind.badgeTitle
        case .plugin(let p): p.manifest.mode == .view ? "插件卡片" : "插件"
        case .command(let cmd): cmd.badgeLabel
        }
    }
}

private struct LiquidResultRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(LiquidMotion.pressSpring, value: configuration.isPressed)
    }
}

private extension View {
    func overlayRowHighlight(selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous)
        let prefs = SystemDisplayPreferences.shared.snapshot
        let reduceTransparency = prefs.reduceTransparency
        let highContrast = prefs.increaseContrast
        return background {
            if selected {
                ZStack {
                    if !reduceTransparency { shape.fill(.ultraThinMaterial) }
                    shape.fill(reduceTransparency ? LiquidColors.highlightGlow : LiquidColors.selectedRowFill)
                    if !reduceTransparency { shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)) }
                }
            }
        }
        .overlay {
            if selected {
                shape.strokeBorder(highContrast ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(LiquidColors.selectedRowRimGradient), lineWidth: highContrast ? 1.4 : 1.05)
            }
        }
        .shadow(color: selected && !reduceTransparency ? Color.cyan.opacity(0.12) : .clear, radius: 8, y: 2)
        .contentShape(shape)
    }
}
