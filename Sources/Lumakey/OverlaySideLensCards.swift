import AppKit
import CoreImage.CIFilterBuiltins
import LumakeyCore
import SwiftUI

@MainActor
private final class ImageQRScannerState: ObservableObject {
    @Published var barcodes: [String] = []
    private var scannedPath: String?
    private var scanTask: Task<Void, Never>?

    func scanIfNeeded(url: URL) {
        let path = url.path
        guard scannedPath != path else { return }
        scannedPath = path; barcodes = []; scanTask?.cancel()
        scanTask = Task {
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0, size < 15_000_000 else { return }
            let detected = await Task.detached(priority: .utility) {
                (try? VisionService.analyzeTextAndBarcodes(at: url).barcodes) ?? []
            }.value
            guard !Task.isCancelled, self.scannedPath == path else { return }
            self.barcodes = detected
        }
    }

    func cancel() { scanTask?.cancel(); scanTask = nil }
}

@MainActor
private final class TextLensModeState: ObservableObject {
    @Published var showQRCode: Bool = false
}

struct ColorSwatchLensCard: View {
    let hex: String; let clip: ClipboardEntry
    let onCopyText: (String, String) -> Void; let onCopyClipboard: () -> Void; let onTogglePin: () -> Void

    var body: some View {
        let swatch = LiquidColors.color(fromHex: hex) ?? .accentColor
        let rgb = LiquidColors.rgbComponents(fromHex: hex)
        let shape = RoundedRectangle(cornerRadius: LiquidRadii.card, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                shape.fill(swatch)
                    .overlay { shape.fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .topLeading, endPoint: .center)) }
                    .overlay { shape.strokeBorder(.white.opacity(0.45), lineWidth: 1.0) }
                    .shadow(color: swatch.opacity(0.32), radius: 12, y: 5)
                HStack(spacing: 6) {
                    Circle().fill(swatch).frame(width: 10, height: 10).overlay { Circle().strokeBorder(.white.opacity(0.75), lineWidth: 0.8) }
                    Text(hex).font(.callout.monospaced().weight(.bold)).foregroundStyle(LiquidColors.textPrimary)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background {
                    Capsule(style: .continuous).fill(.ultraThinMaterial)
                    Capsule(style: .continuous).fill(LiquidColors.elevatedSurface)
                }
                .overlay { Capsule(style: .continuous).strokeBorder(.white.opacity(0.42), lineWidth: 0.75) }
                .padding(10)
            }
            .frame(height: 146)

            VStack(spacing: 6) {
                colorRow("HEX", hex) { onCopyText(hex, "已复制 HEX：\(hex)") }
                if let rgb {
                    let rgbText = "rgb(\(rgb.r), \(rgb.g), \(rgb.b))"
                    colorRow("RGB", rgbText) { onCopyText(rgbText, "已复制 \(rgbText)") }
                }
            }
            .padding(10).liquidGlassCard(cornerRadius: LiquidRadii.row, solidReadable: true)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Button("复制粘贴板", action: onCopyClipboard).buttonStyle(GlassPillButtonStyle(prominent: true))
                Button(clip.isPinned ? "取消收藏" : "收藏", action: onTogglePin).buttonStyle(GlassPillButtonStyle())
            }
        }
    }

    private func colorRow(_ label: String, _ value: String, onCopy: @escaping () -> Void) -> some View {
        HStack {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary).frame(width: 32, alignment: .leading)
            Text(value).font(.caption.monospaced().weight(.medium)).foregroundStyle(LiquidColors.textPrimary).textSelection(.enabled)
            Spacer()
            Button("复制", action: onCopy).buttonStyle(GlassPillButtonStyle())
        }
    }
}

struct ImageClipboardLensCard: View {
    let url: URL; let dimensions: CGSize; let clip: ClipboardEntry
    let onCopyImage: () -> Void; let onPinOverlay: () -> Void; let onOpenViewer: () -> Void
    let onTogglePin: () -> Void; let onCopyText: (String, String) -> Void
    @StateObject private var qrState = ImageQRScannerState()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                if let img = NSImage(contentsOf: url) {
                    Image(nsImage: img).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    Text("无法读取图片").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if dimensions.width > 0 && dimensions.height > 0 {
                    Text("\(Int(dimensions.width)) × \(Int(dimensions.height))").font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.black.opacity(0.56), in: Capsule(style: .continuous)).padding(8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 168, maxHeight: 215, alignment: .center)
            .background(Color.black.opacity(0.10), in: RoundedRectangle(cornerRadius: LiquidRadii.card, style: .continuous))
            .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)

            if let firstCode = qrState.barcodes.first {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder").font(.callout).foregroundStyle(.cyan)
                    Text(firstCode).font(.caption2.monospaced()).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
                    Spacer(minLength: 4)
                    if let parsedURL = URL(string: firstCode), ["http", "https"].contains(parsedURL.scheme?.lowercased() ?? "") {
                        Button("打开") { NSWorkspace.shared.open(parsedURL) }.buttonStyle(GlassPillButtonStyle())
                    }
                    Button("复制") { onCopyText(firstCode, "已复制二维码内容") }.buttonStyle(GlassPillButtonStyle())
                }
                .padding(.horizontal, 10).padding(.vertical, 7).liquidGlassCard(cornerRadius: LiquidRadii.row, solidReadable: true)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button { onCopyImage() } label: { Label("复制图片", systemImage: "doc.on.doc") }.buttonStyle(GlassPillButtonStyle(prominent: true))
                    Button { onPinOverlay() } label: { Label("贴图置顶", systemImage: "pin.fill") }.buttonStyle(GlassPillButtonStyle())
                }
                HStack(spacing: 6) {
                    Button("看图置顶", action: onOpenViewer).buttonStyle(GlassPillButtonStyle())
                    Button(clip.isPinned ? "取消收藏" : "收藏", action: onTogglePin).buttonStyle(GlassPillButtonStyle())
                }
            }
        }
        .onAppear { qrState.scanIfNeeded(url: url) }
        .onChange(of: url) { _, newURL in qrState.scanIfNeeded(url: newURL) }
        .onDisappear { qrState.cancel() }
    }
}

struct TextClipboardLensCard: View {
    let clip: ClipboardEntry; let onCopyClipboard: () -> Void; let onTogglePin: () -> Void
    @StateObject private var mode = TextLensModeState()

    var body: some View {
        let payload = clip.textValue ?? clip.fileURL?.path ?? clip.title
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                LiquidStatusPill(title: clip.payloadKind.badgeTitle, symbol: "doc.text.fill", tint: .cyan)
                LiquidStatusPill(title: "\(payload.count) 字符", tint: .indigo)
                Spacer()
                if !payload.isEmpty && payload.count <= 280 {
                    Button(mode.showQRCode ? "文本" : "二维码") { mode.showQRCode.toggle() }.buttonStyle(GlassPillButtonStyle())
                }
            }
            if mode.showQRCode, let qrImage = Self.makeQRImage(from: payload) {
                ZStack {
                    RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous).fill(Color.white)
                        .frame(width: 176, height: 176).shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                    Image(nsImage: qrImage).interpolation(.none).resizable().frame(width: 150, height: 150)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
            } else {
                ScrollView {
                    Text(payload).font(.system(.caption, design: .monospaced)).foregroundStyle(LiquidColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .padding(12).liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
            }
            HStack(spacing: 6) {
                Button("复制粘贴板", action: onCopyClipboard).buttonStyle(GlassPillButtonStyle(prominent: true))
                Button(clip.isPinned ? "取消收藏" : "收藏", action: onTogglePin).buttonStyle(GlassPillButtonStyle())
                if let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
                   ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    Button("打开链接") { NSWorkspace.shared.open(url) }.buttonStyle(GlassPillButtonStyle())
                }
            }
        }
    }

    private static func makeQRImage(from text: String) -> NSImage? {
        guard let data = text.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator(); filter.message = data; filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let rep = NSCIImageRep(ciImage: output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)))
        let img = NSImage(size: rep.size); img.addRepresentation(rep); return img
    }
}

struct CalculatorLensCard: View {
    let expression: String; let resultText: String; let badge: String; let onCopy: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack { LiquidStatusPill(title: badge, symbol: "equal.circle.fill", tint: .cyan); Spacer(); LiquidKeyHintBadge(keyText: "↩ 复制", highlighted: true) }
            Spacer(minLength: 4)
            Text(resultText).font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(LiquidColors.textPrimary).multilineTextAlignment(.center).lineLimit(2)
                .minimumScaleFactor(0.55).textSelection(.enabled).padding(.horizontal, 8)
            LiquidSectionDivider()
            Text(expression).font(.caption.monospaced()).foregroundStyle(LiquidColors.textSecondary).lineLimit(2).multilineTextAlignment(.center)
            Spacer(minLength: 4)
            Button("复制结果 ↩", action: onCopy).buttonStyle(GlassPillButtonStyle(prominent: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(14)
        .background {
            RadialGradient(colors: [Color.cyan.opacity(0.11), .clear], center: .center, startRadius: 8, endRadius: 180)
                .clipShape(RoundedRectangle(cornerRadius: LiquidRadii.card, style: .continuous))
        }
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }
}

struct InlineOutputLensCard: View {
    let title: String; let outputText: String; let onCopy: () -> Void; let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SquircleBadge(symbol: "terminal.fill", topColor: .cyan, bottomColor: .indigo, size: 26)
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
                Spacer()
                Button("复制", action: onCopy).buttonStyle(GlassPillButtonStyle())
                Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(GlassPillButtonStyle())
            }
            LiquidSectionDivider()
            ScrollView {
                Text(outputText).font(.system(.caption, design: .monospaced)).foregroundStyle(LiquidColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .padding(10).liquidGlassCard(cornerRadius: LiquidRadii.row, solidReadable: true)
        }
    }
}
