import Foundation

/// What a scope id points at. `QueryScope` can't name these — `AppEntry.Kind` and `PaletteMode`
/// both live in AppKit-importing files — which is why the grammar stays id-only.
enum ScopeTarget: Equatable, Sendable {
    /// Narrows the launcher's own list. A set, because one section can span two kinds.
    case kinds(Set<AppEntry.Kind>)
    /// Switches screen instead of filtering; that screen carries its own header, so no chip.
    case mode(PaletteMode)
    case webSearch(WebSearchEngine)
}

/// The scope registry: keyword → id → target. See docs/features/palette.md#scope-keywords.
@MainActor
enum ScopeCatalog {
    private struct Entry {
        let definition: ScopeDefinition
        let target: ScopeTarget
    }

    static let applications = "scope:applications"
    static let quicklinks = "scope:quicklinks"
    static let snippets = "scope:snippets"
    static let commands = "scope:commands"
    static let windowManagement = "scope:window-management"
    static let herdr = "scope:herdr"
    static let vsCode = "scope:vscode"
    static let linear = "scope:linear"
    static let emoji = "scope:emoji"
    static let clipboard = "scope:clipboard"

    /// Keywords are single letters on purpose: a scope is typed constantly and abandoned instantly.
    private static let filters: [Entry] = [
        Entry(
            definition: ScopeDefinition(
                keyword: "a", id: applications, title: "Applications", symbol: "square.grid.2x2", tint: .blue),
            target: .kinds([.application, .systemSettings])),
        Entry(
            definition: ScopeDefinition(
                keyword: "q", id: quicklinks, title: "Quicklinks", symbol: Quicklink.sfSymbol, tint: .green),
            target: .kinds([.quicklink])),
        Entry(
            definition: ScopeDefinition(
                keyword: "s", id: snippets, title: "Snippets", symbol: "text.quote", tint: .orange),
            target: .kinds([.snippet])),
        Entry(
            definition: ScopeDefinition(
                keyword: "c", id: commands, title: "Commands", symbol: "terminal", tint: .purple),
            target: .kinds([.command, .customCommand])),
        Entry(
            definition: ScopeDefinition(
                keyword: "w", id: windowManagement, title: "Window Management",
                symbol: "macwindow.on.rectangle", tint: .teal),
            target: .kinds([.windowCommand, .systemAction])),
        Entry(
            definition: ScopeDefinition(
                keyword: "h", id: herdr, title: "herdr", symbol: "macwindow", tint: .brown),
            target: .kinds([.herdrTarget])),
        Entry(
            definition: ScopeDefinition(
                keyword: "p", id: vsCode, title: "VS Code",
                symbol: "chevron.left.forwardslash.chevron.right", tint: .indigo),
            target: .kinds([.vsCodeProject])),
        Entry(
            definition: ScopeDefinition(
                keyword: "l", id: linear, title: "Linear", symbol: "line.3.horizontal.decrease.circle",
                tint: .pink),
            target: .kinds([.linearTarget]))
    ]

    private static let modes: [Entry] = [
        Entry(
            definition: ScopeDefinition(
                keyword: "e", id: emoji, title: "Emoji & Symbols", symbol: "face.smiling", tint: .mint),
            target: .mode(.emoji)),
        Entry(
            definition: ScopeDefinition(
                keyword: "v", id: clipboard, title: "Clipboard", symbol: "doc.on.doc", tint: .slate),
            target: .mode(.clipboard))
    ]

    private static func webEntry(_ engine: WebSearchEngine) -> Entry {
        Entry(
            definition: ScopeDefinition(
                keyword: engine.keyword, id: "scope:" + engine.entryID, title: engine.name,
                symbol: engine.symbol),
            target: .webSearch(engine))
    }

    /// The scope a named engine arms when it is activated from a row rather than typed.
    static func scope(for engine: WebSearchEngine, settings: AppSettings) -> ScopeDefinition {
        let id = "scope:" + engine.entryID
        return allDefinitions(settings: settings).first { $0.id == id }
            ?? webEntry(engine).definition
    }

    /// The scopes that earn a launcher row. A search engine is left out because it already has one
    /// of its own, which arms the same scope — two rows for one thing would be a lie about the list.
    static func launcherDefinitions(settings: AppSettings) -> [ScopeDefinition] {
        entries(settings: settings).compactMap { entry in
            if case .webSearch = entry.target { return nil }
            return entry.definition
        }
    }

    static func definition(id: String, settings: AppSettings) -> ScopeDefinition? {
        allDefinitions(settings: settings).first { $0.id == id }
    }

    /// Only the scopes that can currently do something: a disabled feature offers no keyword.
    static func registry(settings: AppSettings) -> [ScopeDefinition] {
        entries(settings: settings).map(\.definition)
    }

    static func target(for scope: ScopeDefinition, settings: AppSettings) -> ScopeTarget? {
        entries(settings: settings).first { $0.definition.id == scope.id }?.target
    }

    /// Declaration order, which is also the order a keyword collision is settled in.
    private static var allEntries: [Entry] {
        filters + modes + WebSearchEngine.builtIn.map(webEntry)
    }

    /// Every scope, enabled or not, carrying the keyword the user actually chose. Settings edits
    /// against this rather than `registry`: a keyword taken by a switched-off feature is still taken.
    static func allDefinitions(settings: AppSettings) -> [ScopeDefinition] {
        ScopeKeywords.resolve(allEntries.map(\.definition), overrides: settings.scopeKeywords)
    }

    /// What the scope ships with, so the field can drop an override that merely restores it.
    static func defaultKeyword(id: String) -> String {
        allEntries.first { $0.definition.id == id }?.definition.keyword ?? ""
    }

    static func title(id: String) -> String {
        allEntries.first { $0.definition.id == id }?.definition.title ?? ""
    }

    private static func entries(settings: AppSettings) -> [Entry] {
        zip(allEntries, allDefinitions(settings: settings)).compactMap { entry, definition in
            guard isLive(entry.definition.id, settings: settings) else { return nil }
            return Entry(definition: definition, target: entry.target)
        }
    }

    private static func isLive(_ id: String, settings: AppSettings) -> Bool {
        switch id {
        case quicklinks: return settings.quicklinksEnabled
        // `snippetsEnabled` is the keystroke-listening consent and ships off, so the
        // show-in-launcher flag alone would offer a scope for a feature that is not running.
        case snippets: return settings.snippetsEnabled && settings.snippetsShowInLauncher
        case commands: return settings.customCommandsEnabled
        case windowManagement: return settings.windowManagementEnabled
        case herdr: return settings.herdrEnabled
        case vsCode: return settings.vsCodeEnabled
        case linear: return settings.linearShowInLauncher
        default:
            return id.hasPrefix("scope:" + WebSearchEngine.entryIDPrefix)
                ? settings.webSearchEnabled : true
        }
    }
}
