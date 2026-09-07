import SwiftUI

/// A colour entry's preview: the colour and the copied text, the notations being ⌘K's business.
struct ColorPreview: View {
    let color: ColorValue
    let text: String

    /// Fixed at any pane width: stretched edge to edge a sample reads as a background.
    private static let swatchSize = Theme.Size.clipboardColorSwatch

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ColorSwatch(color: color, cornerRadius: Theme.Radius.card)
                .frame(width: Self.swatchSize.width, height: Self.swatchSize.height)
            Text(text)
                .font(Theme.Typography.previewBody)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xxl)
    }
}
