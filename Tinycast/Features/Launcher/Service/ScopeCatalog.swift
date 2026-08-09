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
    static let emoji = "scope:emoji"
    static let clipboard = "scope:clipboard"

    /// Keywords are single letters on purpose: a scope is typed constantly and abandoned instantly.
    private static let filters: [Entry] = [
        Entry(
            definition: ScopeDefinition(
                keyword: "a", id: applications, title: "Applications", symbol: "square.grid.2x2"),
            target: .kinds([.application, .systemSettings])),
        Entry(
            definition: ScopeDefinition(
                keyword: "q", id: quicklinks, title: "Quicklinks", symbol: Quicklink.sfSymbol),
            target: .kinds([.quicklink])),
        Entry(
            definition: ScopeDefinition(
                keyword: "s", id: snippets, title: "Snippets", symbol: "text.quote"),
            target: .kinds([.snippet])),
        Entry(
            definition: ScopeDefinition(
                keyword: "c", id: commands, title: "Commands", symbol: "terminal"),
            target: .kinds([.command, .customCommand])),
        Entry(
            definition: ScopeDefinition(
                keyword: "w", id: windowManagement, title: "Window Management",
                symbol: "macwindow.on.rectangle"),
            target: .kinds([.windowCommand, .systemAction]))
    ]

    private static let modes: [Entry] = [
        Entry(
            definition: ScopeDefinition(
                keyword: "e", id: emoji, title: "Emoji & Symbols", symbol: "face.smiling"),
            target: .mode(.emoji)),
        Entry(
            definition: ScopeDefinition(
                keyword: "v", id: clipboard, title: "Clipboard", symbol: "doc.on.doc"),
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
    static func scope(for engine: WebSearchEngine) -> ScopeDefinition {
        webEntry(engine).definition
    }

    /// Only the scopes that can currently do something: a disabled feature offers no keyword.
    static func registry(settings: AppSettings) -> [ScopeDefinition] {
        entries(settings: settings).map(\.definition)
    }

    static func target(for scope: ScopeDefinition, settings: AppSettings) -> ScopeTarget? {
        entries(settings: settings).first { $0.definition.id == scope.id }?.target
    }

    private static func entries(settings: AppSettings) -> [Entry] {
        var live = filters.filter { entry in
            switch entry.definition.id {
            case quicklinks: return settings.quicklinksEnabled
            case snippets: return settings.snippetsShowInLauncher
            case commands: return settings.customCommandsEnabled
            case windowManagement: return settings.windowManagementEnabled
            default: return true
            }
        }
        live += modes
        if settings.webSearchEnabled { live += WebSearchEngine.builtIn.map(webEntry) }
        return live
    }
}
