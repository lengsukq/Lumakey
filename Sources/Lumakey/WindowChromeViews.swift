import AppKit
import SwiftUI

struct SecondaryWindowScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let pinWindowKey: String?
    private let content: () -> Content

    init(title: String, subtitle: String? = nil, symbol: String, pinWindowKey: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.subtitle = subtitle; self.symbol = symbol; self.pinWindowKey = pinWindowKey; self.content = content
    }

    var body: some View {
        ZStack {
            LiquidFluidBackdrop()
            content().padding(.top, 10).padding(.horizontal, 16).padding(.bottom, 16)
        }
        .overlay(alignment: .top) {
            ZStack {
                WindowDragRegion()
                titlebarBadgeStrip.allowsHitTesting(false)
                if let pinWindowKey {
                    HStack {
                        Spacer()
                        WindowPinPillButton(key: pinWindowKey).shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    }
                    .padding(.trailing, 14)
                }
            }
            .frame(height: 32).padding(.top, 3).ignoresSafeArea(.container, edges: .top)
        }
    }

    private var titlebarBadgeStrip: some View {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        return HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.cyan)
                .frame(width: 20, height: 20).background(Color.cyan.opacity(0.14), in: Circle())
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(LiquidColors.textPrimary)
            if let subtitle, !subtitle.isEmpty {
                Text("·").foregroundStyle(LiquidColors.textSecondary)
                Text(subtitle).font(.system(size: 11, weight: .medium)).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
            }
        }
        .padding(.leading, 5).padding(.trailing, 12).padding(.vertical, 3.5)
        .background {
            ZStack {
                if !reduceTransparency { Capsule(style: .continuous).fill(.ultraThinMaterial) }
                Capsule(style: .continuous).fill(reduceTransparency ? LiquidColors.solidCardSurface : LiquidColors.elevatedSurface)
            }
        }
        .overlay { Capsule(style: .continuous).strokeBorder(LiquidColors.softCardRimGradient, lineWidth: 0.9) }
        .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
        .frame(height: 28, alignment: .center)
    }
}

struct SettingsSectionHeroHeader<Trailing: View>: View {
    let symbol: String
    let topColor: Color
    let bottomColor: Color
    let title: String
    let subtitle: String
    private let trailing: () -> Trailing

    init(symbol: String, topColor: Color, bottomColor: Color, title: String, subtitle: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.symbol = symbol; self.topColor = topColor; self.bottomColor = bottomColor
        self.title = title; self.subtitle = subtitle; self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            SquircleBadge(symbol: symbol, topColor: topColor, bottomColor: bottomColor, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.bold)).foregroundStyle(LiquidColors.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(LiquidColors.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            trailing()
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RadialGradient(colors: [topColor.opacity(0.10), .clear], center: .topLeading, startRadius: 8, endRadius: 280)
                .clipShape(RoundedRectangle(cornerRadius: LiquidRadii.bento, style: .continuous))
        }
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }
}

extension SettingsSectionHeroHeader where Trailing == EmptyView {
    init(symbol: String, topColor: Color, bottomColor: Color, title: String, subtitle: String) {
        self.init(symbol: symbol, topColor: topColor, bottomColor: bottomColor, title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct SettingsToggleCardRow: View {
    let symbol: String
    let topColor: Color
    let bottomColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SquircleBadge(symbol: symbol, topColor: topColor, bottomColor: bottomColor, size: 38)
            VStack(alignment: .leading, spacing: 2.5) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary)
                Text(subtitle).font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 10)
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().tint(.cyan)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background {
            if isOn {
                RoundedRectangle(cornerRadius: LiquidRadii.card, style: .continuous)
                    .fill(RadialGradient(colors: [topColor.opacity(0.08), .clear], center: .leading, startRadius: 6, endRadius: 240))
            }
        }
        .liquidGlassCard(cornerRadius: LiquidRadii.card)
    }
}

struct GlassInputField: View {
    let symbol: String?
    let placeholder: String
    @Binding var text: String

    init(symbol: String? = nil, placeholder: String, text: Binding<String>) {
        self.symbol = symbol; self.placeholder = placeholder; self._text = text
    }

    var body: some View {
        let shape = Capsule(style: .continuous)
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(LiquidColors.textSecondary)
                    .frame(width: 22, height: 22).background(LiquidColors.pillSurface, in: Circle())
            }
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(LiquidColors.textPrimary)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(LiquidColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, symbol == nil ? 13 : 7).padding(.trailing, 11).padding(.vertical, 6.5)
        .background {
            ZStack {
                if !reduceTransparency { shape.fill(.ultraThinMaterial) }
                shape.fill(reduceTransparency ? LiquidColors.solidCardSurface : LiquidColors.inputFieldSurface)
            }
        }
        .overlay { shape.strokeBorder(LiquidColors.inputFieldBorder, lineWidth: 0.95) }
        .overlay { shape.strokeBorder(LiquidColors.innerSpecularGradient, lineWidth: 0.6).padding(1) }
    }
}
