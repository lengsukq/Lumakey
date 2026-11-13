import AppKit
import SwiftUI
import LumakeyCore

@MainActor
private final class ImageViewerState: ObservableObject {
    @Published var scale: CGFloat = 1.0
    @Published var currentURL: URL?

    func step(by delta: Int, in siblings: [URL], fallback: URL) {
        guard !siblings.isEmpty else { return }
        let active = currentURL ?? fallback
        let idx = siblings.firstIndex(of: active) ?? 0
        let next = (idx + delta + siblings.count) % siblings.count
        currentURL = siblings[next]
        scale = 1.0
    }
}

struct ReadOnlyImageViewerSheet: View {
    let initialURL: URL
    let siblingURLs: [URL]
    let windowKey: String
    let onClose: () -> Void
    @StateObject private var state = ImageViewerState()

    private var activeURL: URL { state.currentURL ?? initialURL }

    var body: some View {
        let indexText = siblingURLs.isEmpty ? nil : "\((siblingURLs.firstIndex(of: activeURL) ?? 0) + 1) / \(siblingURLs.count)"
        SecondaryWindowScaffold(
            title: "只读看图",
            subtitle: indexText,
            symbol: "photo.on.rectangle.angled",
            pinWindowKey: windowKey
        ) {
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    SquircleBadge(symbol: "photo.fill", topColor: .pink, bottomColor: .purple, size: 32)
                    Text(activeURL.lastPathComponent).font(.callout.weight(.semibold)).lineLimit(1)
                    Text("\(Int(round(state.scale * 100)))%")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(LiquidColors.pillSurface, in: Capsule())
                    Spacer()
                    Button { state.step(by: -1, in: siblingURLs, fallback: initialURL) } label: {
                        Label("上一张", systemImage: "chevron.left")
                    }
                    .buttonStyle(GlassPillButtonStyle()).disabled(siblingURLs.count <= 1)
                    Button { state.step(by: 1, in: siblingURLs, fallback: initialURL) } label: {
                        Label("下一张", systemImage: "chevron.right")
                    }
                    .buttonStyle(GlassPillButtonStyle()).disabled(siblingURLs.count <= 1)
                    Button { state.scale = max(0.25, state.scale - 0.25) } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }.buttonStyle(GlassPillButtonStyle())
                    Button("100%") { state.scale = 1.0 }.buttonStyle(GlassPillButtonStyle())
                    Button { state.scale = min(4.0, state.scale + 0.25) } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }.buttonStyle(GlassPillButtonStyle())
                    Button { PinWindowController.shared.pinImage(at: activeURL) } label: {
                        Label("贴图置顶", systemImage: "pin.fill")
                    }.buttonStyle(GlassPillButtonStyle(prominent: true))
                    Button { NSWorkspace.shared.activateFileViewerSelecting([activeURL]) } label: {
                        Label("Finder", systemImage: "folder")
                    }.buttonStyle(GlassPillButtonStyle())
                    let _ = onClose
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .liquidGlassCard(cornerRadius: LiquidRadii.bento)

                if let nsImage = NSImage(contentsOf: activeURL) {
                    GeometryReader { geo in
                        ScrollView([.horizontal, .vertical]) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: max(240, min(nsImage.size.width, 720) * state.scale))
                                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .center)
                        }
                    }
                    .liquidGlassCard(cornerRadius: LiquidRadii.bento)
                } else {
                    ContentUnavailableView("无法读取图像文件", systemImage: "photo")
                }
            }
        }
        .frame(minWidth: 800, minHeight: 580)
    }
}

struct BatchRenameSheet: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ZStack {
            LiquidFluidBackdrop()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SquircleBadge(symbol: "pencil.and.list.clipboard", topColor: .orange, bottomColor: .pink, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("安全批量重命名").font(.headline)
                        Text("共 \(viewModel.batchRenamePreview.count) 项待预览，提交前自动校验重名与非法字符")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("序号递增", isOn: $viewModel.renameRule.useIndexNumbering)
                        .toggleStyle(.switch)
                }
                .padding(12)
                .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)

                HStack(spacing: 8) {
                    GlassInputField(symbol: "magnifyingglass", placeholder: "查找文本", text: $viewModel.renameRule.findText)
                    GlassInputField(symbol: "arrow.triangle.2.circlepath", placeholder: "替换为", text: $viewModel.renameRule.replaceText)
                    GlassInputField(placeholder: "统一前缀", text: $viewModel.renameRule.prefix)
                    GlassInputField(placeholder: "统一后缀", text: $viewModel.renameRule.suffix)
                }

                List(viewModel.batchRenamePreview) { item in
                    HStack(spacing: 8) {
                        Text(item.originalName).foregroundStyle(.secondary).lineLimit(1)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.cyan)
                        Text(item.proposedName).fontWeight(.medium).lineLimit(1)
                        Spacer()
                        if let reason = item.conflictReason {
                            Text(reason)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.red, in: Capsule())
                        } else {
                            Text("可提交")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
                .frame(minHeight: 240)

                HStack {
                    Spacer()
                    Button("取消") { viewModel.showBatchRenameSheet = false }
                        .buttonStyle(GlassPillButtonStyle())
                    Button("确认重命名") { viewModel.applyBatchRename() }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                        .disabled(viewModel.batchRenamePreview.contains(where: \.hasConflict))
                }
            }
            .padding(16)
        }
        .frame(minWidth: 740, minHeight: 450)
    }
}

struct WorkspaceHostView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        SecondaryWindowScaffold(
            title: "文件与外置磁盘工作台",
            subtitle: viewModel.layoutMode == .dual ? "双栏模式" : "单栏模式",
            symbol: "externaldrive.fill.badge.checkmark",
            pinWindowKey: "workspace"
        ) {
            FileWorkspaceView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showBatchRenameSheet) { BatchRenameSheet(viewModel: viewModel) }
        .alert(
            viewModel.diagnostic?.title ?? "提示",
            isPresented: Binding(get: { viewModel.diagnostic != nil }, set: { if !$0 { viewModel.diagnostic = nil } })
        ) {
            Button("确定", role: .cancel) { viewModel.diagnostic = nil }
        } message: {
            if let diag = viewModel.diagnostic {
                Text("\(diag.reason)\n\(diag.dataSafety)\n\(diag.nextStep)")
            }
        }
    }
}
