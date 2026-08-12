#if DEBUG
    import AppKit
    import SwiftUI

    /// Literal, offline fixtures: a canvas must never depend on a scan, a fetch or a live store.
    @MainActor
    enum PreviewData {

        // MARK: - Launcher

        static let notes = AppEntry(
            id: "/System/Applications/Notes.app", name: "Notes",
            url: URL(fileURLWithPath: "/System/Applications/Notes.app"),
            bundleID: "com.apple.Notes", kind: .application)

        static let music = AppEntry(
            id: "/System/Applications/Music.app", name: "Music",
            url: URL(fileURLWithPath: "/System/Applications/Music.app"),
            bundleID: "com.apple.Music", kind: .application)

        static let mail = AppEntry(
            id: "/System/Applications/Mail.app", name: "Mail",
            url: URL(fileURLWithPath: "/System/Applications/Mail.app"),
            bundleID: "com.apple.mail", kind: .application)

        static let terminal = AppEntry(
            id: "/System/Applications/Utilities/Terminal.app", name: "Terminal",
            url: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            bundleID: "com.apple.Terminal", kind: .application)

        static let applicationsScope = AppEntry(
            id: "scope:applications", name: "Search Applications",
            url: URL(string: "tinycast://scope/applications")!, bundleID: nil, kind: .scope,
            symbolName: "square.grid.2x2", symbolTint: .blue)

        static let linearScope = AppEntry(
            id: "scope:linear", name: "Search Linear",
            url: URL(string: "tinycast://scope/linear")!, bundleID: nil, kind: .scope,
            symbolName: "list.bullet.rectangle", symbolTint: .indigo)

        static let sleepAction = AppEntry(
            id: "system-action:sleep", name: "Sleep",
            url: URL(string: "tinycast://system-action/sleep")!, bundleID: nil, kind: .systemAction)

        static let leftHalf = AppEntry(
            id: "window-command:left-half", name: "Left Half",
            url: URL(string: "tinycast://window-command/left-half")!, bundleID: nil,
            kind: .windowCommand)

        /// The launcher's resting shape: two favorites, then a section per kind.
        static let launcherResults: [AppEntry] = [
            notes, music, applicationsScope, linearScope, mail, terminal, sleepAction, leftHalf
        ]

        static let launcherFavoriteCount = 2

        // MARK: - Calculator

        static let calcArithmetic = CalcResult(
            expression: "1,234 × 56", sourceBadge: "Expression", targetBadge: "Result",
            payload: .value(display: "69,104", copyText: "69104"))

        static let calcConversion = CalcResult(
            expression: "12 kg", sourceBadge: "Kilograms", targetBadge: "Pounds",
            payload: .value(display: "26.46", copyText: "26.4555"))

        static let calcError = CalcResult(
            expression: "10 km in kg", payload: .error(message: "Can't convert length to mass"))

        static let calcHistory: [CalcHistoryEntry] = [
            CalcHistoryEntry(
                id: UUID(), expression: "1,234 × 56", result: "69,104", createdAt: minutesAgo(4)),
            CalcHistoryEntry(
                id: UUID(), expression: "128 GB in MB", result: "131,072 MB",
                createdAt: minutesAgo(52)),
            CalcHistoryEntry(
                id: UUID(), expression: "18% of 240", result: "43.2", createdAt: daysAgo(1)),
            CalcHistoryEntry(
                id: UUID(), expression: "0xff", result: "255", createdAt: daysAgo(9))
        ]

        // MARK: - Clipboard

        static let clipboardItems: [ClipboardItem] = [
            ClipboardItem(
                id: UUID(), kind: .text, text: "https://github.com/abue-ammar/tinycast",
                imagePath: nil, createdAt: minutesAgo(9), sourceBundleID: "com.apple.Safari",
                pinnedAt: minutesAgo(30)),
            ClipboardItem(
                id: UUID(), kind: .text, text: "xcodegen generate && ./Scripts/run-tests.sh",
                imagePath: nil, createdAt: minutesAgo(2),
                sourceBundleID: "com.apple.Terminal"),
            ClipboardItem(
                id: UUID(), kind: .image, text: nil, imagePath: nil, createdAt: minutesAgo(26),
                sourceBundleID: "com.apple.Preview"),
            ClipboardItem(
                id: UUID(),
                kind: .text,
                text: "The header and bottom bar float over the list as fully transparent overlays.",
                imagePath: nil, createdAt: daysAgo(1), sourceBundleID: "com.apple.Notes")
        ]

        // MARK: - Quicklinks

        static let quicklinks: [Quicklink] = [
            Quicklink(
                name: "Tinycast Issues", link: "https://github.com/abue-ammar/tinycast/issues",
                iconSymbol: "ladybug", pinnedAt: daysAgo(3)),
            Quicklink(name: "Search MDN", link: "https://developer.mozilla.org/search?q={query}"),
            Quicklink(
                name: "Swift Forums", link: "https://forums.swift.org", showsInRootSearch: false)
        ]

        static let quicklinkOptions = ["staging", "production", "local"]

        // MARK: - Uninstall

        static let uninstallCandidates: [UninstallCandidate] = [
            UninstallCandidate(
                path: "/Applications/Example.app", name: "Example",
                locationLabel: "Applications", evidence: .bundle, isDirectory: true,
                size: MeasuredSize(bytes: 214_000_000), protection: .removable),
            UninstallCandidate(
                path: "~/Library/Application Support/com.example.app",
                name: "com.example.app", locationLabel: "~/Library/Application Support",
                evidence: .bundleID, isDirectory: true,
                size: MeasuredSize(bytes: 48_300_000, isLowerBound: true), protection: .removable),
            UninstallCandidate(
                path: "~/Library/Preferences/com.example.app.plist",
                name: "com.example.app.plist", locationLabel: "~/Library/Preferences",
                evidence: .bundleID, isDirectory: false, size: MeasuredSize(bytes: 4_096),
                protection: .removable),
            UninstallCandidate(
                path: "/usr/local/bin/example", name: "example", locationLabel: "/usr/local/bin",
                evidence: .binSymlink, isDirectory: false, size: MeasuredSize(bytes: 62),
                protection: .parentNotWritable)
        ]

        static let uninstallSummary = "4 items · 262.3 MB"

        // MARK: - Emoji

        private static let smileys: [EmojiEntry] = [
            EmojiEntry(glyph: "😀", name: "grinning face", category: .smileysAndPeople,
                supportsSkinTone: false, keywords: "smile happy"),
            EmojiEntry(glyph: "😅", name: "grinning face with sweat", category: .smileysAndPeople,
                supportsSkinTone: false, keywords: "relief"),
            EmojiEntry(glyph: "🤔", name: "thinking face", category: .smileysAndPeople,
                supportsSkinTone: false, keywords: "hmm"),
            EmojiEntry(glyph: "👋", name: "waving hand", category: .smileysAndPeople,
                supportsSkinTone: true, keywords: "wave hello"),
            EmojiEntry(glyph: "👍", name: "thumbs up", category: .smileysAndPeople,
                supportsSkinTone: true, keywords: "yes approve"),
            EmojiEntry(glyph: "🙌", name: "raising hands", category: .smileysAndPeople,
                supportsSkinTone: true, keywords: "celebrate"),
            EmojiEntry(glyph: "🎉", name: "party popper", category: .activity,
                supportsSkinTone: false, keywords: "celebration"),
            EmojiEntry(glyph: "🚀", name: "rocket", category: .travelAndPlaces,
                supportsSkinTone: false, keywords: "ship launch"),
            EmojiEntry(glyph: "🔥", name: "fire", category: .travelAndPlaces,
                supportsSkinTone: false, keywords: "hot lit"),
            EmojiEntry(glyph: "✨", name: "sparkles", category: .activity,
                supportsSkinTone: false, keywords: "shiny")
        ]

        private static let objects: [EmojiEntry] = [
            EmojiEntry(glyph: "💻", name: "laptop", category: .objects, supportsSkinTone: false,
                keywords: "computer"),
            EmojiEntry(glyph: "⌨️", name: "keyboard", category: .objects, supportsSkinTone: false,
                keywords: "type"),
            EmojiEntry(glyph: "🖱️", name: "computer mouse", category: .objects,
                supportsSkinTone: false, keywords: "pointer"),
            EmojiEntry(glyph: "📦", name: "package", category: .objects, supportsSkinTone: false,
                keywords: "box ship"),
            EmojiEntry(glyph: "🔑", name: "key", category: .objects, supportsSkinTone: false,
                keywords: "lock secret")
        ]

        /// Two sections, so the preview shows the header rhythm and a partial trailing row.
        static let emojiSections: [EmojiGridSection] = [
            EmojiGridSection(title: "Frequently Used", entries: smileys, start: 0),
            EmojiGridSection(title: "Objects", entries: objects, start: smileys.count)
        ]

        // MARK: - Palette chrome

        static let scope = ScopeDefinition(
            keyword: "l", id: "scope:linear", title: "Linear", symbol: "list.bullet.rectangle",
            tint: .indigo)

        static let menuItems: [PopoverMenuItem] = [
            PopoverMenuItem(title: "Open Application", systemImage: "arrow.up.forward.app",
                shortcut: "↵") {},
            PopoverMenuItem(title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵") {},
            PopoverMenuItem(title: "Add to Favorites", systemImage: "star") {},
            PopoverMenuItem(title: "Uninstall", systemImage: "trash", isDestructive: true) {}
        ]

        // MARK: - Dialogs and HUDs

        static let confirmDialog = DialogRequest(
            title: "Restart your Mac?", message: "Every open app will be asked to quit first.",
            symbol: "arrow.clockwise",
            actions: [DialogAction(title: "Restart"), DialogAction(title: "Cancel", role: .cancel)],
            defaultIndex: 0, cancelIndex: 1)

        static let destructiveDialog = DialogRequest(
            title: "Move Example to the Trash?",
            message: "4 items totalling 262.3 MB will be moved to the Trash. You can put them back"
                + " from there.",
            symbol: "trash", tone: .danger,
            actions: [
                DialogAction(title: "Move to Trash", role: .destructive),
                DialogAction(title: "Cancel", role: .cancel)
            ],
            defaultIndex: 0, cancelIndex: 1)

        /// The one dialog whose glyph tone and button role disagree, which is the point of it.
        static let importDialog = DialogRequest(
            title: "Import executable commands?",
            message: "This backup contains 3 custom commands. They run shell scripts you did not"
                + " write on this Mac.",
            symbol: "square.and.arrow.down", tone: .danger,
            actions: [DialogAction(title: "Import"), DialogAction(title: "Cancel", role: .cancel)],
            defaultIndex: 0, cancelIndex: 1)

        static var volumeDialog: DialogRequest {
            DialogRequest(
                title: "Set Volume", message: "Choose the output volume.", symbol: "speaker.wave.2",
                actions: [
                    DialogAction(title: "Set Volume"),
                    DialogAction(title: "Cancel", role: .cancel)
                ],
                defaultIndex: 0, cancelIndex: 1, volume: VolumeState(level: 0.65))
        }

        // MARK: - Clocks

        /// Bucketed lists read as "Today"/"Yesterday" only against the real clock.
        static func minutesAgo(_ minutes: Int) -> Date {
            Date(timeIntervalSinceNow: -Double(minutes) * 60)
        }

        static func daysAgo(_ days: Int) -> Date {
            Date(timeIntervalSinceNow: -Double(days) * 86_400)
        }
    }
#endif
