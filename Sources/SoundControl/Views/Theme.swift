import AppKit
import SwiftUI
import SoundControlCore

enum Theme {
    /// Brand purple (#9670FF): sound icons, audio actions, active toggles and the selected pack.
    static let accent = Color(red: 0.588, green: 0.439, blue: 1.0)
    static let accentSoft = accent.opacity(0.16)
    static let warning = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let success = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let danger = Color(red: 1.0, green: 0.27, blue: 0.23)
    /// Grouped sections in the popover: a faint fill and a hairline, no heavy cards.
    static let groupFill = Color.primary.opacity(0.045)
    static let hairline = Color.primary.opacity(0.08)
    static let groupRadius: CGFloat = 10
    static let rowIconWidth: CGFloat = 18
    /// Status dot of a Claude session that is working.
    static let working = Color(red: 0.2, green: 0.85, blue: 0.4)
    static let cardRadius: CGFloat = 12
    static let tileSize: CGFloat = 32
}

/// Rounded square holding a trigger or pack symbol.
struct SymbolTile: View {
    let symbol: String
    var isActive = true
    var size: CGFloat = Theme.tileSize

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(isActive ? Theme.accent : .secondary)
            .frame(width: size, height: size)
            .background(isActive ? Theme.accentSoft : Color.secondary.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Grouped card container used by every page.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .glassSurface(radius: Theme.cardRadius)
    }
}

/// Frosted glass: a translucent fill that catches light from the top left, a bright rim that fades towards the
/// bottom right, and a soft shadow that lifts it off the page. With Reduce transparency on, it is a solid fill.
struct GlassSurface: ViewModifier {
    let radius: CGFloat
    /// A rim colour that replaces the white one, such as the accent on the card in use.
    var rim: Color?
    var rimWidth: CGFloat = 1
    /// Small controls skip the frost and the shadow; they sit on a surface that already has both.
    var isChip = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isDark: Bool { scheme == .dark }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(rim ?? Theme.hairline, lineWidth: rimWidth))
        } else {
            content
                .background {
                    ZStack {
                        if !isChip { shape.fill(.ultraThinMaterial) }
                        shape.fill(LinearGradient(colors: fill, startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                .overlay(shape.strokeBorder(rim.map { AnyShapeStyle($0) } ?? AnyShapeStyle(rimGradient), lineWidth: rimWidth))
                .shadow(color: .black.opacity(isChip ? 0 : (isDark ? 0.18 : 0.08)), radius: 4, y: 2)
        }
    }

    private var fill: [Color] {
        isDark ? [.white.opacity(isChip ? 0.12 : 0.09), .white.opacity(isChip ? 0.05 : 0.03)]
               : [.white.opacity(0.7), .white.opacity(0.38)]
    }

    private var rimGradient: LinearGradient {
        let colors: [Color] = isDark ? [.white.opacity(0.3), .white.opacity(0.05), .white.opacity(0.12)]
                                     : [.white.opacity(0.95), .black.opacity(0.04), .black.opacity(0.08)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension View {
    func glassSurface(radius: CGFloat = Theme.groupRadius, rim: Color? = nil, rimWidth: CGFloat = 1) -> some View {
        modifier(GlassSurface(radius: radius, rim: rim, rimWidth: rimWidth))
    }

    /// A choice button: lit glass when idle, the accent with a soft highlight on top when picked.
    func glassChip(isSelected: Bool, radius: CGFloat = 7) -> some View {
        modifier(GlassChip(isSelected: isSelected, radius: radius))
    }
}

struct GlassChip: ViewModifier {
    let isSelected: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if isSelected {
            content
                .background(Theme.accent, in: shape)
                .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.28), .clear],
                                                   startPoint: .top, endPoint: .center)))
                .overlay(shape.strokeBorder(.white.opacity(0.35)))
                .shadow(color: Theme.accent.opacity(0.35), radius: 4, y: 1)
        } else {
            content.modifier(GlassSurface(radius: radius, isChip: true))
        }
    }
}

/// Small capsule label ("2 takes", "Needs permission").
struct Badge: View {
    let text: String
    var color: Color = .secondary
    var symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(L(text))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
    }
}

struct PageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.control) {
            VStack(alignment: .leading, spacing: Spacing.micro) {
                Text(L(title)).font(.largeTitle.weight(.semibold))
                Text(L(subtitle)).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            accessory
        }
    }
}

/// Round play button used next to sounds and triggers.
struct PlayButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24, height: 24)
                .background(Theme.accentSoft, in: Circle())
        }
        .buttonStyle(.plain)
        .help(L("Preview"))
        .accessibilityLabel(L("Preview sound"))
    }
}

extension View {
    func rowPadding() -> some View {
        padding(.horizontal, 14).padding(.vertical, 10)
    }
}
