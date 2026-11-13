import AppKit
import LumakeyCore
import SwiftUI

@MainActor
private final class DocumentReaderState: ObservableObject {
    @Published var activeURL: URL?
    @Published var rawText: String = ""
    @Published var blocks: [MarkdownBlock] = []
    @Published var headings: [MarkdownHeadingItem] = []
    @Published var isTruncated: Bool = false
    @Published var showRawSource: Bool = false
    @Published var showOutline: Bool = true
    @Published var fontSize: CGFloat = 14

    func load(url: URL) {
        activeURL = url
        let (content, truncated) = MediaClassifier.loadDocumentText(at: url, maxBytes: 262_144)
        rawText = content
        isTruncated = truncated
        if MediaClassifier.classify(url: url, isDirectory: false) == .markdown {
            let parsed = MarkdownDocumentParser.parse(content)
            blocks = parsed
            headings = MarkdownDocumentParser.headings(in: parsed)
            showOutline = !headings.isEmpty
        } else {
            blocks = []
            headings = []
            showOutline = false
        }
    }

    func stepSibling(by delta: Int, in siblings: [URL], fallback: URL) {
        guard siblings.count > 1 else { return }
        let current = activeURL ?? fallback
        let idx = siblings.firstIndex(of: current) ?? 0
        let next = (idx + delta + siblings.count) % siblings.count
        load(url: siblings[next])
    }
}

struct DocumentReaderWindowView: View {
    let initialURL: URL
    let siblingURLs: [URL]
    let windowKey: String
    let onClose: () -> Void
    @StateObject private var state = DocumentReaderState()

    private var currentURL: URL { state.activeURL ?? initialURL }
    private var isMarkdown: Bool {
        MediaClassifier.classify(url: currentURL, isDirectory: false) == .markdown
    }

    var body: some View {
        SecondaryWindowScaffold(
            title: isMarkdown ? "Markdown 阅读器" : "代码与文本阅读",
            subtitle: currentURL.lastPathComponent,
            symbol: isMarkdown ? "text.document.fill" : "doc.plaintext",
            pinWindowKey: windowKey
        ) {
            VStack(spacing: 10) {
                let _ = onClose
                toolbarStrip
                mainContentPane
            }
        }
        .frame(minWidth: 820, minHeight: 580)
        .onAppear { state.load(url: initialURL) }
    }

    private var toolbarStrip: some View {
        HStack(alignment: .center, spacing: 10) {
            SquircleBadge(symbol: isMarkdown ? "text.document.fill" : "doc.plaintext", topColor: .cyan, bottomColor: .blue, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(currentURL.lastPathComponent).font(.headline).lineLimit(1)
                Text(currentURL.path).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if siblingURLs.count > 1 {
                Button("上一篇") { state.stepSibling(by: -1, in: siblingURLs, fallback: initialURL) }.buttonStyle(GlassPillButtonStyle())
                Button("下一篇") { state.stepSibling(by: 1, in: siblingURLs, fallback: initialURL) }.buttonStyle(GlassPillButtonStyle())
            }
            if isMarkdown {
                Button(state.showOutline ? "隐藏大纲" : "大纲") { state.showOutline.toggle() }.buttonStyle(GlassPillButtonStyle())
                Button(state.showRawSource ? "渲染视图" : "源码") { state.showRawSource.toggle() }.buttonStyle(GlassPillButtonStyle())
            }
            Button("A-") { state.fontSize = max(11, state.fontSize - 1) }.buttonStyle(GlassPillButtonStyle())
            Button("A+") { state.fontSize = min(24, state.fontSize + 1) }.buttonStyle(GlassPillButtonStyle())
            Button("复制全文") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(state.rawText, forType: .string)
            }.buttonStyle(GlassPillButtonStyle(prominent: true))
            Button("访达") { NSWorkspace.shared.activateFileViewerSelecting([currentURL]) }.buttonStyle(GlassPillButtonStyle())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }

    @ViewBuilder
    private var mainContentPane: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 12) {
                if isMarkdown && !state.showRawSource && state.showOutline && !state.headings.isEmpty {
                    outlineSidebar(proxy: proxy)
                        .frame(width: 220)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if state.isTruncated {
                            Text("提示：文档超过 256 KB，为保障零卡顿与低内存仅加载前 256 KB。")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(8)
                                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        }
                        if isMarkdown && !state.showRawSource {
                            MarkdownBlocksStackView(blocks: state.blocks, baseFontSize: state.fontSize)
                        } else {
                            NumberedRawTextView(text: state.rawText, fontSize: state.fontSize)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
            }
        }
    }

    private func outlineSidebar(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("文档大纲").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.bottom, 4)
                ForEach(state.headings) { item in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(item.id, anchor: .top)
                        }
                    } label: {
                        Text(item.text)
                            .font(.system(size: max(11, 13 - CGFloat(item.level - 1) * 0.5), weight: item.level == 1 ? .semibold : .regular))
                            .foregroundStyle(item.level <= 2 ? .primary : .secondary)
                            .padding(.leading, CGFloat(max(0, item.level - 1) * 10))
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }
}

private struct NumberedRawTextView: View {
    let text: String
    let fontSize: CGFloat

    var body: some View {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        LazyVStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(idx + 1)")
                        .font(.system(size: fontSize - 2, design: .monospaced).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 42, alignment: .trailing)
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: fontSize, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
