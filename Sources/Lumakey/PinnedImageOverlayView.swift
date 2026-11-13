import AppKit
import LumakeyCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PinOverlayState: ObservableObject {
    @Published var opacity: Double = 0.98
    @Published var isHovered: Bool = false
    @Published var statusBadge: String?
    private var badgeTask: Task<Void, Never>?

    func flashBadge(_ text: String, autoClear: Bool = true) {
        badgeTask?.cancel()
        statusBadge = text
        guard autoClear else { return }
        badgeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.statusBadge = nil
        }
    }
}

struct PinnedImageOverlayView: View {
    let image: NSImage
    let imageURL: URL
    let aspectRatio: CGFloat
    let onPinCutout: (URL) -> Void
    let onResetOriginalSize: () -> Void
    let onCloseAll: () -> Void
    let onClose: () -> Void
    @StateObject private var state = PinOverlayState()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        ZStack {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .opacity(state.opacity)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(LiquidColors.specularRimGradient, lineWidth: 1.4)
                }

            PinInteractionLayer(
                aspectRatio: aspectRatio,
                onDoubleClick: { copyImage() },
                onAdjustOpacity: { delta in
                    state.opacity = min(1.0, max(0.25, state.opacity + delta))
                    state.flashBadge("\(Int(round(state.opacity * 100)))% 透明")
                },
                onHoverChanged: { hovered in
                    state.isHovered = hovered
                },
                menuCallbacks: PinMenuCallbacks(
                    copyImage: { copyImage() },
                    runOCR: { runOCR() },
                    runCutout: { runCutout() },
                    resetSize: onResetOriginalSize,
                    toggleOpacity: { toggleOpacity() },
                    savePNG: { saveAsPNG() },
                    closeThis: onClose,
                    closeAll: onCloseAll
                )
            )

            VStack {
                HStack(spacing: 6) {
                    if let badge = state.statusBadge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.68), in: Capsule())
                    }
                    Spacer()
                    if state.isHovered {
                        toolbarPills
                    }
                }
                .padding(8)

                Spacer()
            }
        }
    }

    private var toolbarPills: some View {
        HStack(spacing: 5) {
            Button("识字") { runOCR() }
            Button("抠图") { runCutout() }
            Button("复制") { copyImage() }
            Button { toggleOpacity() } label: { Image(systemName: "circle.lefthalf.filled") }
                .help("半透明对比 (⌥+滚轮可微调)")
            Button { saveAsPNG() } label: { Image(systemName: "square.and.arrow.down") }
                .help("另存为 PNG")
            Button(action: onClose) { Image(systemName: "xmark") }
                .help("关闭此钉图 (Esc)")
        }
        .font(.caption2.weight(.semibold))
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThickMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous).strokeBorder(.white.opacity(0.32), lineWidth: 0.8)
        }
    }

    private func toggleOpacity() {
        state.opacity = state.opacity > 0.72 ? 0.55 : 0.98
        state.flashBadge("\(Int(round(state.opacity * 100)))% 透明")
    }

    private func copyImage() {
        if !ScreenshotCompositor.copyImageFileToPasteboard(at: imageURL) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
        }
        state.flashBadge("图片已复制")
    }

    private func saveAsPNG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "Lumakey-Pin-\(stamp).png"
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.copyItem(at: imageURL, to: dest)
            state.flashBadge("已保存")
        }
    }

    private func runOCR() {
        state.flashBadge("识字中…", autoClear: false)
        let url = imageURL
        Task {
            do {
                let res = try await Task.detached(priority: .userInitiated) {
                    try VisionService.analyzeTextAndBarcodes(at: url)
                }.value
                state.flashBadge(res.recognizedText.isEmpty && res.barcodes.isEmpty ? "无文本" : "OCR 已复制")
                OCRResultWindowController.shared.present(imageURL: url, analysis: res)
            } catch {
                state.flashBadge("识别失败")
            }
        }
    }

    private func runCutout() {
        state.flashBadge("抠图中…", autoClear: false)
        let url = imageURL
        Task {
            do {
                let outURL = try await Task.detached(priority: .userInitiated) {
                    try VisionService.liftForegroundSubject(from: url)
                }.value
                _ = ScreenshotCompositor.copyImageFileToPasteboard(at: outURL)
                state.flashBadge("已抠图并复制")
                onPinCutout(outURL)
            } catch {
                state.flashBadge("未检测到主体")
            }
        }
    }
}
