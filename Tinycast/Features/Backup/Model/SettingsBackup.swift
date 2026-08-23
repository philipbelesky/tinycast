import Foundation

/// A readable configuration snapshot; every field is optional, so an import merges.
struct SettingsBackup: Codable {
    var version = 4
    var settings: SettingsData?
    var hotkeys: HotkeyBackup?
    var customCommands: [CustomCommand]?
    var quicklinks: [Quicklink]?
    var favoriteApps: [String]?
    var hiddenLauncherItems: [String]?
    var hiddenLauncherKinds: [String]?

    /// Enums store by raw value, so an unknown one is ignored rather than failing.
    struct SettingsData: Codable {
        // Adding a field here means adding it to SettingsBackupCoverage too, or the harness fails.
        var clipboardRetentionDays: Int?
        var clipboardDisabledApps: [String]?
        var launchAtLogin: Bool?
        var hyperKey: String?
        var hyperKeyIncludesShift: Bool?
        var hyperKeyQuickPress: String?
        var emojiSkinTone: String?
        var showInMenuBar: Bool?
        var popToRootSeconds: Int?
        var appearance: String?
        var compactMode: Bool?
        var showFavoritesInCompactMode: Bool?
        var searchScopes: [String]?
        var openOnCursorScreen: Bool?
        // Safe to carry: it grants no permission class, just repositions the window.
        var paletteDraggable: Bool?
        var fileSearchEnabled: Bool?
        var fileSearchScopes: [String]?
        var fileSearchIgnorePatterns: [String]?
        // `snippetsEnabled` is absent: an import must not enable keystroke listening.
        var customCommandsEnabled: Bool?
        var customCommandsShowInLauncher: Bool?
        var snippetsShowInLauncher: Bool?
        // Safe to carry: it grants no permission class paste doesn't already prompt for.
        var windowManagementEnabled: Bool?
        var windowManagementShowInLauncher: Bool?
        var windowGap: Int?
        var windowCycleOnRepeat: Bool?
        // Carried, unlike `snippetsEnabled`: opening a link grants no permission class of its own.
        var quicklinksEnabled: Bool?
        var quicklinksShowInLauncher: Bool?
        var quicklinkOpensNewWindow: Bool?
        var quicklinkSelectionFallback: String?
        var quicklinkConfirmsBeforeDelete: Bool?
        // Carried like the quicklink flags: opening a search grants no permission class.
        var webSearchEnabled: Bool?
        var webSearchShowInLauncher: Bool?
        var webSearchEngine: String?
        // Carried too: a bundle id names an app to raise, which grants no permission class.
        var herdrEnabled: Bool?
        var herdrShowInLauncher: Bool?
        var herdrTerminalBundleID: String?
        var vsCodeEnabled: Bool?
        var vsCodeShowInLauncher: Bool?
        /// Carried: a keyword is a typing preference, and grants nothing.
        var scopeKeywords: [String: String]?
        // Carried: neither is the Linear consent flag, which lives on the store and never leaves it.
        var linearShowInLauncher: Bool?
        var linearDestination: String?
    }

    /// Combos keep the legacy shape, so older files import. docs/features/hotkeys.md#persistence
    struct HotkeyBackup: Codable {
        var togglePalette: HotKeyBinding?
        var togglePaletteAlternate: HotKeyBinding?
        var toggleClipboard: HotKeyBinding?
        var toggleClipboardAlternate: HotKeyBinding?
        var toggleEmoji: HotKeyBinding?
        var searchFiles: HotKeyBinding?
        var apps: [String: HotKeyBinding]?
        var panes: [String: HotKeyBinding]?
        var customCommands: [String: HotKeyBinding]?
        var systemActions: [String: HotKeyBinding]?
        var windowCommands: [String: HotKeyBinding]?
        var quicklinks: [String: HotKeyBinding]?
    }

    /// A tally of what an import touched, for user-facing confirmation.
    struct ApplySummary {
        var settingsFields = 0
        var hotkeys = 0
        var favorites = 0
        var hiddenItems = 0
        var customCommands = 0
        var quicklinks = 0
    }
}

// MARK: - Serialization

extension SettingsBackup {
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    init(json: Data) throws {
        self = try JSONDecoder().decode(SettingsBackup.self, from: json)
    }
}
