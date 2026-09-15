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

        func side(_ metrics: InterfaceMetrics) -> CGFloat {
            switch self {
            case .compact: metrics.size.compactKeyCap
            case .standard: metrics.size.keyCap
            case .hero: metrics.size.heroKeyCap
            }
        }

        @MainActor
        func font(_ metrics: InterfaceMetrics) -> Font {
            switch self {
            case .compact: metrics.typography.compactKeyCap
            case .standard: metrics.typography.keyCap
            case .hero: metrics.typography.heroKeyCap
            }
        }
    }

    let text: String
    var style: Style = .filled
    var scale: Scale = .standard
    @Environment(\.metrics) private var metrics

    /// "↵" falls back to another face that seats high, so nudge it render-only.
    private static let returnGlyphDrop: CGFloat = 1.1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.keyCap, style: .continuous)
        Text(text)
            .font(scale.font(metrics))
            .foregroundStyle(Theme.Colors.textSecondary)
            .offset(y: text == "↵" ? Self.returnGlyphDrop : 0)
            .padding(.horizontal, metrics.spacing.xs)
            .frame(minWidth: scale.side(metrics), minHeight: scale.side(metrics))
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
