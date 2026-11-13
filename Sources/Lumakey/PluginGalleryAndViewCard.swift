import AppKit
import LumakeyCore
import SwiftUI

struct PluginStructuredViewCard: View {
    let payload: PluginViewPayload
    var onCopyText: ((String) -> Void)? = nil
    var onOpenURL: ((URL) -> Void)? = nil
    var onRunCommandArgs: (([String]) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(payload.title)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(LiquidColors.textPrimary)
                    if let subtitle = payload.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(LiquidColors.textSecondary)
                    }
                }
                Spacer(minLength: 6)
                if let badge = payload.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
                        .overlay { Capsule(style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
                }
            }

            if let metrics = payload.metrics, !metrics.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(metrics) { metric in
                        Button { copyValue(metric.value) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric.key)
                                    .font(.caption2)
                                    .foregroundStyle(LiquidColors.textSecondary)
                                Text(metric.value)
                                    .font(.caption.monospaced().weight(.semibold))
                                    .foregroundStyle(LiquidColors.textPrimary)
                                    .lineLimit(1)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                                    .strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let items = payload.items, !items.isEmpty {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        itemRow(item)
                    }
                }
            }

            if let markdown = payload.markdown, !markdown.isEmpty {
                markdownBlock(markdown)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func itemRow(_ item: PluginViewItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon ?? "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 26, height: 26)
                .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .lineLimit(1)
                if let sub = item.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if let badge = item.badge, !badge.isEmpty {
                Text(badge)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(LiquidColors.pillSurface, in: Capsule())
            }
            if let copyText = item.copyText, !copyText.isEmpty {
                Button("复制") { copyValue(copyText) }
                    .buttonStyle(GlassPillButtonStyle())
            }
            if let rawURL = item.openURL, let url = URL(string: rawURL) {
                Button("打开") {
                    if let onOpenURL { onOpenURL(url) } else { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(GlassPillButtonStyle())
            }
            if let args = item.commandArgs, !args.isEmpty, let onRunCommandArgs {
                Button("执行") { onRunCommandArgs(args) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(LiquidColors.pillSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                .strokeBorder(LiquidColors.pillBorder, lineWidth: 0.65)
        }
    }

    @ViewBuilder
    private func markdownBlock(_ raw: String) -> some View {
        let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        Group {
            if let attributed {
                Text(attributed)
            } else {
                Text(raw)
            }
        }
        .font(.caption)
        .foregroundStyle(LiquidColors.textPrimary)
        .textSelection(.enabled)
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
    }

    private func copyValue(_ value: String) {
        if let onCopyText {
            onCopyText(value)
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    }
}

struct PluginStarterGalleryListView: View {
    let installedIDs: Set<String>
    let onInstall: (PluginStarterTemplate) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                ForEach(PluginStarterGallery.templates) { tpl in
                    let installed = installedIDs.contains(tpl.id)
                    HStack(alignment: .center, spacing: 11) {
                        SquircleBadge(
                            symbol: tpl.icon,
                            topColor: tpl.mode == .view ? .cyan : .purple,
                            bottomColor: tpl.mode == .view ? .blue : .indigo,
                            size: 36
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(tpl.name).font(.caption.weight(.bold)).foregroundStyle(LiquidColors.textPrimary)
                                Text(tpl.mode.rawValue.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(tpl.mode == .view ? .cyan : .purple)
                                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                                    .background(LiquidColors.pillSurface, in: Capsule())
                            }
                            Text(tpl.description)
                                .font(.caption2)
                                .foregroundStyle(LiquidColors.textSecondary)
                                .lineLimit(2)
                            Text("触发词: \(tpl.keywords.joined(separator: ", "))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(LiquidColors.textSecondary)
                        }
                        Spacer(minLength: 6)
                        Button(installed ? "重装/预览" : "一键安装") { onInstall(tpl) }
                            .buttonStyle(GlassPillButtonStyle(prominent: !installed))
                    }
                    .padding(10)
                    .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
                }
            }
        }
    }
}

struct PluginConfigFormCard: View {
    let plugin: PluginDescriptor
    let fields: [PluginConfigField]
    @ObservedObject var ctrl: PluginCenterController
    let viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("参数配置 (plugin-state.json)").font(.caption.weight(.bold))
                Spacer()
                Button("保存配置") { ctrl.saveConfig(for: plugin, viewModel: viewModel) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
            ForEach(fields) { field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.label).font(.caption2.weight(.medium)).foregroundStyle(LiquidColors.textSecondary)
                    switch field.type {
                    case .text:
                        GlassInputField(symbol: "slider.horizontal.3", placeholder: field.placeholder ?? field.key, text: ctrl.binding(for: field))
                    case .secret:
                        SecureField(field.placeholder ?? "输入密钥参数", text: ctrl.binding(for: field))
                            .textFieldStyle(.plain).font(.caption)
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(LiquidColors.inputFieldSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                    case .boolean:
                        Toggle(field.label, isOn: ctrl.boolBinding(for: field)).toggleStyle(.switch).font(.caption)
                    case .select:
                        HStack(spacing: 6) {
                            ForEach(field.options ?? [], id: \.self) { opt in
                                Button(opt) { ctrl.configDraft[field.key] = opt }
                                    .buttonStyle(GlassPillButtonStyle(prominent: (ctrl.configDraft[field.key] ?? field.defaultValue) == opt))
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }
}
