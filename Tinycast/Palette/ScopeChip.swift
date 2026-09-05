import SwiftUI

/// The committed scope, shown before the search field. See docs/features/palette.md#scope-keywords.
struct ScopeChip: View {
    let scope: ScopeDefinition
    let onClear: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: scope.symbol)
                .font(Theme.Typography.rowTrailing)
                .symbolRenderingMode(.hierarchical)
            Text(scope.title)
                .font(Theme.Typography.rowTrailing)
                .lineLimit(1)
            // A target, not decoration: bare backspace does the same thing from the keyboard.
            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(Theme.Typography.compactKeyCap)
                    .foregroundStyle(Color.white.opacity(hovered ? 1 : 0.65))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                .fill(Color(nsColor: Theme.Colors.tile(scope.tint)))
        )
        .fixedSize()
        .armedHover($hovered)
    }
}

#if DEBUG
    #Preview("Scope chip") {
        ScopeChip(scope: PreviewData.scope, onClear: {})
            .previewOnPanel()
    }
#endif
