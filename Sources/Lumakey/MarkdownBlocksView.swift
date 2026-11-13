import AppKit
import LumakeyCore
import SwiftUI

struct MarkdownBlocksStackView: View {
    let blocks: [MarkdownBlock]
    let baseFontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                renderBlock(block)
                    .id(block.id)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .frontmatter(_, let pairs):
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 6) {
                ForEach(pairs, id: \.self) { pair in
                    HStack(spacing: 4) {
                        Text(pair.key).font(.caption2.weight(.semibold)).foregroundStyle(.cyan)
                        Text(pair.value).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
        case .heading(_, let level, let text):
            VStack(alignment: .leading, spacing: 4) {
                inlineText(text, size: headingSize(level), weight: level <= 2 ? .bold : .semibold)
                if level <= 2 { Divider().opacity(0.3) }
            }
            .padding(.top, level == 1 ? 6 : 3)
        case .paragraph(_, let text):
            inlineText(text, size: baseFontSize, weight: .regular)
        case .codeBlock(_, let language, let code):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(language.isEmpty ? "code" : language).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    Spacer()
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    }
                    .buttonStyle(GlassPillButtonStyle())
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: max(11, baseFontSize - 1), design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                    .strokeBorder(LiquidColors.pillBorder, lineWidth: 0.8)
            }
        case .quote(_, let lines):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Color.cyan.opacity(0.65)).frame(width: 3)
                inlineText(lines.joined(separator: "\n"), size: baseFontSize, weight: .regular)
                    .foregroundStyle(.secondary)
            }
        case .alert(_, let kind, let lines):
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title).font(.caption.weight(.bold)).foregroundStyle(alertColor(kind))
                inlineText(lines.joined(separator: "\n"), size: baseFontSize - 0.5, weight: .regular)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alertColor(kind).opacity(0.12), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        case .bulletList(_, let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(.cyan)
                        inlineText(item, size: baseFontSize, weight: .regular)
                    }
                }
            }
        case .orderedList(_, let start, let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(start + idx).").font(.system(size: baseFontSize).monospacedDigit()).foregroundStyle(.cyan)
                        inlineText(item, size: baseFontSize, weight: .regular)
                    }
                }
            }
        case .taskList(_, let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.checked ? Color.green : Color.secondary)
                        inlineText(item.text, size: baseFontSize, weight: .regular)
                    }
                }
            }
        case .table(_, let headers, let rows):
            Group {
                if baseFontSize < 13 {
                    tableGrid(headers: headers, rows: rows, compact: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        tableGrid(headers: headers, rows: rows, compact: false)
                    }
                }
            }
            .background(LiquidColors.pillSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                    .strokeBorder(LiquidColors.pillBorder, lineWidth: 0.8)
            }
        case .divider:
            Divider().opacity(0.45)
        }
    }

    @ViewBuilder
    private func tableGrid(headers: [String], rows: [[String]], compact: Bool) -> some View {
        Grid(alignment: .leading, horizontalSpacing: compact ? 8 : 14, verticalSpacing: compact ? 5 : 6) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                    Text(h)
                        .font(.system(size: baseFontSize - 1, weight: .semibold))
                        .fixedSize(horizontal: !compact, vertical: true)
                }
            }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(0..<headers.count, id: \.self) { col in
                        inlineText(col < row.count ? row[col] : "", size: baseFontSize - 1, weight: .regular)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(compact ? 8 : 10)
    }

    private func inlineText(_ raw: String, size: CGFloat, weight: Font.Weight) -> some View {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attr = try? AttributedString(markdown: raw, options: opts) {
            return Text(attr).font(.system(size: size, weight: weight)).textSelection(.enabled)
        }
        return Text(raw).font(.system(size: size, weight: weight)).textSelection(.enabled)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: baseFontSize + 11
        case 2: baseFontSize + 7
        case 3: baseFontSize + 4
        default: baseFontSize + 1.5
        }
    }

    private func alertColor(_ kind: MarkdownAlertKind) -> Color {
        switch kind {
        case .note: .cyan
        case .tip: .green
        case .important: .purple
        case .warning: .orange
        case .caution: .red
        }
    }
}
