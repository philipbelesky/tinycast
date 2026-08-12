import SwiftUI

/// Section label above a group of rows, shared by every palette list.
struct SectionHeader: View {
    let title: String
    /// The first header hugs the top; later ones get spacing above, reading as below.
    var isFirst = false
    var body: some View {
        Text(title)
            .font(Theme.Typography.sectionHeader)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, isFirst ? Theme.Spacing.xs : Theme.Spacing.sectionSpacing)
            .padding(.bottom, Theme.Spacing.sectionHeaderBottom)
    }
}

#if DEBUG
    /// The rhythm only reads with a row between headers, and with the first one hugging the top.
    #Preview("Section headers") {
        VStack(spacing: 0) {
            SectionHeader(title: "Favorites", isFirst: true)
            Text("Notes")
                .font(Theme.Typography.rowTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            SectionHeader(title: "Applications")
            Text("Music")
                .font(Theme.Typography.rowTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            SectionHeader(title: "Commands")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .previewInPalette(height: Theme.Size.panelHeight / 2)
    }
#endif
