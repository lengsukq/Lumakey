import AppKit
import LumakeyCore
import SwiftUI

struct OverlayUnifiedRowsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        let items = viewModel.displayedCandidates
        if items.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: viewModel.omniFilter.symbolName)
                .padding(.top, 44)
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
                        Spacer()
                        candidateTrailingInfo(candidate, selected: isSelected)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlayRowHighlight(selected: isSelected)
                }
                .buttonStyle(.plain)
                .id("row-\(index)")
            }
        }
    }

    private var emptyTitle: String {
        switch viewModel.omniFilter {
        case .all: "无匹配应用、文件、剪贴板或命令"
        case .files: "无匹配文件，尝试 ext:md / pic: / 关键词"
        case .clipboard: "暂无匹配的剪贴板记录"
        case .plugins: "未找到可用插件，可在设置中心创建"
        }
    }

    @ViewBuilder
    private func candidateLeadingIcon(_ candidate: LauncherCandidate) -> some View {
        switch candidate.kind {
        case .app(let app):
            Image(nsImage: IconCache.shared.appIcon(for: app.url))
                .resizable().frame(width: 30, height: 30)
        case .calculator:
            SquircleBadge(symbol: "equal", topColor: .orange, bottomColor: .red, size: 30)
        case .fileHit(let hit):
            let ext = hit.url.pathExtension.lowercased()
            Image(nsImage: IconCache.shared.fileIcon(isDirectory: hit.isDirectory, extensionLowercased: ext))
                .resizable().frame(width: 28, height: 28)
        case .clipboard(let entry):
            clipboardLeadingBadge(entry)
        case .plugin:
            SquircleBadge(symbol: "puzzlepiece.extension.fill", topColor: .purple, bottomColor: .indigo, size: 30)
        case .command(let cmd):
            SquircleBadge(symbol: cmd.symbol, topColor: .cyan, bottomColor: .blue, size: 30)
        }
    }

    @ViewBuilder
    private func clipboardLeadingBadge(_ entry: ClipboardEntry) -> some View {
        switch entry.payloadKind {
        case .colorHex(let hex):
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LiquidColors.color(fromHex: hex) ?? .accentColor)
                .frame(width: 28, height: 28)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.45), lineWidth: 1)
                }
        case .image:
            SquircleBadge(symbol: "photo.fill", topColor: .pink, bottomColor: .purple, size: 28)
        case .file(let url):
            let ext = url.pathExtension.lowercased()
            Image(nsImage: IconCache.shared.fileIcon(isDirectory: false, extensionLowercased: ext))
                .resizable().frame(width: 28, height: 28)
        case .text:
            SquircleBadge(symbol: "doc.text.fill", topColor: .cyan, bottomColor: .blue, size: 28)
        }
    }

    @ViewBuilder
    private func candidateBody(_ candidate: LauncherCandidate) -> some View {
        switch candidate.kind {
        case .app(let app):
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.callout.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary)
                Text(app.url.path).font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
            }
        case .calculator(let expr, let resultText, _):
            VStack(alignment: .leading, spacing: 2) {
                Text(resultText).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(.cyan)
                Text(expr).font(.caption2).foregroundStyle(LiquidColors.textSecondary)
            }
        case .fileHit(let hit):
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.name).font(.callout.weight(.medium)).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
                Text(hit.relativeParentPath).font(.caption2.monospaced()).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
            }
        case .clipboard(let entry):
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.callout.weight(.medium)).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
                Text(entry.subtitle).font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
            }
        case .plugin(let plugin):
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.manifest.name).font(.callout.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary)
                Text(plugin.manifest.description).font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
            }
        case .command(let cmd):
            VStack(alignment: .leading, spacing: 2) {
                Text(cmd.title).font(.callout.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary)
                Text(cmd.subtitle).font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func candidateTrailingInfo(_ candidate: LauncherCandidate, selected: Bool) -> some View {
        HStack(spacing: 6) {
            if case .clipboard(let entry) = candidate.kind, entry.isPinned {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
            }
            if case .fileHit(let hit) = candidate.kind {
                Text(hit.formattedSize).font(.caption2.monospacedDigit()).foregroundStyle(LiquidColors.textSecondary)
            }
            if selected {
                Text(actionHint(for: candidate))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
            } else {
                Text(badgeText(for: candidate))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(LiquidColors.pillSurface, in: Capsule())
                    .overlay { Capsule().strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
            }
        }
    }

    private func actionHint(for candidate: LauncherCandidate) -> String {
        switch candidate.kind {
        case .calculator, .clipboard: "复制 ↩"
        case .plugin, .command: "执行 ↩"
        default: "打开 ↩"
        }
    }

    private func badgeText(for candidate: LauncherCandidate) -> String {
        switch candidate.kind {
        case .app: "应用"
        case .calculator(_, _, let b): b
        case .fileHit(let hit): hit.mediaKind.badgeTitle
        case .clipboard(let entry): entry.payloadKind.badgeTitle
        case .plugin: "插件"
        case .command(let cmd): cmd.badgeLabel
        }
    }
}

private extension View {
    func overlayRowHighlight(selected: Bool) -> some View {
        background {
            if selected {
                RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous)
                    .fill(LiquidColors.highlightGlow)
            }
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.0)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous))
    }
}
