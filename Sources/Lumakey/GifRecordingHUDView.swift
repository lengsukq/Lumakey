import AppKit
import LumakeyCore
import SwiftUI

final class GifHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @MainActor
    static func present(near region: NSRect, screenFrame: NSRect, controller: GifCaptureController) -> GifHUDPanel {
        let hudW: CGFloat = 650, hudH: CGFloat = 64
        let visible = NSScreen.screens.first(where: { $0.frame.intersects(screenFrame) })?.visibleFrame ?? screenFrame
        let x = min(max(region.midX - hudW / 2, visible.minX + 8), visible.maxX - hudW - 8)
        let aboveY = region.maxY + 10, belowY = region.minY - hudH - 10
        let y: CGFloat = (aboveY + hudH <= visible.maxY - 4) ? aboveY : ((belowY >= visible.minY + 4) ? belowY : visible.maxY - hudH - 8)

        let panel = GifHUDPanel(
            contentRect: NSRect(x: x, y: y, width: hudW, height: hudH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: GifRecordingHUDView(controller: controller))
        panel.orderFrontRegardless()
        return panel
    }

    @MainActor
    static func presentSelection(
        session: GifSelectionSession,
        on screen: NSScreen,
        onStart: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> CaptureOverlayPanel {
        let panel = CaptureOverlayPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(rootView: GifSelectionOverlayView(session: session, onStartRecording: onStart, onCancel: onCancel))
        panel.setFrame(screen.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return panel
    }
}

struct GifRecordingHUDView: View {
    @ObservedObject var controller: GifCaptureController

    var body: some View {
        ZStack {
            switch controller.phase {
            case .recording(let isPaused):
                recordingCapsule(isPaused: isPaused)
            case .encoding:
                encodingCapsule
            case .completed(let result):
                completedCapsule(result: result)
            case .idle, .selectingRegion:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.30, dampingFraction: 0.84), value: controller.phase)
    }

    private func recordingCapsule(isPaused: Bool) -> some View {
        let pulse = isPaused ? 1.0 : (0.45 + 0.55 * (0.5 + 0.5 * sin(controller.elapsedSeconds * 5.4)))
        let dotColor = isPaused ? Color.orange : Color(red: 1.0, green: 0.24, blue: 0.22)
        let dimLabel = GifRecordingOptions.dimensionLabel(for: controller.options.maxDimension)

        return HStack(spacing: 10) {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(dotColor.opacity(0.30 * pulse)).frame(width: 16, height: 16)
                    Circle().fill(dotColor.opacity(pulse)).frame(width: 8.5, height: 8.5)
                }
                Text(Self.formatDuration(controller.elapsedSeconds))
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(.white)
            }
            .padding(.leading, 4)

            capsuleDivider

            HStack(spacing: 6) {
                Text(frameSummaryText(isPaused: isPaused))
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.86))
                Text("\(dimLabel)·\(controller.options.fps)FPS")
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.cyan)
                    .padding(.horizontal, 7).padding(.vertical, 2.5).background(.cyan.opacity(0.16), in: Capsule())
            }

            capsuleDivider

            HStack(spacing: 6) {
                hudButton(title: isPaused ? "继续" : "暂停", symbol: isPaused ? "play.fill" : "pause.fill", tint: .white.opacity(0.14)) {
                    controller.togglePauseResume()
                }
                hudButton(title: "取消", symbol: "xmark", tint: .white.opacity(0.12)) {
                    controller.cancelCapture()
                }
                Button(action: { controller.finishRecording() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill").font(.system(size: 9, weight: .bold))
                        Text("完成并复制").font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(.white).padding(.horizontal, 11).padding(.vertical, 5.5)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.28, blue: 0.26), Color(red: 0.88, green: 0.14, blue: 0.34)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                }
                .buttonStyle(GifScaleButtonStyle())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .modifier(DynamicIslandGlassModifier())
    }

    private var encodingCapsule: some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small).tint(.cyan)
            Text("正在合成 GIF89a 动图 (\(controller.encodedFrameCount) 帧)…")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .modifier(DynamicIslandGlassModifier())
    }

    private func completedCapsule(result: GifFinalizeResult) -> some View {
        let sizeText = FastFormatters.formatFileBytes(result.fileSizeBytes)
        let w = Int(result.pixelSize.width), h = Int(result.pixelSize.height)

        return HStack(spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("已复制 GIF 动图").font(.system(size: 11.5, weight: .bold)).foregroundStyle(.white)
                    Text("\(sizeText) · \(w)×\(h) · \(result.frameCount)帧")
                        .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.leading, 3)

            capsuleDivider

            HStack(spacing: 6) {
                hudButton(title: "另存为", symbol: "square.and.arrow.down", tint: .white.opacity(0.14)) { controller.saveResultAs(result) }
                hudButton(title: "访达定位", symbol: "folder", tint: .white.opacity(0.14)) { controller.revealResultInFinder(result) }
                hudButton(title: "预览", symbol: "eye", tint: .white.opacity(0.14)) { controller.previewResult(result) }
                hudButton(title: "再来一段", symbol: "arrow.clockwise", tint: .cyan.opacity(0.28)) { controller.recordAgain() }
                Button(action: { controller.dismissCompletedHUD() }) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.78))
                        .frame(width: 24, height: 24).background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(GifScaleButtonStyle())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7.5)
        .modifier(DynamicIslandGlassModifier())
    }

    private var capsuleDivider: some View {
        Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 18)
    }

    private func frameSummaryText(isPaused: Bool) -> String {
        if isPaused { return "已暂停 · \(controller.encodedFrameCount)帧" }
        return controller.mergedFrameCount > 0
            ? "\(controller.encodedFrameCount)帧 (省\(controller.mergedFrameCount))"
            : "\(controller.encodedFrameCount) 帧"
    }

    private func hudButton(title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.94)).padding(.horizontal, 9.5).padding(.vertical, 5.5)
            .background(tint, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.7))
        }
        .buttonStyle(GifScaleButtonStyle())
    }

    static func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct DynamicIslandGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        content
            .background {
                ZStack {
                    if !reduceTransparency { Capsule(style: .continuous).fill(.ultraThinMaterial) }
                    Capsule(style: .continuous).fill(Color(red: 0.06, green: 0.07, blue: 0.11).opacity(reduceTransparency ? 0.96 : 0.76))
                    WindowDragRegion()
                }
            }
            .clipShape(Capsule(style: .continuous))
            .overlay { Capsule(style: .continuous).strokeBorder(LiquidColors.specularRimGradient, lineWidth: 1.0) }
            .shadow(color: .black.opacity(0.32), radius: 12, y: 5)
    }
}

private struct GifScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}
