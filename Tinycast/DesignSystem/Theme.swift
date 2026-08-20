import AppKit
import SwiftUI

/// Central design tokens; the app forces `.aqua`, so colours are literal alphas.
enum Theme {
    /// Multiplies every length and font size below; ratios, alphas and durations are exempt.
    static let scale: CGFloat = 1.25

    enum Spacing {
        static let xxs: CGFloat = 2 * scale
        static let xs: CGFloat = 4 * scale
        static let sm: CGFloat = 6 * scale
        static let md: CGFloat = 8 * scale
        static let lg: CGFloat = 10 * scale
        static let xl: CGFloat = 12 * scale
        static let xxl: CGFloat = 20 * scale
        /// Calculator answer card's roomier vertical breathing room.
        static let xxxl: CGFloat = 28 * scale
        /// Gap under a category header, shared by every palette list's `SectionHeader`.
        static let sectionHeaderBottom: CGFloat = 4 * scale
        /// Space above every header but the first, reading as the previous section's close.
        static let sectionSpacing: CGFloat = 12 * scale
    }

    enum Radius {
        static let panel: CGFloat = 26 * scale
        static let row: CGFloat = 10 * scale
        static let menu: CGFloat = 6 * scale
        /// Hover highlight behind a popover menu row.
        static let menuRow: CGFloat = 10 * scale
        static let menuPanel: CGFloat = 16 * scale
        /// The dialog and HUD surface, so a dialog reads as a sibling of the palette.
        static let dialog: CGFloat = 20 * scale
        static let thumbnail: CGFloat = 6 * scale
        static let card: CGFloat = 10 * scale
        static let keyCap: CGFloat = 6 * scale
        /// Settings shortcut-recorder keycap — smaller than the palette's `keyCap` chip.
        static let recorderKeyCap: CGFloat = 4 * scale
    }

    enum Size {
        static let panelWidth: CGFloat = 750 * scale
        static let panelHeight: CGFloat = 475 * scale
        /// Opening size on a first run and the floor: below it the title bar's own parts collide.
        static let noteWindow = CGSize(width: 440 * scale, height: 180 * scale)
        static let noteEditorInset: CGFloat = 16 * scale
        /// Shorter than the horizontal inset, so the first line sits close under the title bar.
        static let noteEditorTopInset: CGFloat = 6 * scale
        static let noteSearchHeight: CGFloat = 34 * scale
        /// The switcher popover, sized independently of a note window that can be 180pt tall.
        static let noteSwitcher = CGSize(width: 300 * scale, height: 240 * scale)
        static let noteSwitcherEmptyHeight: CGFloat = 96 * scale
        static let noteSwitcherDrop: CGFloat = 56 * scale
        static let noteFooterHeight: CGFloat = 28 * scale
        /// Holds the launcher's action capsule with the same margin its own bar gives it.
        static let noteTitlebar: CGFloat = 52 * scale
        /// Symmetric, so the title stays centred on the window while clearing lights and capsule.
        static let noteTitleInset: CGFloat = 120 * scale
        /// Notes seats its traffic lights further in than the palette.
        static let noteTrafficLightInset: CGFloat = 20 * scale
        /// Fraction of visible height above the palette's top edge; it grows downward.
        static let paletteTopMarginFraction: CGFloat = 0.18
        static let headerHeight: CGFloat = 44 * scale
        /// Fixed slot for the header glyph, so the field starts at one x in every mode.
        static let headerIconSlot: CGFloat = 22 * scale
        /// Room above the search row, constant so typing never shifts the bar.
        static let headerPadding: CGFloat = 10 * scale
        /// Collapsed compact bar: the search row centered in symmetric `headerPadding` slack.
        static let compactHeight: CGFloat = headerHeight + headerPadding * 2
        /// How near the default placement a drag has to land before it snaps home.
        static let paletteSnapDistance: CGFloat = 24 * scale
        /// A restored position needs this much of the compact bar on a display to still be grabbable.
        static let paletteMinimumVisible: CGFloat = 44 * scale
        /// Dash and gap of the drop guides, equal so the line reads evenly. Chrome, so unscaled.
        static let dropGuideDash: CGFloat = 4
        static let dropGuideWidth: CGFloat = 2
        static let bottomBarHeight: CGFloat = 52 * scale
        /// A footer button's hover capsule, shorter than the bar it sits in.
        static let barButtonHeight: CGFloat = 28 * scale
        static let rowIcon: CGFloat = 24 * scale
        /// The running-app dot under a launcher icon; doubles as its drop below the slot.
        static let runningDot: CGFloat = 3 * scale
        static let keyCap: CGFloat = 18 * scale
        /// Settings shortcut-recorder keycap — smaller than the palette's `keyCap` chip.
        static let recorderKeyCap: CGFloat = 16 * scale
        /// Fixed so the recorder can't resize as its binding changes.
        static let shortcutRecorder: CGFloat = 120 * scale
        /// One text line in the recorder callout.
        static let shortcutPopoverLine: CGFloat = 14 * scale
        /// Summed from the laid-out bands; the width is pinned by `callout-test`.
        static let shortcutPopover = CGSize(
            width: 132 * scale,
            height: Spacing.sm * 2 + heroKeyCap + Spacing.sm + shortcutPopoverLine + Spacing.sm
                + compactKeyCap + calloutCaretHeight)
        /// The callout's pointer: a triangle with a rounded tip.
        static let calloutCaretWidth: CGFloat = 15 * scale
        static let calloutCaretHeight: CGFloat = 7 * scale
        static let calloutCaretTip: CGFloat = 2.5 * scale
        /// Keycaps: `compact` hints, `keyCap` is standard, `hero` where the cap is content.
        static let compactKeyCap: CGFloat = 15 * scale
        static let heroKeyCap: CGFloat = 22 * scale
        static let menuButton: CGFloat = 36 * scale
        static let noteGlyph: CGFloat = 16 * scale
        static let noteEmptyGlyph: CGFloat = 28 * scale
        /// The menu circle's hand-drawn two-line glyph: long bar, short bar, weight, gap.
        static let menuGlyphWide: CGFloat = 14 * scale
        static let menuGlyphNarrow: CGFloat = 8 * scale
        static let menuGlyphWeight: CGFloat = 1.5 * scale
        static let menuGlyphGap: CGFloat = 3 * scale
        /// The uninstall list's leading checkbox / lock glyph.
        static let checkbox: CGFloat = 16 * scale
        static let clipboardListWidth: CGFloat = 290 * scale
        /// An app icon in the clipboard preview's metadata rows.
        static let previewRowIcon: CGFloat = 20 * scale
        static let emojiCell: CGFloat = 56 * scale
        static let menuWidth: CGFloat = 276 * scale
        /// The clipboard type filter's menu; `menuWidth` is too wide for five short rows.
        static let clipboardFilterMenuWidth: CGFloat = 200 * scale
        /// A menu row's glyph slot, sized so symbol and app-icon rows read the same.
        static let menuIcon: CGFloat = 20 * scale
        /// Opening size and the resize floor; tall enough that the sidebar's rows never scroll.
        static let settingsWindow = CGSize(width: 860 * scale, height: 700 * scale)
        /// Settings sidebar: a fixed column, wide enough for "Window Management".
        static let settingsSidebar: CGFloat = 215 * scale
        /// The narrowest the pane column may get before a grouped row's control starts colliding.
        static let settingsDetailMinimum: CGFloat = 420 * scale
        static let settingsRowIcon: CGFloat = 20 * scale
        /// Settings editor modals (Custom Commands, Snippets): fixed width, intrinsic height.
        static let editorSheetWidth: CGFloat = 480 * scale
        /// Label column of an extension form, so every field's input starts on one line.
        static let formLabelWidth: CGFloat = 110 * scale
        /// The multi-line box inside those modals; it scrolls rather than grows the sheet.
        static let editorTextHeight: CGFloat = 120 * scale
        /// The argument prompt's field column, kept under the alert's natural width.
        static let argumentPromptWidth: CGFloat = 220 * scale
        /// The confirmation HUD's width ceiling, and its distance above the screen bottom.
        static let hudMaxWidth: CGFloat = 420 * scale
        static let hudEdgeOffset: CGFloat = 48 * scale
        /// Tinycast's own dialog: fixed width, height measured from the SwiftUI content.
        static let dialogWidth: CGFloat = 420 * scale
        /// A dialog's leading glyph, larger than a row icon: it carries the subject.
        static let dialogIcon: CGFloat = 32 * scale
        /// Transient volume HUD shown after any volume or mute command.
        static let hudWidth: CGFloat = 200 * scale
        static let hudHeight: CGFloat = 100 * scale
        /// Volume slider geometry, shared by the Set Volume dialog and the HUD's read-only bar.
        static let volumeTrackHeight: CGFloat = 6 * scale
        static let volumeKnob: CGFloat = 16 * scale
        /// Fixed slot for the level readout, sized to the widest string it ever holds.
        static let volumeReadout: CGFloat = 38 * scale
    }

    enum Duration {
        /// How long each HUD stays up; a sentence needs longer than a level does.
        static let messageHUD: TimeInterval = 2.4
        static let volumeHUD: TimeInterval = 1.6
        /// How a borderless surface arrives and leaves; the exit is shorter, so it feels quick.
        static let enter: TimeInterval = 0.18
        static let exit: TimeInterval = 0.12
        /// Fade-in/out for a hover `Tooltip`.
        static let tooltip: TimeInterval = 0.15
    }

    /// Point sizes are the platform's own text-style metrics, so `scale` is the only departure.
    enum Typography {
        /// One size, two frameworks: `TextTrailingDragHandle` measures what the field renders.
        static let searchFieldSize: CGFloat = 20 * scale
        static let searchField = Font.system(size: searchFieldSize, weight: .regular)
        /// `NSFont` is not `Sendable`, hence the isolation; every reader is a view anyway.
        @MainActor static let searchFieldNSFont = NSFont.systemFont(
            ofSize: searchFieldSize, weight: .regular)
        static let headerIcon = scaled(18, .medium)
        static let rowTitle = scaled(.body)
        static let rowTrailing = scaled(.callout)
        static let sectionHeader = scaled(.subheadline, .medium)
        /// The big value line on the calculator answer card (both source and target sides).
        static let calcResult = scaled(.title1)
        /// The `arrow.right` between a value answer's source and target columns.
        static let calcArrow = scaled(.title3, .semibold)
        /// A calculator card that reports a parse failure instead of an answer.
        static let calcMessage = scaled(.body)
        static let keyCap = scaled(.caption1)
        /// Pair with the matching `Size` for `KeyCapChip.Scale`.
        static let compactKeyCap = scaled(.caption2)
        static let heroKeyCap = scaled(.body)
        static let bar = scaled(.callout, .medium)
        /// A dropdown control's trailing chevron, smaller than the label it follows.
        static let disclosure = scaled(.caption1, .semibold)
        static let menuRow = scaled(.body)
        static let menuShortcut = scaled(.callout)
        static let menuIcon = scaled(.body)
        static let noteTitle = scaled(.headline)
        /// A dialog's title line, above its wrapped `rowTrailing` message.
        static let dialogTitle = scaled(.headline, .bold)
        /// The oversized glyph an empty list or a missing thumbnail stands in with.
        static let emptyGlyph = scaled(.largeTitle)
        /// The clipboard preview pane: monospaced content, then its metadata rows.
        static let previewBody = scaled(.subheadline, .regular, .monospaced)
        static let previewDetail = scaled(.callout)
        /// The name above an argument's field in a prompt.
        static let fieldLabel = scaled(.callout, .medium)
        /// A symbol centred in a `rowIcon` tile, standing in for an app icon.
        static let tileGlyph = scaled(12)
        /// A small trailing marker on a row — hidden-from-search, overflow, argument progress.
        static let hintGlyph = scaled(10)
        static let statusGlyph = scaled(11)
        /// One emoji in its `emojiCell`, where the glyph is the whole content.
        static let emojiGlyph = scaled(30)

        private static func scaled(
            _ points: CGFloat, _ weight: Font.Weight = .regular,
            _ design: Font.Design = .default
        ) -> Font {
            .system(size: points * scale, weight: weight, design: design)
        }

        private static func scaled(
            _ style: NSFont.TextStyle, _ weight: Font.Weight = .regular,
            _ design: Font.Design = .default
        ) -> Font {
            scaled(NSFont.preferredFont(forTextStyle: style).pointSize, weight, design)
        }
    }

    enum Colors {
        /// The panel's surface tint over the behind-window material; a Color, so no call site
        /// has to know which way the surface leans.
        static let panelTint = Color.white.opacity(0.55)
        /// Selection fill, shared by every list so they look identical.
        static let selection = Color.black.opacity(0.09)
        /// Mouse hover: a fainter layer, visually distinct from selection.
        static let rowHover = Color.black.opacity(0.045)
        static let menuHover = Color.black.opacity(0.09)
        static let separator = Color.black.opacity(0.10)
        /// Small control surfaces: kbd chips, glyph tiles.
        static let controlSurface = Color.black.opacity(0.08)
        /// Control borders: outlined kbd chips.
        static let border = Color.black.opacity(0.16)
        static let textPrimary = Color.black
        static let textSecondary = Color.black.opacity(0.60)
        static let textTertiary = Color.black.opacity(0.40)
        static let noteText = Color.black.opacity(0.85)
        static let iconPlaceholder = Color.black.opacity(0.06)
        /// The faint wash behind a header on the light surface.
        static let sheen = Color.black.opacity(0.04)
        /// The Settings card: a faint surface whose border doubles as the row divider.
        static let cardFill = Color.white.opacity(0.45)
        static let cardStroke = Color.black.opacity(0.10)
        /// Tint layered into the floating controls, so the glass reads frosted, not clear.
        static let glassFrost = Color.white.opacity(0.30)
        /// The violet of the app mark, used only to tint the About support callout.
        static let brand = Color(red: 0.525, green: 0.231, blue: 1.0)
        /// The palette's drop guides while dragging, and once a release would snap it home.
        static let dropGuide = Color.white.opacity(0.35)
        static let dropGuideArmed = Color.blue

        /// Category tiles carry a white glyph and are the surface's only category-coded colour.
        static func tile(_ tint: ScopeTint) -> NSColor {
            switch tint {
            case .teal: return .systemTeal
            case .cyan: return .systemCyan
            case .orange: return .systemOrange
            case .purple: return .systemPurple
            case .brown: return .systemBrown
            case .black: return .black
            case .indigo: return .systemIndigo
            case .yellow: return .systemYellow
            case .slate: return .systemGray
            }
        }

        /// Destructive tint: a destructive label, and a `.danger` dialog's glyph.
        static let destructive = Color.red
        /// Success tint: the leading glyph of a `.success` dialog.
        static let success = Color.green
    }
}

extension View {
    /// A floating glass control surface, frosted so it reads brighter than clear glass.
    func frosted(in shape: some Shape) -> some View {
        glassEffect(.regular.interactive().tint(Theme.Colors.glassFrost), in: shape)
            .tint(.clear)
    }
}
