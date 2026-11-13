import AppKit
import LumakeyCore
import SwiftUI

enum LiquidRadii {
    static let panel: CGFloat = 28
    static let windowPanel: CGFloat = 24
    static let bento: CGFloat = 22
    static let searchBar: CGFloat = 22
    static let card: CGFloat = 18
    static let row: CGFloat = 14
    static let control: CGFloat = 12
    static let pill: CGFloat = 10
}

enum LiquidMotion {
    static let pressSpring = Animation.spring(response: 0.24, dampingFraction: 0.76)
}

enum LiquidColors {
    static let primaryNSColor = dynamicColor(
        name: "LumaTextPrimary",
        light: NSColor(srgbRed: 0.05, green: 0.08, blue: 0.15, alpha: 1.0),
        dark: NSColor(srgbRed: 0.97, green: 0.985, blue: 1.0, alpha: 1.0)
    )
    static let secondaryNSColor = dynamicColor(
        name: "LumaTextSecondary",
        light: NSColor(srgbRed: 0.19, green: 0.24, blue: 0.34, alpha: 0.96),
        dark: NSColor(srgbRed: 0.79, green: 0.84, blue: 0.92, alpha: 0.95)
    )
    static let placeholderNSColor = dynamicColor(
        name: "LumaTextPlaceholder",
        light: NSColor(srgbRed: 0.25, green: 0.31, blue: 0.41, alpha: 0.86),
        dark: NSColor(srgbRed: 0.76, green: 0.82, blue: 0.91, alpha: 0.78)
    )

    static let textPrimary = Color(nsColor: primaryNSColor)
    static let textSecondary = Color(nsColor: secondaryNSColor)
    static let textTertiary = textSecondary.opacity(0.72)

    static let canvasBase = Color(nsColor: dynamicColor(
        name: "LumaCanvasBase",
        light: NSColor(calibratedRed: 0.94, green: 0.965, blue: 0.995, alpha: 1),
        dark: NSColor(calibratedRed: 0.065, green: 0.08, blue: 0.12, alpha: 1)
    ))
    static let solidCardSurface = Color(nsColor: dynamicColor(
        name: "LumaSolidSurface",
        light: NSColor(calibratedRed: 0.965, green: 0.975, blue: 0.995, alpha: 0.96),
        dark: NSColor(calibratedRed: 0.125, green: 0.145, blue: 0.195, alpha: 0.95)
    ))
    static let shellTint = Color(nsColor: dynamicColor(
        name: "LumaShellTint",
        light: NSColor(calibratedRed: 0.97, green: 0.985, blue: 1.0, alpha: 0.60),
        dark: NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.14, alpha: 0.50)
    ))
    static let cardSurface = Color(nsColor: dynamicColor(
        name: "LumaCardSurface",
        light: NSColor(calibratedWhite: 1.0, alpha: 0.56),
        dark: NSColor(calibratedRed: 0.13, green: 0.155, blue: 0.215, alpha: 0.44)
    ))
    static let elevatedSurface = Color(nsColor: dynamicColor(
        name: "LumaElevatedSurface",
        light: NSColor(calibratedWhite: 1.0, alpha: 0.72),
        dark: NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.26, alpha: 0.56)
    ))
    static let inputFieldSurface = Color(nsColor: dynamicColor(
        name: "LumaInputFieldSurface",
        light: NSColor(calibratedWhite: 1.0, alpha: 0.72),
        dark: NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.18, alpha: 0.62)
    ))
    static let inputFieldBorder = Color(nsColor: dynamicColor(
        name: "LumaInputFieldBorder",
        light: NSColor.black.withAlphaComponent(0.13),
        dark: NSColor.white.withAlphaComponent(0.24)
    ))
    static let pillSurface = Color(nsColor: dynamicColor(
        name: "LumaPillSurface",
        light: NSColor.black.withAlphaComponent(0.058),
        dark: NSColor.white.withAlphaComponent(0.115)
    ))
    static let pillBorder = Color(nsColor: dynamicColor(
        name: "LumaPillBorder",
        light: NSColor.black.withAlphaComponent(0.12),
        dark: NSColor.white.withAlphaComponent(0.22)
    ))
    static let subtleRim = Color(nsColor: dynamicColor(
        name: "LumaSubtleRim",
        light: NSColor.black.withAlphaComponent(0.11),
        dark: NSColor.white.withAlphaComponent(0.20)
    ))
    static let highlightGlow = Color(nsColor: dynamicColor(
        name: "LumaHighlightGlow",
        light: NSColor.systemBlue.withAlphaComponent(0.14),
        dark: NSColor.systemCyan.withAlphaComponent(0.22)
    ))
    static let selectedRowFill = Color(nsColor: dynamicColor(
        name: "LumaSelectedRowFill",
        light: NSColor(calibratedRed: 0.89, green: 0.955, blue: 1.0, alpha: 0.78),
        dark: NSColor(calibratedRed: 0.14, green: 0.32, blue: 0.45, alpha: 0.36)
    ))

    static let specularRimGradient = LinearGradient(
        stops: [.init(color: .white.opacity(0.72), location: 0.0), .init(color: .white.opacity(0.14), location: 0.46), .init(color: .white.opacity(0.32), location: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let innerSpecularGradient = LinearGradient(
        colors: [.white.opacity(0.34), .cyan.opacity(0.14), .white.opacity(0.08)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let softCardRimGradient = LinearGradient(
        stops: [.init(color: .white.opacity(0.52), location: 0.0), .init(color: .white.opacity(0.08), location: 0.48), .init(color: .white.opacity(0.22), location: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let selectedRowRimGradient = LinearGradient(
        colors: [.white.opacity(0.68), .cyan.opacity(0.42), .blue.opacity(0.28)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.08, green: 0.78, blue: 0.96), Color(red: 0.12, green: 0.50, blue: 0.98)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static func dynamicColor(name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name(name)) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    static func color(fromHex hex: String) -> Color? {
        guard let c = rgbComponents(fromHex: hex) else { return nil }
        return Color(.sRGB, red: Double(c.r) / 255.0, green: Double(c.g) / 255.0, blue: Double(c.b) / 255.0, opacity: 1.0)
    }

    static func rgbComponents(fromHex hex: String) -> (r: Int, g: Int, b: Int, luminance: Double)? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Int((value >> 16) & 0xFF), g = Int((value >> 8) & 0xFF), b = Int(value & 0xFF)
        let lum = (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
        return (r, g, b, lum)
    }
}

struct FrostedWindowVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material; view.blendingMode = .behindWindow; view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material { nsView.material = material }
        nsView.state = .active
    }
}

struct LiquidFluidBackdrop: View {
    var body: some View {
        let reduceTransparency = SystemDisplayPreferences.shared.reduceTransparency
        ZStack {
            if !reduceTransparency { FrostedWindowVisualEffectView().ignoresSafeArea() }
            LiquidColors.canvasBase.opacity(reduceTransparency ? 1.0 : 0.44)
            if !reduceTransparency {
                RadialGradient(colors: [Color.cyan.opacity(0.15), .clear], center: .topLeading, startRadius: 20, endRadius: 560)
                RadialGradient(colors: [Color.mint.opacity(0.08), .clear], center: .topTrailing, startRadius: 24, endRadius: 440)
                RadialGradient(colors: [Color.indigo.opacity(0.13), .clear], center: .bottomTrailing, startRadius: 30, endRadius: 620)
            }
        }
        .ignoresSafeArea()
    }
}

struct LiquidGlassShellModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let prefs = SystemDisplayPreferences.shared.snapshot
        let reduceTransparency = prefs.reduceTransparency
        let highContrast = prefs.increaseContrast
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    if !reduceTransparency { shape.fill(.ultraThinMaterial) }
                    shape.fill(reduceTransparency ? LiquidColors.solidCardSurface : LiquidColors.shellTint)
                    if !reduceTransparency {
                        RadialGradient(colors: [Color.cyan.opacity(0.11), .clear], center: .topLeading, startRadius: 8, endRadius: 380)
                        RadialGradient(colors: [Color.indigo.opacity(0.08), .clear], center: .topTrailing, startRadius: 10, endRadius: 350)
                        LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
                    }
                }
            }
            .clipShape(shape)
            .overlay { DoubleSpecularBorder(cornerRadius: cornerRadius, isShell: true, highContrast: highContrast) }
    }
}

struct LiquidGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let solidReadable: Bool

    func body(content: Content) -> some View {
        let prefs = SystemDisplayPreferences.shared.snapshot
        let reduceTransparency = prefs.reduceTransparency
        let highContrast = prefs.increaseContrast
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    if !reduceTransparency { shape.fill(solidReadable ? .regularMaterial : .ultraThinMaterial) }
                    shape.fill(reduceTransparency ? LiquidColors.solidCardSurface : (solidReadable ? LiquidColors.elevatedSurface : LiquidColors.cardSurface))
                    if !reduceTransparency { LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .center) }
                }
            }
            .clipShape(shape)
            .overlay { DoubleSpecularBorder(cornerRadius: cornerRadius, isShell: false, highContrast: highContrast) }
            .shadow(color: .black.opacity(reduceTransparency ? 0.08 : 0.055), radius: 10, y: 4)
    }
}

final class DragRegionNSView: NSView {
    var onDoubleClick: (() -> Void)?
    override var intrinsicContentSize: NSSize { NSSize(width: 1, height: 1) }
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let onDoubleClick { onDoubleClick(); return }
        window?.performDrag(with: event)
    }
}

struct WindowDragRegion: NSViewRepresentable {
    var onDoubleClick: (() -> Void)? = nil
    func makeNSView(context: Context) -> DragRegionNSView { let v = DragRegionNSView(); v.onDoubleClick = onDoubleClick; return v }
    func updateNSView(_ nsView: DragRegionNSView, context: Context) { nsView.onDoubleClick = onDoubleClick }
}

extension View {
    func liquidGlassShell(cornerRadius: CGFloat = LiquidRadii.panel) -> some View {
        modifier(LiquidGlassShellModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassCard(cornerRadius: CGFloat = LiquidRadii.card, solidReadable: Bool = false) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, solidReadable: solidReadable))
    }
}
