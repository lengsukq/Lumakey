import AppKit
import LumakeyCore
import SwiftUI

struct PluginViewLensContainerCard: View {
    let payload: PluginViewPayload
    let onCopyText: (String) -> Void
    let onOpenURL: (URL) -> Void
    let onRunCommandArgs: ([String]) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SquircleBadge(symbol: "rectangle.3.group.bubble.fill", topColor: .cyan, bottomColor: .indigo, size: 26)
                Text("插件视图卡片")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LiquidColors.textSecondary)
                Spacer()
                LiquidKeyHintBadge(keyText: "Esc 关闭")
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(GlassPillButtonStyle())
            }

            ScrollView {
                PluginStructuredViewCard(
                    payload: payload,
                    onCopyText: onCopyText,
                    onOpenURL: onOpenURL,
                    onRunCommandArgs: onRunCommandArgs
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct DevToolLensCard: View {
    let tool: DevToolResult
    let onExecute: () -> Void
    let onCopyText: (String, String) -> Void
    let onPinImage: (URL) -> Void

    var body: some View {
        if let qrURL = tool.previewImageURL {
            qrPreviewBody(url: qrURL)
        } else if let hex = tool.colorHex {
            colorSwatchBody(hex: hex)
        } else {
            textOutputBody
        }
    }

    private func qrPreviewBody(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LiquidStatusPill(title: tool.badge, symbol: "qrcode", tint: .cyan)
                Spacer()
                LiquidKeyHintBadge(keyText: "↩ 复制 PNG", highlighted: true)
            }
            ZStack {
                RoundedRectangle(cornerRadius: LiquidRadii.card, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 196, height: 196)
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
                if let img = NSImage(contentsOf: url) {
                    Image(nsImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 172, height: 172)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)

            Text(tool.copyText)
                .font(.caption2.monospaced())
                .foregroundStyle(LiquidColors.textSecondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                Button { onExecute() } label: {
                    Label("复制 PNG ↩", systemImage: "doc.on.doc")
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true))

                Button { onPinImage(url) } label: {
                    Label("贴图置顶", systemImage: "pin.fill")
                }
                .buttonStyle(GlassPillButtonStyle())

                Button("源文本") {
                    onCopyText(tool.copyText, "已复制二维码源文本")
                }
                .buttonStyle(GlassPillButtonStyle())
            }
        }
    }

    private func colorSwatchBody(hex: String) -> some View {
        let swatch = LiquidColors.color(fromHex: hex) ?? .accentColor
        let shape = RoundedRectangle(cornerRadius: LiquidRadii.card, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                shape.fill(swatch)
                    .overlay { shape.fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .topLeading, endPoint: .center)) }
                    .overlay { shape.strokeBorder(.white.opacity(0.48), lineWidth: 1.0) }
                    .shadow(color: swatch.opacity(0.30), radius: 10, y: 4)
                Text(hex)
                    .font(.callout.monospaced().weight(.bold))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(LiquidColors.elevatedSurface, in: Capsule(style: .continuous))
                    .padding(10)
            }
            .frame(height: 146)

            VStack(alignment: .leading, spacing: 6) {
                LiquidStatusPill(title: tool.badge, symbol: tool.symbol, tint: .cyan)
                Text(tool.copyText)
                    .font(.callout.monospaced().weight(.semibold))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .textSelection(.enabled)
                Text(tool.subtitle)
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassCard(cornerRadius: LiquidRadii.row, solidReadable: true)

            Spacer(minLength: 0)
            Button("复制 \(tool.badge) ↩", action: onExecute)
                .buttonStyle(GlassPillButtonStyle(prominent: true))
        }
    }

    private var textOutputBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LiquidStatusPill(title: tool.badge, symbol: tool.symbol, tint: .mint)
                Spacer()
                LiquidKeyHintBadge(keyText: "↩ 复制", highlighted: true)
            }
            Text(tool.subtitle)
                .font(.caption2)
                .foregroundStyle(LiquidColors.textSecondary)
            ScrollView {
                Text(tool.copyText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(12)
            .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)

            Button("一键复制结果 ↩", action: onExecute)
                .buttonStyle(GlassPillButtonStyle(prominent: true))
        }
    }
}

struct SnippetLensCard: View {
    let match: SnippetMatch
    let onExecute: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                LiquidStatusPill(title: match.snippet.keyword.isEmpty ? "短语" : match.snippet.keyword, symbol: "text.quote", tint: .cyan)
                LiquidStatusPill(title: match.snippet.category, tint: .indigo)
                Spacer()
                LiquidKeyHintBadge(keyText: "↩ 复制", highlighted: true)
            }
            Text(match.snippet.title)
                .font(.callout.weight(.bold))
                .foregroundStyle(LiquidColors.textPrimary)

            ScrollView {
                Text(match.expandedText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(12)
            .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)

            HStack(spacing: 8) {
                Button("复制展开文本 ↩", action: onExecute)
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
                Button("管理词库…", action: onOpenSettings)
                    .buttonStyle(GlassPillButtonStyle())
            }
        }
    }
}
