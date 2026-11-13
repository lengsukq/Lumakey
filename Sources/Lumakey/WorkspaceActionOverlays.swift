import AppKit
import LumakeyCore
import SwiftUI

@MainActor
final class WorkspacePromptController: ObservableObject {
    enum Mode {
        case createFolder(pane: PaneSide, directory: URL)
        case renameSingle(pane: PaneSide, entry: FileEntry)
    }

    @Published var activeMode: Mode?
    @Published var inputText: String = ""
    @Published var inlineError: String?

    var isPresented: Bool { activeMode != nil }

    func presentCreateFolder(in pane: PaneSide, directory: URL) {
        inlineError = nil
        inputText = "新建文件夹"
        activeMode = .createFolder(pane: pane, directory: directory)
    }

    func presentSingleRename(entry: FileEntry, in pane: PaneSide) {
        inlineError = nil
        inputText = entry.name
        activeMode = .renameSingle(pane: pane, entry: entry)
    }

    func dismiss() {
        activeMode = nil
        inlineError = nil
    }
}

struct WorkspacePromptSheetView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var prompt: WorkspacePromptController

    private var isCreateFolder: Bool {
        if case .createFolder = prompt.activeMode { return true }
        return false
    }

    var body: some View {
        ZStack {
            LiquidFluidBackdrop()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    SquircleBadge(
                        symbol: isCreateFolder ? "folder.badge.plus" : "character.cursor.ibeam",
                        topColor: .cyan,
                        bottomColor: .blue,
                        size: 34
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isCreateFolder ? "新建文件夹" : "重命名项目").font(.headline)
                        Text(subtitleText).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                }

                GlassInputField(
                    symbol: isCreateFolder ? "folder" : "pencil",
                    placeholder: isCreateFolder ? "输入新文件夹名称…" : "输入新名称…",
                    text: $prompt.inputText
                )
                .onSubmit { viewModel.submitWorkspacePrompt() }

                if let err = prompt.inlineError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                HStack {
                    Spacer()
                    Button("取消") { prompt.dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(GlassPillButtonStyle())
                    Button(isCreateFolder ? "创建" : "确认重命名") { viewModel.submitWorkspacePrompt() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                }
            }
            .padding(18)
        }
        .frame(width: 440, height: prompt.inlineError == nil ? 186 : 222)
    }

    private var subtitleText: String {
        switch prompt.activeMode {
        case .createFolder(_, let dir): "位置：\(dir.path)"
        case .renameSingle(_, let entry): "原名称：\(entry.name)"
        case .none: ""
        }
    }
}

struct WorkspaceFloatingActionBar: View {
    @ObservedObject var viewModel: AppViewModel
    let pane: PaneSide

    var body: some View {
        let selected = viewModel.selectedEntries(in: pane)
        let clip = viewModel.activePane == pane ? viewModel.workspaceClipboard : nil
        if !selected.isEmpty || (clip != nil && !(clip?.isEmpty ?? true)) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let summary = viewModel.selectionSummaryText(in: pane) {
                        LiquidStatusPill(title: summary, symbol: "checkmark.circle.fill", tint: .cyan, prominent: true)
                    }
                    if !selected.isEmpty {
                        Button("复制 ⌘C") { viewModel.copyEntriesToWorkspaceClipboard(selected, cut: false) }
                            .buttonStyle(GlassPillButtonStyle())
                        Button("剪切 ⌘X") { viewModel.copyEntriesToWorkspaceClipboard(selected, cut: true) }
                            .buttonStyle(GlassPillButtonStyle())
                        if viewModel.layoutMode == .dual {
                            let targetTitle = pane == .left ? "右栏" : "左栏"
                            Button("移至\(targetTitle)") { viewModel.transferToOtherPane(entries: selected, copy: false, from: pane) }
                                .buttonStyle(GlassPillButtonStyle())
                            Button("拷至\(targetTitle)") { viewModel.transferToOtherPane(entries: selected, copy: true, from: pane) }
                                .buttonStyle(GlassPillButtonStyle())
                        }
                        Button("移动到…") { viewModel.chooseDirectoryAndTransfer(entries: selected, copy: false, sourcePane: pane) }
                            .buttonStyle(GlassPillButtonStyle())
                        Button("复制到…") { viewModel.chooseDirectoryAndTransfer(entries: selected, copy: true, sourcePane: pane) }
                            .buttonStyle(GlassPillButtonStyle())
                        if selected.count == 1 {
                            Button("重命名 ↩") { viewModel.beginSingleRename(selected[0], in: pane) }
                                .buttonStyle(GlassPillButtonStyle())
                        } else {
                            Button("批量重命名") { viewModel.activePane = pane; viewModel.showBatchRenameSheet = true }
                                .buttonStyle(GlassPillButtonStyle())
                        }
                        Button("废纸篓 ⌘⌫") { viewModel.trashEntries(selected, in: pane) }
                            .buttonStyle(GlassPillButtonStyle())
                    }
                    if let clip, !clip.isEmpty {
                        let label = clip.mode == .cutMove
                            ? "移动 \(clip.urls.count) 项到此目录 (⌘V)"
                            : "粘贴 \(clip.urls.count) 项到此目录 (⌘V)"
                        Button(label) { viewModel.pasteWorkspaceClipboard(in: pane, forceMove: false) }
                            .buttonStyle(GlassPillButtonStyle(prominent: true))
                        if clip.mode == .copy {
                            Button("移入此处 (⌘⌥V)") { viewModel.pasteWorkspaceClipboard(in: pane, forceMove: true) }
                                .buttonStyle(GlassPillButtonStyle())
                        }
                        Button { viewModel.workspaceClipboard = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("清空待粘贴剪贴板")
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 20)
                .padding(.vertical, 6)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.95),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .liquidGlassCard(cornerRadius: LiquidRadii.row, solidReadable: true)
        }
    }
}

struct WorkspaceKeyShortcutBridgeView: NSViewRepresentable {
    let viewModel: AppViewModel

    func makeNSView(context: Context) -> ShortcutMonitorNSView {
        let view = ShortcutMonitorNSView()
        view.viewModel = viewModel
        view.installMonitorIfNeeded()
        return view
    }

    func updateNSView(_ nsView: ShortcutMonitorNSView, context: Context) {
        nsView.viewModel = viewModel
        nsView.installMonitorIfNeeded()
    }

    static func dismantleNSView(_ nsView: ShortcutMonitorNSView, coordinator: ()) {
        nsView.removeMonitor()
    }
}

@MainActor
final class ShortcutMonitorNSView: NSView {
    weak var viewModel: AppViewModel?
    nonisolated(unsafe) private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window == nil ? removeMonitor() : installMonitorIfNeeded()
    }

    func installMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let targetWindow = window,
              event.window === targetWindow,
              targetWindow.isKeyWindow,
              targetWindow.attachedSheet == nil,
              let vm = viewModel,
              !vm.showBatchRenameSheet,
              !vm.workspacePrompt.isPresented else { return event }
        if let responder = targetWindow.firstResponder, responder is NSText || responder is NSTextField {
            return event
        }
        return vm.handleWorkspaceKeyShortcut(event) ? nil : event
    }
}
