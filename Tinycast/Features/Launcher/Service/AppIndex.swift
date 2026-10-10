import AppKit

struct AppEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case application
        case systemSettings
        case command
        case quickAction
        case customCommand
        case snippet
        case systemAction
        case windowCommand
        case windowLayout
        case windowRoom
        case quicklink
        case appleShortcut
        case webSearch
        case herdrTarget
        case vsCodeProject
        case zedProject
        case linearTarget
        case scope
        case extensionCommand
        case meeting

        var descriptor: KindDescriptor {
            switch self {
            case .application:
                return KindDescriptor(
                    label: "Application", sectionTitle: "Applications",
                    openVerb: "Open Application", canHideFromSearch: true,
                    canRevealInFinder: true, canDragOut: true, isSymbolIcon: false, rankPriority: 4)
            case .systemSettings:
                return KindDescriptor(
                    label: "System Setting", sectionTitle: "System Settings",
                    openVerb: "Open System Setting", canHideFromSearch: true,
                    canRevealInFinder: true, canDragOut: false, isSymbolIcon: false, rankPriority: 1)
            case .command:
                return KindDescriptor(
                    label: "Command", sectionTitle: "Commands",
                    openVerb: "Run Command", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .quickAction:
                return KindDescriptor(
                    label: "Quick Action", sectionTitle: "Quick Actions",
                    openVerb: "Run Quick Action", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .customCommand:
                return KindDescriptor(
                    label: "Custom Command", sectionTitle: "Custom Commands",
                    openVerb: "Run Custom Command", canHideFromSearch: false,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .snippet:
                return KindDescriptor(
                    label: "Snippet", sectionTitle: "Snippets",
                    openVerb: "Paste Snippet", canHideFromSearch: false,
                    canRevealInFinder: true, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .systemAction:
                return KindDescriptor(
                    label: "System Action", sectionTitle: "System Actions",
                    openVerb: "Run System Action", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .windowCommand:
                return KindDescriptor(
                    label: "Window Command", sectionTitle: "Window Management",
                    openVerb: "Move Window", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .windowLayout:
                return KindDescriptor(
                    label: "Window Layout", sectionTitle: "Window Layouts",
                    openVerb: "Arrange Windows", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .windowRoom:
                return KindDescriptor(
                    label: "Room", sectionTitle: "Rooms", openVerb: "Enter Room",
                    canHideFromSearch: true, canRevealInFinder: false, canDragOut: false,
                    isSymbolIcon: true, rankPriority: 3)
            case .quicklink:
                return KindDescriptor(
                    label: "Quicklink", sectionTitle: "Quicklinks",
                    openVerb: "Open Quicklink", canHideFromSearch: false,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 2)
            case .appleShortcut:
                // File-backed so every row draws the Shortcuts app's own icon.
                return KindDescriptor(
                    label: "Apple Shortcut", sectionTitle: "Apple Shortcuts",
                    openVerb: "Run Shortcut", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: false, rankPriority: 3)
            case .webSearch:
                return KindDescriptor(
                    label: "Web Search", sectionTitle: "Web Search",
                    openVerb: "Search the Web", canHideFromSearch: false,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 2)
            case .herdrTarget:
                return KindDescriptor(
                    label: "herdr", sectionTitle: "herdr",
                    openVerb: "Focus in herdr", canHideFromSearch: false,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .vsCodeProject:
                return KindDescriptor(
                    label: "VS Code", sectionTitle: "VS Code Projects",
                    openVerb: "Open in VS Code", canHideFromSearch: false,
                    canRevealInFinder: true, canDragOut: false, isSymbolIcon: false, rankPriority: 3)
            case .zedProject:
                return KindDescriptor(
                    label: "Zed", sectionTitle: "Zed Projects",
                    openVerb: "Open in Zed", canHideFromSearch: false,
                    canRevealInFinder: true, canDragOut: false, isSymbolIcon: false, rankPriority: 3)
            case .linearTarget:
                return KindDescriptor(
                    label: "Linear", sectionTitle: "Linear",
                    openVerb: "Open in Linear", canHideFromSearch: false,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .scope:
                return KindDescriptor(
                    label: "Scope", sectionTitle: "Search Scopes",
                    openVerb: "Narrow the Search", canHideFromSearch: false,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .extensionCommand:
                // The label is per-entry, the owning extension's title; this is the fallback.
                return KindDescriptor(
                    label: "Extension", sectionTitle: "Extensions",
                    openVerb: "Run Command", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .meeting:
                return KindDescriptor(
                    label: "Meeting", sectionTitle: "Meetings",
                    openVerb: "Join Meeting", canHideFromSearch: false,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 1)
            }
        }
    }

    /// Fixed per kind: a new `Kind` case fails to build until it names every field.
    struct KindDescriptor: Sendable {
        let label: String
        let sectionTitle: String
        let openVerb: String
        /// Only where Settings lists a per-item checkbox to put it back: a hide is never one-way.
        let canHideFromSearch: Bool
        let canRevealInFinder: Bool
        /// Only an application: a pane or a shortcut dropped on another app opens nothing there.
        let canDragOut: Bool
        let isSymbolIcon: Bool
        /// Breaks a full tie, apps first: Calculator over Calculator History.
        let rankPriority: Int
    }

    let id: String  // file path (or "command:…" id) — always unique
    let name: String  // clean display name, never includes ".app"
    let url: URL
    let bundleID: String?
    let kind: Kind
    /// Set when a feature pane, not this entry's category pane, lists its controls and gates it.
    var settingsOwner: SettingsTab?
    /// Secondary label beside the name, for an entry whose name alone can't say what it acts on.
    var subtitle: String?
    /// Background-refresh dot for a scheduled extension command; nil everywhere else.
    var backgroundRefresh: ExtensionRefreshState?
    /// Ranked like the name: a translation, a rename, `CFBundleAlternateNames`.
    var alternateTitles: [String] = []
    /// Per-item symbol, for the one kind whose glyph is the user's choice. Nil elsewhere.
    var symbolName: String?
    /// Set only for a scope row, which is drawn as a coloured category tile rather than a wash.
    var symbolTint: ScopeTint?
    /// Found by, never ranked by: a declared name, an extension's keywords.
    var keywords: [String] = []
    /// Moves when the bundle's icon changes on disk, retiring the cached bitmap. Applications only.
    var iconStamp: Int = 0
    /// Set by the feature that produced the entry when its glyph isn't derivable from `kind`.
    var iconOverride: EntryIcon?
    /// What this entry comes from — an extension's title. Labels the row; ranks as a subtitle.
    var ownerName: String?
    /// When it landed on disk, so a fresh install can be suggested before its first open.
    var installedAt: Date?
    /// The searchable form of every field above, built at publish by `buildSearchProfile`.
    var search = SearchProfile.unnamed

    /// Stable identity for learned ranking, favorites, and other per-entry preferences.
    var preferenceKey: String { bundleID ?? id }

    /// What this entry is called, in the shape `EntryNaming` reads.
    var naming: EntryNaming.Sources {
        var sources = EntryNaming.Sources(name: name)
        sources.alternateTitles = alternateTitles
        // The subtitle a row prints wins; the owner it replaced still finds the entry.
        sources.subtitle = subtitle ?? ownerName
        sources.keywords = keywords + (subtitle == nil ? [] : [ownerName].compactMap { $0 })
        return sources
    }

    /// Built once per index change, never per keystroke; only `AppIndex.named` calls it.
    mutating func buildSearchProfile() { search = EntryNaming.profile(for: naming) }

    /// Only a name the entry lacks adds anything; a bundle usually spells itself the same twice.
    mutating func addAlternateTitle(_ candidate: String) {
        let existing = [name] + alternateTitles
        guard !candidate.isEmpty,
            !existing.contains(where: {
                FuzzyMatch.normalized($0) == FuzzyMatch.normalized(candidate)
            })
        else { return }
        alternateTitles.append(candidate)
    }

    var kindLabel: String { ownerName ?? kind.descriptor.label }

    /// The hotkey action for this entry, or nil when the entry has no addressable action.
    var hotKeyAction: HotKeyAction? {
        switch kind {
        case .command:
            return CommandCatalog.command(for: self)?.hotKeyAction
        case .quickAction:
            if let command = CommandCatalog.command(for: self) { return command.hotKeyAction }
            return CustomQuickAction.id(fromEntryID: id).map { .quickAction(id: $0) }
        case .application:
            return bundleID.map { .app(bundleID: $0) }
        case .systemSettings:
            return bundleID.map { .settingsPane(bundleID: $0) }
        case .customCommand:
            return CustomCommand.id(fromEntryID: id).map { .customCommand(id: $0) }
        case .systemAction:
            return SystemActionCatalog.action(forEntryID: id).map { .systemAction(id: $0.id) }
        case .windowCommand:
            if let command = WindowCommandCatalog.command(forEntryID: id) {
                return .windowCommand(id: command.id)
            }
            return CustomWindowSize.id(fromEntryID: id).map { .customWindowSize(id: $0) }
        case .windowLayout:
            return WindowLayout.id(fromEntryID: id).map { .windowLayout(id: $0) }
        case .windowRoom:
            return Room.id(fromEntryID: id).map { .windowRoom(id: $0) }
        case .quicklink:
            return Quicklink.id(fromEntryID: id).map { .quicklink(id: $0) }
        case .appleShortcut:
            return AppleShortcut.id(fromEntryID: id).map { .appleShortcut(id: $0) }
        case .snippet:
            return StoredSnippet.id(fromEntryID: id).map { .snippet(id: $0) }
        // A web search needs a query; a herdr id and a project path can vanish between launches.
        case .webSearch, .herdrTarget, .vsCodeProject, .zedProject, .linearTarget, .scope,
            .extensionCommand, .meeting:
            return nil
        }
    }

    /// Synthetic entries have no file to reveal; a destination is its record's own action.
    var canRevealInFinder: Bool { kind.descriptor.canRevealInFinder }

    var canHideFromSearch: Bool { kind.descriptor.canHideFromSearch }

    var canDragOut: Bool { kind.descriptor.canDragOut }

    /// What this row draws where the entry stands for itself — Settings lists, pickers, favorites.
    @MainActor var iconSource: EntryIcon { iconOverride ?? defaultIcon }

    /// Derived from the kind alone: synthetic entries get a symbol tile, everything else its file.
    @MainActor private var defaultIcon: EntryIcon {
        guard kind.descriptor.isSymbolIcon else { return .file(stamp: iconStamp) }
        let name = symbolName ?? kindSymbol
        guard let tint = tileTint else { return .symbol(name) }
        return tile(name, tint)
    }

    /// The launcher list's answer instead: a row wears its scope's glyph as well as its colour, so
    /// results read as categories — owner's call, docs/ui.md#category-tiles. Applications are the
    /// exception: a red grid tells every app apart from every other app equally, so it is the app's
    /// own icon that carries the information — reverted, FORK.md divergence 4.
    @MainActor var categoryIconSource: EntryIcon {
        if kind == .application || kind == .systemSettings { return iconSource }
        guard let symbol = ScopeCatalog.symbol(for: kind), let tint = tileTint else {
            return iconSource
        }
        return tile(symbol, tint)
    }

    @MainActor private func tile(_ name: String, _ tint: ScopeTint) -> EntryIcon {
        .tintedSymbol(name: name, tint: SymbolTint(key: tint.rawValue, color: Theme.Colors.tile(tint)))
    }

    private var kindSymbol: String {
        switch kind {
        case .quicklink: return Quicklink.sfSymbol
        case .snippet: return "text.quote"
        case .customCommand: return CustomCommand.sfSymbol
        case .command: return CommandCatalog.command(for: self)?.sfSymbol ?? "questionmark"
        case .quickAction:
            return CommandCatalog.command(for: self)?.sfSymbol ?? CustomQuickAction.sfSymbol
        case .systemAction: return SystemActionCatalog.action(forEntryID: id)?.sfSymbol ?? "questionmark"
        case .windowCommand:
            return WindowCommandCatalog.command(forEntryID: id)?.sfSymbol
                ?? CustomWindowSize.sfSymbol
        case .webSearch:
            return WebSearchEngine.engine(id: WebSearchEngine.id(fromEntryID: id) ?? "")?.symbol
                ?? WebSearchEngine.default.symbol
        case .herdrTarget: return "macwindow"
        case .windowLayout: return WindowLayout.sfSymbol
        case .windowRoom: return Room.sfSymbol
        case .meeting: return "video.fill"
        case .application, .systemSettings, .appleShortcut, .vsCodeProject, .zedProject,
            .linearTarget, .scope, .extensionCommand:
            return "questionmark"
        }
    }

    /// A scope row's own colour, or the colour of the scope that reveals this kind — so a herdr
    /// tab and the herdr row that leads to it read as the same category. docs/ui.md#category-tiles
    @MainActor var tileTint: ScopeTint? { symbolTint ?? ScopeCatalog.tint(for: kind) }

    /// Main-actor because it subscribes the calling view; every caller is a `body`.
    @MainActor var icon: NSImage {
        IconCache.observeStyle()
        return IconCache.icon(for: iconSource, fileURL: url)
    }

    /// Icon identity for a row's async load: re-skinning changes the glyph while `id` stays put.
    @MainActor var iconKey: String { "\(id)|\(iconSource)" }
}

extension AppEntry {
    /// The one row a web search engine draws, including when Google is offered as a fallback.
    init(_ webSearchEngine: WebSearchEngine) {
        self.init(
            id: webSearchEngine.entryID, name: webSearchEngine.name,
            url: URL(string: "tinycast://web-search/" + webSearchEngine.id)!,
            bundleID: nil, kind: .webSearch, symbolName: webSearchEngine.symbol)
    }

    /// The one row a layout draws, wherever it is offered from.
    init(_ layout: WindowLayout) {
        self.init(
            id: layout.entryID, name: layout.name,
            url: URL(string: "tinycast://window-layout/" + layout.id.uuidString)!,
            bundleID: nil, kind: .windowLayout, symbolName: layout.iconSymbol)
    }

    init(_ room: Room) {
        self.init(
            id: room.entryID, name: room.name,
            url: URL(string: "tinycast://window-room/" + room.id.uuidString)!,
            bundleID: nil, kind: .windowRoom)
    }

    init(_ command: WindowCommand) {
        self.init(
            id: command.entryID, name: command.name,
            url: URL(string: "tinycast://window-command/" + command.id.rawValue)!,
            bundleID: nil, kind: .windowCommand)
    }

    /// A custom size shares the window commands' kind and section, as custom Quick Actions do.
    init(_ size: CustomWindowSize) {
        self.init(
            id: size.entryID, name: size.name,
            url: URL(string: "tinycast://window-size/" + size.id.uuidString)!,
            bundleID: nil, kind: .windowCommand)
    }

    /// The one row a custom Quick Action draws, wherever it is offered from.
    init(_ action: CustomQuickAction) {
        self.init(
            id: action.entryID, name: action.name,
            url: URL(string: "tinycast://quick-action/" + action.id.uuidString)!,
            bundleID: nil, kind: .quickAction, symbolName: action.iconSymbol)
    }

    /// The one row a custom command draws, wherever it is offered from.
    init(_ command: CustomCommand) {
        self.init(
            id: command.entryID, name: command.name,
            url: URL(string: "tinycast://custom-command/" + command.id.uuidString)!,
            bundleID: nil, kind: .customCommand, symbolName: command.iconSymbol)
    }

    /// The one row a quicklink draws, wherever it is offered from.
    init(_ quicklink: Quicklink) {
        self.init(
            id: quicklink.entryID, name: quicklink.name,
            url: URL(string: "tinycast://quicklink/" + quicklink.id.uuidString)!,
            bundleID: nil, kind: .quicklink,
            symbolName: quicklink.iconSymbol
                ?? QuicklinkDestination.detect(quicklink.link)?.defaultSymbol)
    }

    /// No bundle id: that would key every shortcut's alias and ranking to the Shortcuts app.
    init(_ shortcut: AppleShortcut, applicationURL: URL) {
        self.init(
            id: shortcut.entryID, name: shortcut.name, url: applicationURL, bundleID: nil,
            kind: .appleShortcut)
    }
}

extension AppEntry.Kind {
    private static let byCategoryName: [String: AppEntry.Kind] = allCases.reduce(into: [:]) {
        $0[FuzzyMatch.normalized($1.descriptor.sectionTitle)] = $1
        $0[FuzzyMatch.normalized($1.descriptor.label)] = $1
    }

    private static let categoryNames = allCases.map { kind in
        (kind, [kind.descriptor.sectionTitle, kind.descriptor.label].map(FuzzyMatch.Candidate.init))
    }

    static func named(by query: LauncherOrder.CategoryQuery) -> AppEntry.Kind? {
        byCategoryName[query.name]
    }

    static func matching(by query: LauncherOrder.CategoryQuery) -> Set<AppEntry.Kind> {
        if let kind = named(by: query) { return [kind] }
        return Set(
            categoryNames.compactMap { kind, names in
                names.contains(where: query.matches) ? kind : nil
            })
    }
}

@MainActor
@Observable
final class AppIndex {
    private(set) var apps: [AppEntry] = []

    private var snippetEntries: [AppEntry] = []

    /// The launcher's rows in order, with the size of each leading section at their head.
    struct Results: Equatable {
        var entries: [AppEntry] = []
        var favoriteCount = 0
        var meetingCount = 0
        var suggestionCount = 0
        var matchCount = 0
    }

    private struct MatchKey: Equatable {
        let query: String
        let limit: Int
        let entriesRevision: Int
        let rankingRevision: Int
        let aliasRevision: Int
        let sensitivity: SearchSensitivity
    }

    private struct ResultsKey: Equatable {
        let match: MatchKey
        let visibilityRevision: Int
        let favoritesRevision: Int
        let hotKeysRevision: Int
        let showsSuggestions: Bool
        /// Suggestions and usage order age with the clock, which no revision tracks.
        let minute: Int
        /// Part of the key, or a scoped query would be served the previous unscoped result set.
        let scopeID: String?
        let additionalEntries: [AppEntry]
    }

    /// Repeated renders for the same query reuse the ranking instead of re-matching every frame.
    @ObservationIgnored private var matchMemo = Memo<MatchKey, Results>()
    @ObservationIgnored private var resultsMemo = Memo<ResultsKey, Results>()
    /// Bumped whenever `apps` changes, so both memos above name the entry set they were built from.
    private var entriesRevision = 0

    private static let systemActionEntries: [AppEntry] = SystemActionCatalog.all
        .map { command in
            AppEntry(
                id: command.entryID, name: command.name,
                url: URL(string: "tinycast://system-action/" + command.id.rawValue)!,
                bundleID: nil, kind: .systemAction)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private static let allWindowCommandEntries: [AppEntry] = WindowCommandCatalog.all
        .map(AppEntry.init)
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private var discoveredEntries: [AppEntry] = []
    private var customCommandEntries: [AppEntry] = []
    private var windowCommandEntries: [AppEntry] = []
    private var customWindowSizeEntries: [AppEntry] = []
    private var windowLayoutEntries: [AppEntry] = []
    private var windowRoomEntries: [AppEntry] = []
    private var quicklinkEntries: [AppEntry] = []
    private var appleShortcutEntries: [AppEntry] = []
    private var webSearchEntries: [AppEntry] = []
    private var herdrEntries: [AppEntry] = []
    private var vsCodeEntries: [AppEntry] = []
    private var zedEntries: [AppEntry] = []
    private var linearEntries: [AppEntry] = []
    private var scopeEntries: [AppEntry] = []
    private var customQuickActionEntries: [AppEntry] = []
    private var extensionEntries: [AppEntry] = []
    private var meetingEntries: [AppEntry] = []
    /// The catalog's commands a disabled feature hides; the Commands slice is recomputed from it.
    private var hiddenCommands: Set<CommandID> = []
    /// Kept out of launcher search by a "Show in launcher" switch, yet still runnable by shortcut.
    private var unlistedCommands: Set<CommandID> = []
    private var nameCache = BundleNameCache()
    private var paneCache: SettingsPaneScanner.Cache?
    private var isRefreshing = false
    /// Set when a refresh lands mid-scan, so a scope edit is never silently dropped.
    private var refreshPending = false
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private var settings: AppSettings?
    /// Fired after every scan, even an unchanged one: LaunchServices can trail a deletion by seconds.
    @ObservationIgnored var onScan: (() -> Void)?

    init(ranking: LauncherRankingStore, aliases: AliasStore) {
        self.ranking = ranking
        self.aliases = aliases
    }

    /// The always-relevant built-ins, plus whatever a disabled feature has not hidden.
    private var commandEntries: [AppEntry] {
        visibleCatalogEntries.filter { $0.kind == .command }
    }

    private var quickActionEntries: [AppEntry] {
        visibleCatalogEntries.filter { $0.kind == .quickAction } + customQuickActionEntries
    }

    private var visibleCatalogEntries: [AppEntry] {
        CommandCatalog.all.filter {
            guard let command = CommandCatalog.command(for: $0) else { return true }
            return !hiddenCommands.contains(command) && !unlistedCommands.contains(command)
        }
    }

    /// Whether the feature behind a command is on, which is what its shortcut has to obey too.
    func isCommandEnabled(_ command: CommandID) -> Bool {
        !hiddenCommands.contains(command)
    }

    /// A feature's commands leave the Commands slice when it is off; `visible` restores them.
    func setCommandsVisible(_ commands: Set<CommandID>, _ visible: Bool) {
        let updated = visible ? hiddenCommands.subtracting(commands) : hiddenCommands.union(commands)
        guard updated != hiddenCommands else { return }
        hiddenCommands = updated
        publishEntries()
    }

    func setCommandsListed(_ commands: Set<CommandID>, _ listed: Bool) {
        let updated =
            listed ? unlistedCommands.subtracting(commands) : unlistedCommands.union(commands)
        guard updated != unlistedCommands else { return }
        unlistedCommands = updated
        publishEntries()
    }

    /// Replaces the command slice without rescanning, so Settings edits land at once.
    func setCustomCommands(_ commands: [CustomCommand]) {
        let entries = commands.filter { $0.isEnabled && $0.showsInRootSearch }.map(AppEntry.init)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard entries != customCommandEntries else { return }
        customCommandEntries = entries
        publishEntries()
    }

    /// Replaces the custom Quick Action slice, which shares its section with the shipped four.
    func setCustomQuickActions(_ actions: [CustomQuickAction]) {
        let entries = actions.sorted(by: CustomQuickAction.precedes).map(AppEntry.init)
        guard entries != customQuickActionEntries else { return }
        customQuickActionEntries = entries
        publishEntries()
    }

    /// Replaces the quicklink slice; a toggle can't split its entries from their section.
    func setQuicklinks(_ quicklinks: [Quicklink]) {
        let entries =
            quicklinks
            .filter { $0.isEnabled && $0.showsInRootSearch }
            .sorted(by: Quicklink.precedes)
            .map(AppEntry.init)
        guard entries != quicklinkEntries else { return }
        quicklinkEntries = entries
        publishEntries()
    }

    /// Discovered from the Shortcuts app, so it arrives already built and sorted.
    func setAppleShortcuts(_ entries: [AppEntry]) {
        guard entries != appleShortcutEntries else { return }
        appleShortcutEntries = entries
        publishEntries()
    }

    /// Events move on their own, so this comes from the store's change hook, not an edit.
    func setMeetings(_ entries: [AppEntry]) {
        guard entries != meetingEntries else { return }
        meetingEntries = entries
        publishEntries()
    }

    /// Called by `ExtensionManager` when the installed set or a chosen appearance changes.
    func setExtensionCommands(_ entries: [AppEntry]) {
        guard entries != extensionEntries else { return }
        extensionEntries = entries
        publishEntries()
    }

    /// Whether any published entry belongs to one of these kinds.
    func hasEntries(ofAnyKind kinds: Set<AppEntry.Kind>) -> Bool {
        apps.contains { kinds.contains($0.kind) }
    }

    /// The keywords, as rows. Activating one arms the scope instead of opening anything, which is
    /// why they lead the empty query: they are the map of what the launcher can be narrowed to.
    func setScopes(_ definitions: [ScopeDefinition]) {
        let entries = definitions.map { definition in
            AppEntry(
                id: definition.id, name: definition.title,
                url: URL(string: "tinycast://scope/" + definition.id)!,
                bundleID: nil, kind: .scope,
                // So typing the letter finds its own row, the way typing it and a space would arm it.
                alternateTitles: definition.keyword.isEmpty ? [] : [definition.keyword],
                symbolName: definition.symbol, symbolTint: definition.tint)
        }
        guard entries != scopeEntries else { return }
        scopeEntries = entries
        publishEntries()
    }

    /// Replaces the Linear slice. Empty without consent, which the store enforces rather than this.
    func setLinearTargets(_ views: [LinearTarget]) {
        let entries = Self.linearEntries(for: views)
        guard entries != linearEntries else { return }
        linearEntries = entries
        publishEntries()
    }

    /// Maps cached destinations and transient ticket results into the launcher's shared row shape.
    static func linearEntries(for targets: [LinearTarget]) -> [AppEntry] {
        targets.map { target in
            AppEntry(
                id: target.entryID, name: target.displayName,
                url: URL(string: "tinycast://linear/" + target.kind.rawValue)!,
                bundleID: nil, kind: .linearTarget,
                // Workspace, title and issue identifier should each retrieve the same destination.
                subtitle: target.displaySubtitle,
                alternateTitles: [target.workspaceURLKey, target.name]
                    + [target.issueDetails?.identifier].compactMap { $0 },
                symbolName: target.symbol)
        }
    }

    /// Replaces the VS Code slice, already ordered most recently opened first — that order is the
    /// feature, so these entries deliberately keep it rather than sorting by name.
    func setVSCodeProjects(_ projects: [VSCodeProject]) {
        let entries = projects.map { project in
            AppEntry(
                id: project.entryID, name: project.name, url: URL(filePath: project.path),
                bundleID: nil, kind: .vsCodeProject,
                // So a query naming the parent folder finds the project inside it.
                alternateTitles: [project.displayPath])
        }
        guard entries != vsCodeEntries else { return }
        vsCodeEntries = entries
        publishEntries()
    }

    /// Replaces the Zed slice, already ordered most recently opened first.
    func setZedProjects(_ projects: [ZedProject]) {
        let entries = projects.map { project in
            AppEntry(
                id: project.entryID, name: project.name, url: URL(filePath: project.paths[0]),
                bundleID: nil, kind: .zedProject,
                // Every root and parent should find the workspace that Zed opens together.
                alternateTitles: project.paths + project.displayPaths)
        }
        guard entries != zedEntries else { return }
        zedEntries = entries
        publishEntries()
    }

    /// Replaces the herdr slice. Unlike the others this changes between palette opens, because the
    /// session it mirrors does; an empty array is how "herdr isn't running" arrives.
    func setHerdrTargets(_ targets: [HerdrTarget]) {
        let entries = targets.map { target in
            AppEntry(
                id: target.entryID, name: target.displayName,
                url: URL(string: "tinycast://herdr/tab")!,
                bundleID: nil, kind: .herdrTarget,
                // So "working" or "focused" finds the row that is, without touching the name.
                alternateTitles: [
                    target.status.isNoteworthy ? target.status.rawValue : nil,
                    target.focused ? "focused" : nil,
                    target.workspaceLabel
                ].compactMap { $0 },
                symbolName: "macwindow")
        }
        guard entries != herdrEntries else { return }
        herdrEntries = entries
        publishEntries()
    }

    /// Shows or hides the web-search slice; the engines themselves are static.
    func setWebSearchVisible(_ visible: Bool) {
        let entries = visible ? WebSearchEngine.builtIn.map(AppEntry.init) : []
        guard entries != webSearchEntries else { return }
        webSearchEntries = entries
        publishEntries()
    }

    /// Shows or hides the window-command slice; the catalog itself is static.
    func setWindowCommandsVisible(_ visible: Bool) {
        let entries = visible ? Self.allWindowCommandEntries : []
        guard entries != windowCommandEntries else { return }
        windowCommandEntries = entries
        publishEntries()
    }

    /// Replaces the custom-size slice, which shares its section with the window commands.
    func setCustomWindowSizes(_ sizes: [CustomWindowSize]) {
        let entries = sizes.sorted(by: CustomWindowSize.precedes).map(AppEntry.init)
        guard entries != customWindowSizeEntries else { return }
        customWindowSizeEntries = entries
        publishEntries()
    }

    /// Replaces the layout slice; a toggle can't split its entries from their section.
    func setWindowLayouts(_ layouts: [WindowLayout]) {
        let entries = layouts.sorted(by: WindowLayout.precedes).map(AppEntry.init)
        guard entries != windowLayoutEntries else { return }
        windowLayoutEntries = entries
        publishEntries()
    }

    /// Replaces the room slice, which publishes between the layouts and the window commands.
    func setWindowRooms(_ rooms: [Room]) {
        let entries = rooms.sorted(by: Room.precedes).map(AppEntry.init)
        guard entries != windowRoomEntries else { return }
        windowRoomEntries = entries
        publishEntries()
    }

    func updateSnippets(_ records: [StoredSnippet]) {
        let entries =
            records
            .filter { $0.snippet.isEnabled }
            .map { record in
                AppEntry(
                    id: record.entryID,
                    name: record.snippet.name,
                    url: record.fileURL,
                    bundleID: nil,
                    kind: .snippet,
                    alternateTitles: [record.snippet.keyword].compactMap { $0 })
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard entries != snippetEntries else { return }
        snippetEntries = entries
        publishEntries()
    }

    /// Wires the scopes, re-indexing on edit rather than waiting for the next open.
    func start(settings: AppSettings) {
        self.settings = settings
        observeSearchScopes()
    }

    /// Fires synchronously on main before the write lands, so the task re-arms, then rescans.
    private func observeSearchScopes() {
        withObservationTracking {
            _ = settings?.searchScopes
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeSearchScopes()
                await self.refresh()
            }
        }
    }

    /// Re-scan on every open; reopens collapse, and an unchanged set does no UI work.
    func refresh() async {
        guard !isRefreshing else {
            refreshPending = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshPending = false
            let scopes = settings?.searchScopes ?? SearchScopes.defaults
            let reusingPanes = paneCache
            let languages = BundleLocalization.indexedLanguages(Locale.preferredLanguages)
            let reusing = BundleNameCache(reusing: nameCache, languages: languages)
            let (found, cache, panes) = await Task.detached(priority: .utility) {
                AppIndex.scan(
                    scopes: scopes, languages: languages, cache: reusing, paneCache: reusingPanes)
            }.value
            nameCache = cache
            paneCache = panes
            guard found != discoveredEntries else { continue }
            discoveredEntries = found
            publishEntries()
        } while refreshPending
        onScan?()
    }

    /// Out of the index *and* unknown to LaunchServices, so dropping a search scope isn't a delete.
    func isUninstalled(bundleID: String) -> Bool {
        !discoveredEntries.contains { $0.kind == .application && $0.bundleID == bundleID }
            && NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) == nil
    }

    nonisolated private static func scan(
        scopes: [String], languages: [String], cache: BundleNameCache,
        paneCache: SettingsPaneScanner.Cache?
    ) -> ([AppEntry], BundleNameCache, SettingsPaneScanner.Cache?) {
        Signposts.interval("AppIndex.scan") {
            var cache = cache
            var indexByBundleID: [String: Int] = [:]
            var result: [AppEntry] = []
            for url in SearchScopes.appBundles(in: scopes) {
                let bundle = Bundle(url: url)
                let bundleID = bundle?.bundleIdentifier
                let fileName = EntryNaming.strippingAppExtension(url.lastPathComponent)
                // Dedup by bundle id; the first scope wins, but a renamed copy lends its name.
                if let bundleID, let first = indexByBundleID[bundleID] {
                    result[first].addAlternateTitle(fileName)
                    continue
                }

                // Finder's rule: LaunchServices ignores a display name the file name contradicts.
                let names = cache.names(
                    for: url, base: fileName, developmentRegion: bundle?.developmentLocalization)
                // Raw: Calendar's strings file swaps its `iCal` array for a name.
                let alternates = bundle?.infoDictionary?["CFBundleAlternateNames"] as? [String] ?? []
                // Still searchable, never the label: `code` must keep finding Visual Studio Code.
                let declared = [bundle?.installedAppName].compactMap { $0 }
                var entry = AppEntry(
                    id: url.path, name: names.first ?? fileName, url: url, bundleID: bundleID,
                    kind: .application, alternateTitles: Array(names.dropFirst()) + alternates,
                    keywords: declared, iconStamp: FileIconStamp.value(for: url),
                    installedAt: try? url.resourceValues(forKeys: [.addedToDirectoryDateKey])
                        .addedToDirectoryDate)
                entry.addAlternateTitle(fileName)
                if let bundleID { indexByBundleID[bundleID] = result.count }
                result.append(entry)
            }
            // Slice order is section order, so the flat selection maps 1:1 onto rows.
            let apps = result.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            // Settings panes are `.appex` bundles, which carry no Spotlight alternate names.
            let (panes, panesCache) = SettingsPaneScanner.scan(languages: languages, cache: paneCache)
            // Named here, not at publish: romanizing a CJK index is ~50 ms of main-actor time.
            return (AppIndex.named(apps + panes), cache, panesCache)
        }
    }

    /// The searchable form of every name an entry carries. `scan` names the app slice itself.
    nonisolated private static func named(_ entries: [AppEntry]) -> [AppEntry] {
        entries.map { entry in
            var entry = entry
            entry.buildSearchProfile()
            return entry
        }
    }

    private func publishEntries() {
        // Each slice arrives in its own display order; the slice order is the section order.
        let updated =
            Self.named(scopeEntries + meetingEntries) + discoveredEntries
            + Self.named(
                extensionEntries + quicklinkEntries + appleShortcutEntries + vsCodeEntries + zedEntries
                    + herdrEntries + linearEntries + webSearchEntries + snippetEntries
                    + Self.systemActionEntries + windowLayoutEntries + windowRoomEntries
                    + windowCommandEntries
                    + customWindowSizeEntries + customCommandEntries + quickActionEntries
                    + commandEntries)
        guard updated != apps else { return }
        apps = updated
        entriesRevision &+= 1
    }

    func matches(_ query: String, limit: Int = 200) -> [AppEntry] {
        searchResults(query, limit: limit).entries
    }

    /// Ranked matches lead so Return still opens the best one; a started category only appends.
    private func searchResults(_ query: String, limit: Int = 200) -> Results {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Results(entries: apps) }
        return matchMemo.value(for: matchKey(q, limit: limit)) {
            let category = LauncherOrder.CategoryQuery(q)
            if let kind = AppEntry.Kind.named(by: category) {
                return Results(entries: categoryListing(kind, query: category.name))
            }
            let ranked = rank(q, limit: limit)
            let listed = categoryRemainder(AppEntry.Kind.matching(by: category), excluding: ranked)
            return Results(entries: ranked + listed, matchCount: ranked.count)
        }
    }

    /// Slice order is section order, so filtering keeps sections and selection aligned.
    private func categoryListing(_ kind: AppEntry.Kind, query: String) -> [AppEntry] {
        let listed = apps.filter {
            $0.kind == kind || FuzzyMatch.normalized($0.name) == query
        }
        return byUsage(listed, usage: ranking.snapshot())
    }

    private func categoryRemainder(
        _ kinds: Set<AppEntry.Kind>, excluding ranked: [AppEntry]
    ) -> [AppEntry] {
        guard !kinds.isEmpty else { return [] }
        let matched = Set(ranked.map(\.id))
        let listed = apps.filter { kinds.contains($0.kind) && !matched.contains($0.id) }
        return byUsage(listed, usage: ranking.snapshot())
    }

    /// The launcher's rows: ranked matches, or favorites, suggestions and each kind by usage.
    func orderedResults(
        query: String, visibility: VisibilityStore, favorites: FavoritesStore, hotKeys: HotKeyManager,
        scope: ScopeDefinition? = nil, kinds: Set<AppEntry.Kind>? = nil,
        additionalEntries: [AppEntry] = []
    ) -> Results {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let showsSuggestions = settings?.launcherShowsSuggestions ?? true
        let usage = ranking.snapshot()
        let key = ResultsKey(
            match: matchKey(q, limit: 200), visibilityRevision: visibility.revision,
            favoritesRevision: favorites.revision, hotKeysRevision: hotKeys.revision,
            showsSuggestions: showsSuggestions, minute: Int(usage.now.timeIntervalSince1970 / 60),
            scopeID: scope?.id, additionalEntries: additionalEntries)
        return resultsMemo.value(for: key) {
            // Filtering stays downstream of `matches` so that memo is never keyed on hidden state.
            let matched =
                additionalEntries.isEmpty || AppEntry.Kind.named(by: LauncherOrder.CategoryQuery(q)) != nil
                ? searchResults(q) : rankedResults(q, additionalEntries: additionalEntries)
            let shows = { (entry: AppEntry) in
                visibility.isVisible(entry) && (kinds?.contains(entry.kind) ?? true)
            }
            let visible = matched.entries.filter(shows)
            // A scope is the whole point of the query; favorites would only dilute it.
            guard q.isEmpty, kinds == nil else {
                let matchCount = matched.entries.prefix(matched.matchCount).count(where: shows)
                return Results(entries: visible, matchCount: matchCount)
            }
            let split = favorites.ordered(visible)
            let suggested =
                showsSuggestions ? suggestions(from: split.rest, usage: usage, hotKeys: hotKeys) : []
            let shown = Set(suggested.map(\.id))
            let rest = byUsage(split.rest.filter { !shown.contains($0.id) }, usage: usage)
            // Above Suggestions: a meeting is worth opening only until it ends.
            let meetings = rest.filter { $0.kind == .meeting }
            return Results(
                entries: split.favorites + meetings + suggested + rest.filter { $0.kind != .meeting },
                favoriteCount: split.favorites.count, meetingCount: meetings.count,
                suggestionCount: suggested.count)
        }
    }

    private var sensitivity: SearchSensitivity { settings?.rootSearchSensitivity ?? .default }

    private func matchKey(_ query: String, limit: Int) -> MatchKey {
        MatchKey(
            query: query, limit: limit, entriesRevision: entriesRevision, rankingRevision: ranking.revision,
            aliasRevision: aliases.revision, sensitivity: sensitivity)
    }

    /// Unmemoized: transient rows, such as Linear's ticket hits, ranked alongside the index.
    private func rankedResults(_ q: String, additionalEntries: [AppEntry]) -> Results {
        let ranked = rank(q, limit: 200, additionalEntries: additionalEntries)
        return Results(entries: ranked, matchCount: ranked.count)
    }

    private func rank(_ q: String, limit: Int, additionalEntries: [AppEntry] = []) -> [AppEntry] {
        Signposts.interval("AppIndex.rank") {
            let usage = ranking.snapshot()
            let additionalIDs = Set(additionalEntries.map(\.id))
            let entries =
                additionalEntries.isEmpty
                ? apps : apps.filter { !additionalIDs.contains($0.id) } + Self.named(additionalEntries)
            return LauncherOrder.ranked(
                entries, query: LauncherOrder.Query(q), sensitivity: sensitivity, limit: limit,
                profile: \.search, signals: { self.signals(for: $0, usage: usage) })
        }
    }

    private func byUsage(_ entries: [AppEntry], usage: LauncherRankingStore.Snapshot) -> [AppEntry] {
        var ordered: [AppEntry] = []
        ordered.reserveCapacity(entries.count)
        var start = entries.startIndex
        while start < entries.endIndex {
            let kind = entries[start].kind
            let end = entries[start...].firstIndex { $0.kind != kind } ?? entries.endIndex
            if kind == .meeting {
                ordered.append(contentsOf: entries[start..<end])
            } else {
                ordered += LauncherOrder.byUsage(
                    Array(entries[start..<end]), signals: { self.signals(for: $0, usage: usage) })
            }
            start = end
        }
        return ordered
    }

    /// Meetings keep their own card, AI is never pushed, and Tinycast opening Tinycast goes nowhere.
    private func suggestions(
        from entries: [AppEntry], usage: LauncherRankingStore.Snapshot, hotKeys: HotKeyManager
    ) -> [AppEntry] {
        let eligible = entries.filter {
            $0.kind != .meeting && $0.settingsOwner != .ai
                && !($0.bundleID?.hasPrefix(Self.ownBundlePrefix) ?? false)
        }
        return LauncherSuggestions.select(from: eligible, now: usage.now) { entry in
            // `hotKeyAction` is nil for an extension command, whose shortcut is keyed by entry ID.
            let action: HotKeyAction? =
                entry.kind == .extensionCommand ? .extensionCommand(entryID: entry.id) : entry.hotKeyAction
            return LauncherSuggestions.Traits(
                signals: signals(for: entry, usage: usage), installedAt: entry.installedAt,
                hasHotKey: action.flatMap(hotKeys.binding(for:)) != nil,
                priority: CommandCatalog.command(for: entry)?.suggestionPriority)
        }
    }

    private static let ownBundlePrefix = "com.belesky.tinycast"  // FORK.md: the fork's bundle ids

    private func signals(
        for entry: AppEntry, usage: LauncherRankingStore.Snapshot
    ) -> LauncherOrder.Signals {
        LauncherOrder.Signals(
            alias: aliases.alias(for: entry.preferenceKey).map { SearchText($0, transliterated: false) },
            usage: usage.usage(for: entry.preferenceKey),
            priority: entry.kind.descriptor.rankPriority, title: entry.name,
            boostedTerms: CommandCatalog.command(for: entry)?.boostedTerms ?? [])
    }
}
