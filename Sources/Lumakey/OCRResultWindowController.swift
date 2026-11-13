import AppKit
import LumakeyCore
import SwiftUI

@MainActor
final class OCRResultState: ObservableObject {
    let imageURL: URL
    let rawText: String
    let barcodes: [String]
    let thumbnail: NSImage?
    @Published var mergeLines: Bool = false
    @Published var editableText: String
    @Published var toastText: String

    init(imageURL: URL, analysis: VisionTextAnalysis) {
        self.imageURL = imageURL
        self.rawText = ([analysis.recognizedText] + analysis.barcodes)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        self.barcodes = analysis.barcodes
        self.thumbnail = NSImage(contentsOf: imageURL)
        self.editableText = self.rawText
        self.toastText = self.rawText.isEmpty ? "未检测到文本" : "✓ 已自动复制到剪贴板"
    }

    func toggleMergeLines() {
        mergeLines.toggle()
        if mergeLines {
            editableText = Self.smartJoinLines(rawText)
        } else {
            editableText = rawText
        }
        copyAll()
    }

    func copyAll() {
        guard !editableText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(editableText, forType: .string)
        toastText = "✓ 已复制到剪贴板"
    }

    private static func smartJoinLines(_ raw: String) -> String {
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard var acc = lines.first else { return "" }
        for line in lines.dropFirst() {
            let lastScalar = acc.unicodeScalars.last
            let nextScalar = line.unicodeScalars.first
            let bothASCII = (lastScalar?.isASCII == true) && (nextScalar?.isASCII == true)
            acc += (bothASCII ? " " : "") + line
        }
        return acc
    }
}

private final class KeyableOCRWindow: NSWindow {
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

@MainActor
final class OCRResultWindowController: NSObject, NSWindowDelegate {
    static let shared = OCRResultWindowController()
    var onVisibilityChanged: (() -> Void)?
    private var window: KeyableOCRWindow?

    var isWindowVisible: Bool { window?.isVisible == true }

    func bringToFrontIfVisible() -> Bool {
        guard let win = window, win.isVisible else { return false }
        if win.isMiniaturized { win.deminiaturize(nil) }
        win.makeKeyAndOrderFront(nil)
        return true
    }

    func present(imageURL: URL, analysis: VisionTextAnalysis, onRetake: (() -> Void)? = nil) {
        let state = OCRResultState(imageURL: imageURL, analysis: analysis)
        if !state.editableText.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(state.editableText, forType: .string)
        } else {
            _ = ScreenshotCompositor.copyImageFileToPasteboard(at: imageURL)
        }

        let win = window ?? KeyableOCRWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Vision 离线识字结果"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.onEscape = { [weak win] in win?.close() }
        if window == nil { win.center() }

        win.contentView = NSHostingView(rootView: OCRResultSheetView(
            state: state,
            onPinImage: { PinWindowController.shared.pinImage(at: imageURL) },
            onRetake: { [weak win] in
                win?.close()
                onRetake?()
            },
            onClose: { [weak win] in win?.close() }
        ))
        WindowLevelStore.shared.attach(window: win, key: "ocrResult", initialPinned: true)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
        onVisibilityChanged?()
    }

    func windowWillClose(_ notification: Notification) {
        WindowLevelStore.shared.detach(key: "ocrResult")
        window?.delegate = nil
        window?.contentView = nil
        window = nil
        onVisibilityChanged?()
        MemoryStats.reclaimFreeHeapPages()
    }
}

private struct OCRResultSheetView: View {
    @ObservedObject var state: OCRResultState
    let onPinImage: () -> Void
    let onRetake: () -> Void
    let onClose: () -> Void

    var body: some View {
        SecondaryWindowScaffold(
            title: "Vision 离线识字",
            subtitle: state.rawText.isEmpty ? "未检测到文本" : "\(state.editableText.count) 字符",
            symbol: "text.viewfinder",
            pinWindowKey: "ocrResult"
        ) {
            VStack(spacing: 10) {
                let _ = onClose
                headerBar
                contentArea
            }
        }
        .frame(minWidth: 600, minHeight: 420)
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            SquircleBadge(symbol: "text.viewfinder", topColor: .indigo, bottomColor: .purple, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vision 离线识字结果").font(.callout.weight(.semibold))
                Text("\(state.toastText) · \(state.editableText.count) 字符")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(state.rawText.isEmpty ? .orange : .green)
            }
            Spacer()
            Button(state.mergeLines ? "保留段落" : "合并换行") { state.toggleMergeLines() }
                .buttonStyle(GlassPillButtonStyle()).disabled(state.rawText.isEmpty)
            Button("钉住原图", action: onPinImage).buttonStyle(GlassPillButtonStyle())
            Button("再次识字 (⌥O)", action: onRetake).buttonStyle(GlassPillButtonStyle())
            Button("复制全文") { state.copyAll() }
                .buttonStyle(GlassPillButtonStyle(prominent: true)).disabled(state.editableText.isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }

    private var contentArea: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("选区原图").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("点击钉屏").font(.caption2).foregroundStyle(.tertiary)
                }
                if let img = state.thumbnail {
                    Button(action: onPinImage) {
                        ZStack {
                            RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                                .fill(LiquidColors.pillSurface)
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .padding(6)
                        }
                        .frame(height: 196)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .help("点击钉住原图到屏幕")
                }
                if !state.barcodes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("条码 / 二维码").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(state.barcodes, id: \.self) { code in
                            Button {
                                if let url = URL(string: code), url.scheme?.hasPrefix("http") == true {
                                    NSWorkspace.shared.open(url)
                                } else {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(code, forType: .string)
                                    state.toastText = "已复制条码"
                                }
                            } label: {
                                Text(code)
                                    .font(.caption2.monospaced())
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(GlassPillButtonStyle())
                        }
                    }
                }
                Spacer()
                Text("Esc 关闭窗口 · 可直接编辑校准")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(width: 204)
            .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)

            Group {
                if state.rawText.isEmpty {
                    ContentUnavailableView {
                        Label("未检测到清晰文字", systemImage: "text.magnifyingglass")
                    } description: {
                        Text("可点击右上角“再次识字 (⌥O)”重新框选区域。")
                    }
                } else {
                    TextEditor(text: $state.editableText)
                        .font(.system(size: 13.5))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
        }
    }
}
