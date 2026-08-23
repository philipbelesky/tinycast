#if DEBUG
    import SwiftUI

    /// A dark desktop: transparency and corner-mask bugs only show against a contrasting one.
    private enum PreviewDesktop {
        static let top = Color(red: 0.09, green: 0.10, blue: 0.15)
        static let bottom = Color(red: 0.26, green: 0.17, blue: 0.32)
        static let inset: CGFloat = Theme.Spacing.xxl * 2
    }

    @MainActor
    extension View {

        /// For a view that already draws its own surface: the palette, a dialog, either HUD.
        func previewOnDesktop() -> some View {
            padding(PreviewDesktop.inset)
                .background(
                    LinearGradient(
                        colors: [PreviewDesktop.top, PreviewDesktop.bottom],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .previewStores()
                // Pinned, not inherited: a canvas never runs `AppCore.start()`, so it has no Theme.
                .preferredColorScheme(.light)
        }

        /// For a leaf control with no list to fill a panel; glass still needs a real backdrop.
        func previewOnPanel() -> some View {
            padding(Theme.Spacing.xxl)
                .background(Theme.Colors.panelScrim)
                .background(VisualEffectView())
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
                .previewOnDesktop()
        }

        /// For content that normally lives *inside* the panel — a list, a card, the header bar.
        func previewInPalette(
            width: CGFloat = Theme.Size.panelWidth, height: CGFloat = Theme.Size.panelHeight
        ) -> some View {
            frame(width: width, height: height)
                .background(Theme.Colors.panelScrim)
                .background(VisualEffectView())
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                .previewOnDesktop()
        }

        /// The live graph is safe here: `AppCore.init` only constructs, `start()` does the wiring.
        func previewStores(_ core: AppCore = .shared) -> some View {
            environment(core)
                .environment(core.settings)
                .environment(core.palette)
                .environment(core.appIndex)
                .environment(core.hotKeys)
                .environment(core.runningApps)
                .environment(core.favorites)
                .environment(core.visibility)
                .environment(core.clipboardStore)
                .environment(core.calcHistory)
                .environment(core.currencyRates)
                .environment(core.emojiIndex)
                .environment(core.frequentEmoji)
                .environment(core.quicklinks)
                .environment(core.quicklinkArguments)
                .environment(core.uninstall)
        }
    }
#endif
