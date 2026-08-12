import SwiftUI

/// A single keycap chip: `.outline` for hotkey hints on rows, `.filled` for footer shortcuts.
struct KeyCapChip: View {
    enum Style {
        case outline
        case filled
    }

    /// Sanctioned cap sizes, so a bigger or smaller one is a named choice, not a stray frame.
    enum Scale {
        case compact
        case standard
        case hero

        var side: CGFloat {
            switch self {
            case .compact: Theme.Size.compactKeyCap
            case .standard: Theme.Size.keyCap
            case .hero: Theme.Size.heroKeyCap
            }
        }

        var font: Font {
            switch self {
            case .compact: Theme.Typography.compactKeyCap
            case .standard: Theme.Typography.keyCap
            case .hero: Theme.Typography.heroKeyCap
            }
        }
    }

    let text: String
    var style: Style = .filled
    var scale: Scale = .standard

    /// "↵" falls back to another face that seats high, so nudge it render-only.
    private static let returnGlyphDrop: CGFloat = 1.1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
        Text(text)
            .font(scale.font)
            .foregroundStyle(Theme.Colors.textSecondary)
            .offset(y: text == "↵" ? Self.returnGlyphDrop : 0)
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(minWidth: scale.side, minHeight: scale.side)
            .background {
                switch style {
                case .filled: shape.fill(Theme.Colors.controlSurface)
                case .outline: shape.strokeBorder(Theme.Colors.border, lineWidth: 1)
                }
            }
    }
}

#if DEBUG
    #Preview("Key caps") {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.xxs) {
                KeyCapChip(text: "⌘", style: .outline)
                KeyCapChip(text: "K", style: .outline)
                KeyCapChip(text: "↵", style: .outline)
                KeyCapChip(text: "esc", style: .outline)
            }
            HStack(spacing: Theme.Spacing.xxs) {
                KeyCapChip(text: "⌘", style: .filled)
                KeyCapChip(text: "K", style: .filled)
                KeyCapChip(text: "↵", style: .filled)
            }
            // The three sanctioned scales side by side, since only relative size tells them apart.
            HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                KeyCapChip(text: "⌥", scale: .compact)
                KeyCapChip(text: "⌥", scale: .standard)
                KeyCapChip(text: "⌥", scale: .hero)
            }
        }
        .previewOnPanel()
    }
#endif
