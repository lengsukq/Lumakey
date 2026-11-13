import SwiftUI

struct SecondaryWindowScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let pinWindowKey: String?
    private let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        symbol: String,
        pinWindowKey: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.pinWindowKey = pinWindowKey
        self.content = content
    }

    var body: some View {
        ZStack {
            LiquidFluidBackdrop()
            content()
                .padding(.top, 8)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .overlay(alignment: .top) {
            ZStack {
                titlebarBadgeStrip
                    .allowsHitTesting(false)
                if let pinWindowKey {
                    HStack {
                        Spacer()
                        WindowPinPillButton(key: pinWindowKey)
                    }
                    .padding(.trailing, 14)
                }
            }
            .frame(height: 30)
            .padding(.top, 3)
            .ignoresSafeArea(.container, edges: .top)
        }
    }

    private var titlebarBadgeStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.cyan)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LiquidColors.textPrimary)
            if let subtitle, !subtitle.isEmpty {
                Text("·")
                    .foregroundStyle(LiquidColors.textSecondary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7)
        }
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

    init(
        symbol: String,
        topColor: Color,
        bottomColor: Color,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.symbol = symbol
        self.topColor = topColor
        self.bottomColor = bottomColor
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SquircleBadge(symbol: symbol, topColor: topColor, bottomColor: bottomColor, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(LiquidColors.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }
}

extension SettingsSectionHeroHeader where Trailing == EmptyView {
    init(
        symbol: String,
        topColor: Color,
        bottomColor: Color,
        title: String,
        subtitle: String
    ) {
        self.init(
            symbol: symbol,
            topColor: topColor,
            bottomColor: bottomColor,
            title: title,
            subtitle: subtitle
        ) { EmptyView() }
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
            SquircleBadge(symbol: symbol, topColor: topColor, bottomColor: bottomColor, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LiquidColors.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 10)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .liquidGlassCard(cornerRadius: LiquidRadii.card)
    }
}

struct GlassInputField: View {
    let symbol: String?
    let placeholder: String
    @Binding var text: String

    init(symbol: String? = nil, placeholder: String, text: Binding<String>) {
        self.symbol = symbol
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        HStack(spacing: 7) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundStyle(LiquidColors.textPrimary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(LiquidColors.inputFieldSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                .strokeBorder(LiquidColors.inputFieldBorder, lineWidth: 0.9)
        }
    }
}
