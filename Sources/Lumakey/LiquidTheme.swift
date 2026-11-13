import AppKit
import SwiftUI

enum LiquidRadii {
    static let panel: CGFloat = 28
    static let windowPanel: CGFloat = 24
    static let bento: CGFloat = 22
    static let searchBar: CGFloat = 20
    static let card: CGFloat = 18
    static let row: CGFloat = 13
    static let control: CGFloat = 12
}

enum LiquidColors {
    static let primaryNSColor = dynamicColor(
        name: "LumaTextPrimary",
        light: NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0),
        dark: NSColor(srgbRed: 0.97, green: 0.98, blue: 1.0, alpha: 1.0)
    )

    static let secondaryNSColor = dynamicColor(
        name: "LumaTextSecondary",
        light: NSColor(srgbRed: 0.20, green: 0.25, blue: 0.34, alpha: 1.0),
        dark: NSColor(srgbRed: 0.80, green: 0.84, blue: 0.91, alpha: 1.0)
    )

    static let placeholderNSColor = dynamicColor(
        name: "LumaTextPlaceholder",
        light: NSColor(srgbRed: 0.27, green: 0.33, blue: 0.43, alpha: 0.90),
        dark: NSColor(srgbRed: 0.76, green: 0.82, blue: 0.90, alpha: 0.82)
    )

    static let textPrimary = Color(nsColor: primaryNSColor)
    static let textSecondary = Color(nsColor: secondaryNSColor)

    static let canvasBase = Color(nsColor: dynamicColor(
        name: "LumaCanvasBase",
        light: NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.99, alpha: 1),
        dark: NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.13, alpha: 1)
    ))

    static let solidCardSurface = Color(nsColor: dynamicColor(
        name: "LumaSolidSurface",
        light: NSColor(calibratedWhite: 1.0, alpha: 0.92),
        dark: NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.20, alpha: 0.90)
    ))

    static let shellTint = Color(nsColor: dynamicColor(
        name: "LumaShellTint",
        light: NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 0.56),
        dark: NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.15, alpha: 0.48)
    ))

    static let cardSurface = Color(nsColor: dynamicColor(
        name: "LumaCardSurface",
        light: NSColor(calibratedWhite: 1.0, alpha: 0.52),
        dark: NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.22, alpha: 0.42)
    ))

    static let inputFieldSurface = Color(nsColor: dynamicColor(
        name: "LumaInputFieldSurface",
        light: NSColor(calibratedWhite: 1.0, alpha: 0.66),
        dark: NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.18, alpha: 0.58)
    ))

    static let inputFieldBorder = Color(nsColor: dynamicColor(
        name: "LumaInputFieldBorder",
        light: NSColor.black.withAlphaComponent(0.15),
        dark: NSColor.white.withAlphaComponent(0.24)
    ))

    static let pillSurface = Color(nsColor: dynamicColor(
        name: "LumaPillSurface",
        light: NSColor.black.withAlphaComponent(0.065),
        dark: NSColor.white.withAlphaComponent(0.11)
    ))

    static let pillBorder = Color(nsColor: dynamicColor(
        name: "LumaPillBorder",
        light: NSColor.black.withAlphaComponent(0.14),
        dark: NSColor.white.withAlphaComponent(0.22)
    ))

    static let subtleRim = Color(nsColor: dynamicColor(
        name: "LumaSubtleRim",
        light: NSColor.black.withAlphaComponent(0.10),
        dark: NSColor.white.withAlphaComponent(0.18)
    ))

    static let highlightGlow = Color(nsColor: dynamicColor(
        name: "LumaHighlightGlow",
        light: NSColor.systemBlue.withAlphaComponent(0.14),
        dark: NSColor.systemCyan.withAlphaComponent(0.22)
    ))

    static let specularRimGradient = LinearGradient(
        colors: [.white.opacity(0.55), .white.opacity(0.10), .white.opacity(0.28)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let softCardRimGradient = LinearGradient(
        colors: [.white.opacity(0.36), .white.opacity(0.06), .white.opacity(0.18)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func dynamicColor(name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name(name)) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    static func color(fromHex hex: String) -> Color? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        return Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255.0, green: Double((value >> 8) & 0xFF) / 255.0, blue: Double(value & 0xFF) / 255.0, opacity: 1.0)
    }
}

struct FrostedWindowVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material { nsView.material = material }
        nsView.state = .active
    }
}

struct LiquidFluidBackdrop: View {
    var body: some View {
        ZStack {
            FrostedWindowVisualEffectView().ignoresSafeArea()
            LiquidColors.canvasBase.opacity(0.46)
            RadialGradient(colors: [Color.cyan.opacity(0.16), Color.clear], center: .topLeading, startRadius: 20, endRadius: 560)
            RadialGradient(colors: [Color.indigo.opacity(0.13), Color.clear], center: .bottomTrailing, startRadius: 30, endRadius: 620)
        }
        .ignoresSafeArea()
    }
}

struct LiquidGlassShellModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                ZStack {
                    if !reduceTransparency { shape.fill(.ultraThinMaterial) }
                    shape.fill(reduceTransparency ? LiquidColors.solidCardSurface : LiquidColors.shellTint)
                    RadialGradient(colors: [Color.cyan.opacity(0.10), Color.clear], center: .topLeading, startRadius: 10, endRadius: 360)
                    RadialGradient(colors: [Color.indigo.opacity(0.08), Color.clear], center: .topTrailing, startRadius: 10, endRadius: 340)
                }
            }
            .clipShape(shape)
            .overlay {
                if highContrast {
                    shape.strokeBorder(LiquidColors.subtleRim, lineWidth: 1.5)
                } else {
                    shape.strokeBorder(LiquidColors.specularRimGradient, lineWidth: 1.1)
                }
            }
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

struct LiquidGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let solidReadable: Bool

    func body(content: Content) -> some View {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                ZStack {
                    if !reduceTransparency {
                        shape.fill(solidReadable ? .regularMaterial : .ultraThinMaterial)
                    }
                    shape.fill(reduceTransparency ? LiquidColors.solidCardSurface : LiquidColors.cardSurface)
                }
            }
            .clipShape(shape)
            .overlay {
                if highContrast {
                    shape.strokeBorder(LiquidColors.subtleRim, lineWidth: 1.4)
                } else {
                    shape.strokeBorder(LiquidColors.softCardRimGradient, lineWidth: 0.95)
                }
            }
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}

struct SquircleBadge: View {
    let symbol: String
    let topColor: Color
    let bottomColor: Color
    var size: CGFloat = 38

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [topColor, bottomColor], startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.fill(LinearGradient(colors: [.white.opacity(0.36), .white.opacity(0.0)], startPoint: .top, endPoint: .center))
            Image(systemName: symbol).font(.system(size: size * 0.43, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay { shape.strokeBorder(.white.opacity(0.45), lineWidth: 0.95) }
        .shadow(color: bottomColor.opacity(0.24), radius: 6, y: 3)
    }
}

struct GlassPillButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : LiquidColors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if prominent {
                    Capsule(style: .continuous).fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    Capsule(style: .continuous).fill(LiquidColors.pillSurface)
                }
            }
            .overlay {
                Capsule(style: .continuous).strokeBorder(prominent ? Color.white.opacity(0.35) : LiquidColors.pillBorder, lineWidth: 0.9)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct KeycapPill: View {
    let title: String
    let keyText: String
    var prominent: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(prominent ? LiquidColors.textPrimary : LiquidColors.textSecondary)
            Text(keyText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(prominent ? Color.white : LiquidColors.textPrimary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background {
                    if prominent { Capsule(style: .continuous).fill(Color.accentColor) }
                    else { Capsule(style: .continuous).fill(LiquidColors.pillSurface) }
                }
                .overlay {
                    Capsule(style: .continuous).strokeBorder(prominent ? Color.white.opacity(0.25) : LiquidColors.pillBorder, lineWidth: 0.7)
                }
        }
    }
}

extension View {
    func liquidGlassShell(cornerRadius: CGFloat = LiquidRadii.panel) -> some View {
        modifier(LiquidGlassShellModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassCard(cornerRadius: CGFloat = LiquidRadii.card, solidReadable: Bool = false) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, solidReadable: solidReadable))
    }
}
