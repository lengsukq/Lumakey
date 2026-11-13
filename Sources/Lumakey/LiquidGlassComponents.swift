import AppKit
import SwiftUI

struct DoubleSpecularBorder: View {
    let cornerRadius: CGFloat
    var isShell: Bool = false
    var highContrast: Bool = false

    var body: some View {
        let outer = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let innerRadius = max(0, cornerRadius - 1.1)
        let inner = RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
        ZStack {
            if highContrast {
                outer.strokeBorder(LiquidColors.subtleRim, lineWidth: isShell ? 1.5 : 1.35)
            } else {
                outer.strokeBorder(
                    isShell ? LiquidColors.specularRimGradient : LiquidColors.softCardRimGradient,
                    lineWidth: isShell ? 1.1 : 0.95
                )
                inner.strokeBorder(LiquidColors.innerSpecularGradient, lineWidth: 0.65)
                    .padding(1.0)
            }
        }
        .allowsHitTesting(false)
    }
}

struct SquircleBadge: View {
    let symbol: String
    let topColor: Color
    let bottomColor: Color
    var size: CGFloat = 38

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [topColor, bottomColor], startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.0)], startPoint: .top, endPoint: .center))
            Image(systemName: symbol)
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .overlay {
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.62), .white.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.95
            )
        }
        .shadow(color: bottomColor.opacity(0.24), radius: 6, y: 3)
    }
}

struct GlassPillButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : LiquidColors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if prominent {
                    Capsule(style: .continuous)
                        .fill(LiquidColors.accentGradient)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                        }
                } else {
                    Capsule(style: .continuous)
                        .fill(LiquidColors.pillSurface)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.04))
                        }
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        prominent
                            ? LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.16)], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(
                                colors: [highContrast ? LiquidColors.subtleRim : LiquidColors.pillBorder, LiquidColors.pillBorder.opacity(0.65)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                        lineWidth: highContrast ? 1.15 : 0.9
                    )
            }
            .shadow(color: prominent ? Color.cyan.opacity(0.22) : .clear, radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.90 : 1.0)
            .animation(LiquidMotion.pressSpring, value: configuration.isPressed)
    }
}

struct LiquidBentoTileStyle: ButtonStyle {
    var cornerRadius: CGFloat = LiquidRadii.bento

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.0))
                    .allowsHitTesting(false)
            }
            .scaleEffect(configuration.isPressed ? 0.972 : 1.0)
            .animation(LiquidMotion.pressSpring, value: configuration.isPressed)
    }
}

struct KeycapPill: View {
    let title: String
    let keyText: String
    var prominent: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(prominent ? LiquidColors.textPrimary : LiquidColors.textSecondary)
            Text(keyText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(prominent ? Color.white : LiquidColors.textPrimary)
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2.5)
                .background {
                    if prominent {
                        Capsule(style: .continuous).fill(LiquidColors.accentGradient)
                    } else {
                        Capsule(style: .continuous).fill(LiquidColors.pillSurface)
                    }
                }
                .overlay {
                    Capsule(style: .continuous).strokeBorder(
                        prominent ? Color.white.opacity(0.35) : LiquidColors.pillBorder,
                        lineWidth: 0.75
                    )
                }
        }
    }
}

struct LiquidKeyHintBadge: View {
    let keyText: String
    var highlighted: Bool = false

    var body: some View {
        Text(keyText)
            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(highlighted ? LiquidColors.textPrimary : LiquidColors.textSecondary.opacity(0.88))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                highlighted ? LiquidColors.elevatedSurface : LiquidColors.pillSurface.opacity(0.75),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(highlighted ? Color.white.opacity(0.45) : LiquidColors.pillBorder.opacity(0.75), lineWidth: 0.7)
            }
    }
}

struct LiquidSectionDivider: View {
    enum Axis { case horizontal, vertical }
    var axis: Axis = .horizontal

    var body: some View {
        if axis == .horizontal {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, LiquidColors.subtleRim.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.8)
        } else {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, LiquidColors.subtleRim.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: 0.8)
        }
    }
}

struct LiquidStatusPill: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = .cyan
    var showDot: Bool = false
    var prominent: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if showDot {
                Circle().fill(tint).frame(width: 6, height: 6)
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(prominent ? .white : tint)
            }
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(prominent ? Color.white : LiquidColors.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8.5)
        .padding(.vertical, 3.5)
        .background {
            if prominent {
                Capsule(style: .continuous).fill(LiquidColors.accentGradient)
            } else {
                Capsule(style: .continuous).fill(tint.opacity(0.11))
            }
        }
        .overlay {
            Capsule(style: .continuous).strokeBorder(prominent ? Color.white.opacity(0.35) : tint.opacity(0.28), lineWidth: 0.75)
        }
    }
}
