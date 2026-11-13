import SwiftUI

/// The root search: favorites, meetings, suggestions, then one section per kind, led by any card.
struct LauncherScreen: PaletteScreen {
    let appIndex: AppIndex
    let favorites: FavoritesStore
    let visibility: VisibilityStore
    let core: AppCore
    let vm: PaletteState
    /// Sampled by `openActions`, so Restart and Quit can't move while the menu is up.
    let running: Bool
    /// The join card's meeting, resolved by the coordinator; nil unless one is due.
    let meeting: MeetingEvent?
    let now: Date
    let openActions: () -> Void
    let openArgumentOptions: (String) -> Void
    /// Called when an action reorders the list, so the highlight scrolls back into view.
    let scrollToFollow: () -> Void

    private let results: [AppEntry]
    private let calc: CalcResult?
    /// Set only while a web scope is committed; it owns row 0 the way the calc card does.
    private let webSearch: WebSearchEngine?
    /// What the engine offers for the query, beneath that row; consent-gated by the store.
    private let suggestions: [String]
    /// True when cached destinations share the list with on-demand Linear ticket results.
    private let isLinearScope: Bool
    /// Set while a capture scope is armed; the query is a task and the card is its preview.
    private let taskCapture: TaskCapturePreview?
    private let color: ColorValue?
    /// Only the empty query pins favorites — a category shows its sections without one of its own.
    private let pinsFavorites: Bool
    private let pinnedFavorites: [FavoritesStore.Item]
    /// How many follow the favorites as Meetings; zero unless the field is empty.
    private let meetingCount: Int
    /// How many follow the meetings as Suggestions; zero unless the field is empty.
    private let suggestionCount: Int
    private let matchCount: Int
    private let files: [FileSearchResult]
    /// The `Use "…" with` section, below every result; empty unless something is typed.
    private let fallbacks: [(fallback: Fallback, entry: AppEntry)]
    /// Resolved in `init`: the palette indexes this several times per event, so it can't recompute.
    let rows: [Row]

    init(
        appIndex: AppIndex, favorites: FavoritesStore, visibility: VisibilityStore,
        currencyRates: CurrencyRateStore, core: AppCore, vm: PaletteState, running: Bool,
        meeting: MeetingEvent?, now: Date,
        openActions: @escaping () -> Void, openArgumentOptions: @escaping (String) -> Void,
        scrollToFollow: @escaping () -> Void
    ) {
        self.appIndex = appIndex
        self.favorites = favorites
        self.visibility = visibility
        self.core = core
        self.vm = vm
        self.running = running
        self.now = now
        self.openActions = openActions
        self.openArgumentOptions = openArgumentOptions
        self.scrollToFollow = scrollToFollow

        // A scope decides what the query may match before the query is scored at all.
        let target = vm.scope.flatMap { ScopeCatalog.target(for: $0, settings: core.settings) }
        var kinds: Set<AppEntry.Kind>?
        var engine: WebSearchEngine?
        var isLinearScope = false
        var capture: TaskCapturePreview?
        switch target {
        case .kinds(let scoped): kinds = scoped
        case .webSearch(let scoped): engine = scoped
        case .linear:
            kinds = [.linearTarget]
            isLinearScope = true
        case .taskCapture(let destination):
            capture = core.taskCaptureCoordinator.preview(query: vm.query, destination: destination)
        // A mode scope never reaches here: adopting one switches screen instead of setting a scope.
        case .mode, nil: break
        }
        // A capture owns the query the way a web scope does: nothing else is scored against it.
        let ownsQuery = engine != nil || capture != nil
        let issues = ScopeCatalog.includesLinearIssues(
            scope: vm.scope, settings: core.settings, isEnabled: core.linear.isEnabled, visibility: visibility)
            ? AppIndex.linearEntries(for: core.linear.issueTargets(for: vm.query)).filter(visibility.isVisible) : []
        let lookup = LinearIssueLookup.parse(vm.query)
        let leadsWithIssues = isLinearScope || lookup?.isExactIssueLookup == true
        // Listed even when hidden from search: the shortcut that opened it must still be answered.
        let pinned = vm.argumentEntryID.flatMap(core.customCommands.command(entryID:))
            .map(AppEntry.init).flatMap { $0.name == vm.query ? $0 : nil }
        let ordered =
            pinned.map { AppIndex.Results(entries: [$0], matchCount: 1) }
            ?? (ownsQuery
                ? AppIndex.Results()
                : appIndex.orderedResults(
                    query: vm.query, visibility: visibility, favorites: favorites, hotKeys: core.hotKeys,
                    scope: vm.scope, kinds: kinds, additionalEntries: leadsWithIssues ? [] : issues))
        var results = ordered.entries
        var matchCount = ordered.matchCount
        if pinned == nil, leadsWithIssues {
            let issueIDs = Set(issues.map(\.id))
            let ranked = results.prefix(matchCount).filter { !issueIDs.contains($0.id) }
            results = issues + results.filter { !issueIDs.contains($0.id) }
            matchCount = issues.count + ranked.count
        }
        // A typed web address leads, unless a scope has already said what the query may match.
        if pinned == nil, vm.scope == nil, let browser = CommandCatalog.openInBrowser(for: vm.query),
            visibility.isVisible(browser)
        {
            results.insert(browser, at: 0)
            matchCount += 1
        }
        // No card over a pinned row, and a resolved PHI key must beat the golden-ratio constant.
        let calc =
            pinned == nil && !ownsQuery && !isLinearScope && !(leadsWithIssues && !issues.isEmpty)
            ? CalcMemo.evaluate(vm.query, rates: currencyRates.rates, format: core.calcNumberFormat) : nil
        // After the calculator: `#FF5733` is never arithmetic, so the two can't both answer.
        let color =
            calc == nil && pinned == nil && !ownsQuery && !isLinearScope ? ColorValue.parse(vm.query) : nil
        let files = pinned == nil && vm.scope == nil
            ? core.fileSearchCoordinator.launcherFiles(for: vm.query) : []
        // Scoped, because the section would widen a query a scope has just narrowed.
        let fallbacks = vm.scope == nil ? core.fallbackCoordinator.entries(for: vm.query) : []
        let pinsFavorites =
            !ownsQuery && vm.scope == nil
            && vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let pinnedFavorites = favorites.orderedItems(
            entries: Array(results.prefix(ordered.favoriteCount)),
            files: pinsFavorites ? core.fileSearchCoordinator.favoriteFiles : [])
        results.removeFirst(ordered.favoriteCount)
        let entries =
            pinnedFavorites.map(Row.init) + results.map(Row.entry) + files.map(Row.file)
            + fallbacks.map { Row.fallback($0.fallback, $0.entry) }
        // At most one of them leads, so the flat index keeps a single-row offset.
        let meeting = pinsFavorites ? meeting : nil
        self.meeting = meeting
        self.results = results
        self.calc = calc
        self.webSearch = engine
        self.isLinearScope = isLinearScope
        self.taskCapture = capture
        // Empty until the query's own reply lands, and empty forever without consent.
        let suggestions = engine == nil ? [] : core.searchSuggestions.suggestions(for: vm.query)
        self.suggestions = suggestions
        self.files = files
        self.fallbacks = fallbacks
        self.color = color
        self.pinsFavorites = pinsFavorites
        self.pinnedFavorites = pinnedFavorites
        self.meetingCount = pinsFavorites ? ordered.meetingCount : 0
        self.suggestionCount = pinsFavorites ? ordered.suggestionCount : 0
        self.matchCount = matchCount
        if let capture {
            let completions = core.taskCaptureCoordinator.completions(
                query: vm.query, destination: capture.destination)
            self.rows = [.taskCapture(capture)] + completions.map(Row.completion)
        } else if let engine {
            self.rows = [.webSearch(engine)] + suggestions.map(Row.suggestion)
        } else if let calc {
            self.rows = [.calc(calc)] + entries
        } else if let color {
            self.rows = [.color(color)] + entries
        } else if let meeting {
            self.rows = [.meeting(meeting)] + entries
        } else {
            self.rows = entries
        }
    }

    /// The card is a row like any other, so the flat selection indexes `rows` with no offset.
    enum Row: Equatable, Identifiable {
        case calc(CalcResult)
        case meeting(MeetingEvent)
        case webSearch(WebSearchEngine)
        case suggestion(String)
        case color(ColorValue)
        case entry(AppEntry)
        /// Prefixed, because an application's entry id is the same bundle path a file hit carries.
        case file(FileSearchResult)
        /// Prefixed, because the same command can also be a ranked hit above its own fallback row.
        case fallback(Fallback, AppEntry)
        case taskCapture(TaskCapturePreview)
        case completion(TaskCaptureCompletion)

        init(_ favorite: FavoritesStore.Item) {
            switch favorite {
            case .entry(let entry): self = .entry(entry)
            case .file(let file): self = .file(file)
            }
        }

        var favoriteKey: String? {
            switch self {
            case .entry(let entry):
                CommandCatalog.isQueryDriven(entry) ? nil : entry.preferenceKey
            case .file(let file): file.favoriteKey
            default: nil
            }
        }

        var id: String {
            switch self {
            case .calc: return "calc-card"
            case .taskCapture: return "task-capture-card"
            case .completion(let completion): return completion.id
            case .meeting: return "meeting-card"
            case .webSearch(let engine): return engine.entryID
            case .suggestion(let text): return SearchSuggestions.rowID(text)
            case .color: return "color-card"
            case .entry(let app): return app.id
            case .file(let result): return "file-" + result.id
            case .fallback(let fallback, _): return "fallback-" + fallback.id
            }
        }
    }

    /// The pill carries no selection, so the screen applies the clamp the palette applies.
    private var clampedSelection: Int {
        let count = rows.count
        return count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
    }

    var primaryActionTitle: String {
        switch row(at: clampedSelection) {
        case .calc: return String(localized: "Copy Answer")
        case .color: return String(localized: "Copy Color")
        case .meeting(let meeting):
            return meeting.link == nil
                ? String(localized: "Open in Calendar") : String(localized: "Join Meeting")
        case .webSearch(let engine): return String(localized: "Search \(engine.name)")
        case .suggestion:
            return webSearch.map { String(localized: "Search \($0.name)") } ?? String(localized: "Search")
        case .taskCapture(let preview):
            return core.taskCaptureCoordinator.primaryActionTitle(for: preview.destination)
        case .completion: return String(localized: "Use")
        case .entry(let app): return app.kind.descriptor.openVerb.resolved()
        case .file(let result):
            return result.isDirectory ? String(localized: "Open Folder") : String(localized: "Open File")
        case .fallback(let fallback, _): return fallback.openVerb
        case nil: return String(localized: "Open Application")
        }
    }

    private func row(at selection: Int) -> Row? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// What the controls are is the owning feature's business; this only forwards.
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    )
        -> PaletteHeaderAccessory?
    {
        guard let entry = entry(at: selection) else { return nil }
        // A quicklink asks for its values in root search too, so the fallback never leaves it.
        if entry.kind == .quicklink {
            return QuicklinkArgumentsAccessory.make(
                quicklink: quicklink(for: entry), core: core, vm: vm, focus: focus,
                placement: .afterQuery, onOpenOptions: openArgumentOptions,
                onSubmit: { activate(at: selection) })
        }
        if entry.kind == .customCommand {
            return CustomCommandArgumentsAccessory.make(
                command: core.customCommands.command(entryID: entry.id), vm: vm,
                metrics: core.settings.interfaceSize.metrics, focus: focus,
                onSubmit: { activate(at: selection) })
        }
        return ExtensionArgumentsAccessory.make(
            entry: entry, coordinator: core.extensionCoordinator,
            values: { name in headerFieldBinding(entry: entry, name: name) },
            focus: focus, metrics: core.settings.interfaceSize.metrics,
            onSubmit: { activate(at: selection) })
    }

    private func headerFieldBinding(entry: AppEntry, name: String) -> Binding<String> {
        let key = PaletteState.argumentKey(entry.id, name)
        return Binding(get: { vm.commandArguments[key] ?? "" }, set: { vm.commandArguments[key] = $0 })
    }

    private func quicklink(for entry: AppEntry) -> Quicklink? {
        Quicklink.id(fromEntryID: entry.id).flatMap(core.quicklinks.quicklink)
    }

    private func entry(at selection: Int) -> AppEntry? {
        guard case .entry(let app) = row(at: selection) else { return nil }
        return app
    }

    private func file(at selection: Int) -> FileSearchResult? {
        guard case .file(let result) = row(at: selection) else { return nil }
        return result
    }

    private func isCardSelected(_ selection: Int) -> Bool {
        switch row(at: selection) {
        case .calc, .meeting, .color, .taskCapture: return true
        case .webSearch, .suggestion, .entry, .file, .fallback, .completion, nil: return false
        }
    }

    private var leadCard: LauncherList.LeadCard? {
        if let taskCapture { return .taskCapture(taskCapture) }
        if let calc { return .calc(calc) }
        if let color { return .color(color) }
        return meeting.map { .meeting($0, now: now) }
    }

    /// An error card is selectable but has no action: it must drive neither the pill nor ⌘K.
    func hasPrimaryAction(at selection: Int) -> Bool {
        switch row(at: selection) {
        case .calc(let result): return result.isActionable
        // An empty scoped query has nothing to search for yet; the row still invites text.
        case .webSearch(let engine):
            return core.webSearchCoordinator.canSearch(engine: engine, query: vm.query)
        case .taskCapture(let preview): return preview.canCapture
        case .meeting, .color, .suggestion, .entry, .file, .fallback, .completion, nil: return true
        }
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        switch row(at: selection) {
        case .calc(let result):
            return result.isActionable ? CalcActionsMenu.content(result: result, core: core) : nil
        case .color(let color):
            return ColorActionsMenu.content(color: color, core: core)
        case .meeting(let meeting):
            return MeetingActionsMenu.content(meeting: meeting, core: core)
        case .entry(let app):
            if isLinearIssue(app) { return nil }
            return AppActionsMenu.content(
                app: app, searchQuery: vm.query, core: core, running: running,
                favorites: favoriteActions(for: .entry(app), at: selection),
                onResetRanking: {
                    core.launcherCoordinator.resetRanking(for: app)
                    // Reset can move the item; keep the highlight on the item whose action ran.
                    if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                },
                onHideFromSearch: { _ = hideFromSearch(at: selection) })
        case .file(let result):
            return FileSearchActionsMenu.content(
                result: result, core: core, target: vm.pasteTarget,
                favorites: favoriteActions(for: .file(result), at: selection))
        case .fallback(let fallback, let app):
            return FallbackActionsMenu.content(
                fallback: fallback, entry: app, query: vm.query, core: core)
        case .taskCapture(let preview):
            return preview.canCapture ? TaskCaptureActionsMenu.content(preview: preview, core: core) : nil
        // A search has one action, and ↵ already is it.
        case .webSearch, .suggestion, .completion, nil:
            return nil
        }
    }

    func activate(at selection: Int) {
        switch row(at: selection) {
        // Error cards no-op — copyCalculatorResult only acts on value payloads.
        case .calc(let result): core.calculatorCoordinator.copyCalculatorResult(result)
        case .color(let color):
            core.clipboardCoordinator.copyColor(color, as: ColorFormat.primary(for: color))
        case .meeting(let meeting): core.calendarCoordinator.activateMeeting(id: meeting.id)
        case .webSearch(let engine):
            core.webSearchCoordinator.search(engine: engine, query: vm.query)
        // A suggestion searches for itself, not for what is still in the field.
        case .suggestion(let text):
            guard let engine = webSearch else { break }
            core.webSearchCoordinator.search(engine: engine, query: text)
        case .entry(let app):
            core.launcherCoordinator.launch(
                app, searchQuery: vm.query, arguments: core.launcherCoordinator.argumentValues(for: app))
        case .file(let result): core.fileSearchCoordinator.open(result)
        case .fallback(let fallback, _):
            core.fallbackCoordinator.run(fallback, query: vm.query)
        case .taskCapture(let preview): core.taskCaptureCoordinator.capture(preview)
        case .completion(let completion): core.taskCaptureCoordinator.accept(completion, palette: vm)
        case nil: break
        }
    }

    /// The card's meeting or a meeting row's; both answer the meeting menu's chords.
    private func meeting(at selection: Int) -> MeetingEvent? {
        switch row(at: selection) {
        case .meeting(let meeting): return meeting
        case .entry(let app) where app.kind == .meeting:
            return core.calendarCoordinator.meeting(entryID: app.id)
        default: return nil
        }
    }

    /// ⌘↵ — a meeting copies its link, an answer becomes the query, an entry on disk is revealed.
    func secondary(at selection: Int) -> Bool {
        if let meeting = meeting(at: selection) {
            return MeetingActionsMenu.secondary(meeting: meeting, core: core)
        }
        if case .calc(let result) = row(at: selection) {
            return core.calculatorCoordinator.putAnswerInSearchBar(result)
        }
        if let file = file(at: selection) {
            core.fileSearchCoordinator.showInFinder(file)
            return true
        }
        guard let app = entry(at: selection), app.canRevealInFinder else { return false }
        core.launcherCoordinator.showInFinder(app)
        return true
    }

    private func runningApplication(at selection: Int) -> AppEntry? {
        guard let app = entry(at: selection), app.kind == .application,
            core.runningApps.isRunning(app)
        else { return nil }
        return app
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        if shortcut == .toggleFavorite { return toggleFavorite(at: selection) }
        if let file = file(at: selection),
            FileSearchActionsMenu.perform(shortcut, result: file, core: core)
        {
            return true
        }
        switch shortcut {
        case .hideFromSearch: return hideFromSearch(at: selection)
        case .quit, .forceQuit: return quit(at: selection, force: shortcut == .forceQuit)
        case .restart: return restart(at: selection)
        case .edit: return editItem(at: selection)
        case .copyPath: return copyQuicklink(at: selection)
        case .copyFile: return copyDeepLink(at: selection)
        case .favoriteSlot(let index): return launchFavorite(at: index)
        case .copyCalculation: return copyCalculation(at: selection)
        case .openInApp, .showDetails:
            guard let meeting = meeting(at: selection) else { return false }
            return MeetingActionsMenu.perform(shortcut, meeting: meeting, core: core)
        default: return false
        }
    }

    private func copyQuicklink(at selection: Int) -> Bool {
        guard let app = entry(at: selection), app.kind == .quicklink,
            let quicklink = quicklink(for: app)
        else { return false }
        core.quicklinkCoordinator.copyQuicklink(id: quicklink.id)
        return true
    }

    private func copyDeepLink(at selection: Int) -> Bool {
        guard let app = entry(at: selection),
            let deepLink = core.launcherCoordinator.deepLink(for: app)
        else { return false }
        core.launcherCoordinator.copyDeepLink(deepLink)
        return true
    }

    private func copyCalculation(at selection: Int) -> Bool {
        guard case .calc(let result) = row(at: selection), result.isActionable else { return false }
        core.calculatorCoordinator.copyCalculationWithExpression(result)
        return true
    }

    /// ⌃⇧Q or ⌃⌥⇧Q — the screen owns the chord, but only a running app has anything to quit.
    private func quit(at selection: Int, force: Bool) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.quit(app, force: force)
        return true
    }

    /// ⌘R — mirrors the Restart Application row.
    private func restart(at selection: Int) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.restart(app)
        return true
    }

    private func editItem(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        switch entry.kind {
        case .quicklink:
            guard let quicklink = quicklink(for: entry) else { return false }
            core.quicklinkCoordinator.editQuicklink(quicklink)
        case .snippet:
            guard let id = StoredSnippet.id(fromEntryID: entry.id),
                let record = core.snippetsStore.record(id: id)
            else { return false }
            core.snippetCoordinator.editSnippet(record)
        case .customCommand:
            guard let command = core.customCommands.command(entryID: entry.id) else { return false }
            core.customCommandCoordinator.editCustomCommand(command)
        default: return false
        }
        return true
    }

    /// The highlight stays in Favorites: the top on add, the neighbour above on remove.
    private func toggleFavorite(at selection: Int) -> Bool {
        guard let row = row(at: selection), row.favoriteKey != nil else { return false }
        if case .entry(let entry) = row, isLinearIssue(entry) { return false }
        let removed = favoriteIndex(of: row)
        switch row {
        case .entry(let entry): favorites.toggle(entry)
        case .file(let file): favorites.toggle(file)
        default: return false
        }
        // A typed query pins no favorites, so nothing moved and the highlight stays.
        guard pinsFavorites else { return true }
        selectFavorite(at: removed.map { $0 - 1 } ?? 0)
        return true
    }

    /// ⌘1–⌘9/⌘0 — launch a favorite by position, in either palette size.
    private func launchFavorite(at index: Int) -> Bool {
        guard pinnedFavorites.indices.contains(index) else { return false }
        activate(at: index + (leadCard == nil ? 0 : 1))
        return true
    }

    /// ⌥⌘↑/↓ — swap with the neighbouring favorite; the ends of the section have nowhere to go.
    func moveFavorite(_ delta: Int, at selection: Int) -> Bool {
        guard let row = row(at: selection), let index = favoriteIndex(of: row) else { return false }
        let target = index + delta
        guard pinnedFavorites.indices.contains(target) else { return false }
        favorites.exchange(pinnedFavorites[index].key, with: pinnedFavorites[target].key)
        follow(row)
        return true
    }

    /// The ends drop the move they can't run; both rows call back here, never drifting.
    private func favoriteActions(
        for row: Row, at selection: Int
    )
        -> FavoriteActions
    {
        let index = favoriteIndex(of: row)
        return FavoriteActions(
            isFavorite: row.favoriteKey.map(favorites.keys.contains) ?? false,
            canMoveUp: index.map { $0 > 0 } ?? false,
            canMoveDown: index.map { $0 < pinnedFavorites.count - 1 } ?? false,
            toggle: { _ = toggleFavorite(at: selection) },
            move: { _ = moveFavorite($0, at: selection) })
    }

    private func favoriteIndex(of row: Row) -> Int? {
        pinnedFavorites.firstIndex { $0.id == row.id }
    }

    /// ⇧⌘H — the row leaves the list for good, so the highlight takes the place it vacated.
    private func hideFromSearch(at selection: Int) -> Bool {
        guard let app = entry(at: selection), !CommandCatalog.isQueryDriven(app),
            let index = rows.firstIndex(of: .entry(app))
        else { return false }
        // Each editor's Show in root search toggle is the undo, so neither hide is one-way.
        if let id = Quicklink.id(fromEntryID: app.id) {
            core.quicklinkCoordinator.setQuicklinkShowsInRootSearch(false, id: id)
        } else if let id = CustomCommand.id(fromEntryID: app.id) {
            core.customCommandCoordinator.setCustomCommandShowsInRootSearch(false, id: id)
        } else if app.canHideFromSearch {
            visibility.setItemVisible(false, for: app)
        } else {
            return false
        }
        select(row: min(index - (leadCard == nil ? 0 : 1), max(reorderedEntryRows().count - 1, 0)))
        return true
    }

    /// The list reorders under an action; keep the highlight and the scroll on the row that moved.
    private func follow(_ row: Row) {
        guard let index = reorderedEntryRows().firstIndex(of: row) else { return }
        select(row: index)
    }

    private func selectFavorite(at index: Int) {
        let count = reorderedFavorites(in: reorderedResults()).count
        select(row: min(max(index, 0), max(count - 1, 0)))
    }

    /// Re-read the order the change just invalidated; this warms the key the next render reads.
    private func reorderedResults() -> AppIndex.Results {
        let target = vm.scope.flatMap { ScopeCatalog.target(for: $0, settings: core.settings) }
        let kinds: Set<AppEntry.Kind>?
        switch target {
        case .kinds(let scoped): kinds = scoped
        case .linear: kinds = [.linearTarget]
        default: kinds = nil
        }
        let issues = ScopeCatalog.includesLinearIssues(
            scope: vm.scope, settings: core.settings, isEnabled: core.linear.isEnabled, visibility: visibility)
            ? AppIndex.linearEntries(for: core.linear.issueTargets(for: vm.query)).filter(visibility.isVisible) : []
        let leadsWithIssues = isLinearScope || LinearIssueLookup.parse(vm.query)?.isExactIssueLookup == true
        var ordered = appIndex.orderedResults(
            query: vm.query, visibility: visibility, favorites: favorites, hotKeys: core.hotKeys,
            scope: vm.scope, kinds: kinds, additionalEntries: leadsWithIssues ? [] : issues)
        if leadsWithIssues {
            let issueIDs = Set(issues.map(\.id))
            let ranked = ordered.entries.prefix(ordered.matchCount).filter { !issueIDs.contains($0.id) }
            ordered = AppIndex.Results(
                entries: issues + ordered.entries.filter { !issueIDs.contains($0.id) },
                matchCount: issues.count + ranked.count)
        }
        return ordered
    }

    private func reorderedEntryRows() -> [Row] {
        let ordered = reorderedResults()
        let pinned = reorderedFavorites(in: ordered)
        return pinned.map(Row.init) + ordered.entries.dropFirst(ordered.favoriteCount).map(Row.entry)
    }

    private func reorderedFavorites(in ordered: AppIndex.Results) -> [FavoritesStore.Item] {
        favorites.orderedItems(
            entries: Array(ordered.entries.prefix(ordered.favoriteCount)),
            files: pinsFavorites ? core.fileSearchCoordinator.favoriteFiles : [])
    }

    private func select(row index: Int) {
        vm.selection = index + (leadCard == nil ? 0 : 1)
        scrollToFollow()
    }

    /// The sample `openActions` takes; only an app row can ever carry the running-only actions.
    func isRunning(at selection: Int) -> Bool {
        guard let app = entry(at: selection) else { return false }
        return core.runningApps.isRunning(app)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        if isLinearScope, results.isEmpty {
            EmptyResults(text: linearEmptyResultsText)
        } else {
            LauncherList(
                results: results,
                selectedRowID: row(at: selection)?.id,
                favorites: pinnedFavorites,
                meetingCount: meetingCount,
                suggestionCount: suggestionCount,
                matchCount: matchCount,
                scroll: scroll,
                card: leadCard,
                cardSelected: isCardSelected(selection),
                onActivateCard: {
                    vm.selection = 0
                    activate(at: 0)
                },
                onCardActions: {
                    guard hasPrimaryAction(at: 0) else { return }
                    vm.selection = 0
                    openActions()
                },
                webSearch: webSearch.map {
                    LauncherList.WebSearchPrompt(
                        id: $0.entryID,
                        title: core.webSearchCoordinator.rowTitle(engine: $0, query: vm.query),
                        symbol: $0.symbol,
                        sectionTitle: AppEntry.Kind.webSearch.descriptor.sectionTitle.resolved())
                },
                suggestions: suggestions,
                onActivateWebSearch: { activate(at: 0) },
                onActivateSuggestion: { text in
                    guard let index = rows.firstIndex(of: .suggestion(text)) else { return }
                    vm.selection = index
                    activate(at: index)
                },
                completions: rows.compactMap {
                    if case .completion(let completion) = $0 { return completion }
                    return nil
                },
                onActivateCompletion: { completion in
                    guard let index = rows.firstIndex(of: .completion(completion)) else { return }
                    vm.selection = index
                    activate(at: index)
                },
                onActivate: {
                    core.launcherCoordinator.launch(
                        $0, searchQuery: vm.query, arguments: core.launcherCoordinator.argumentValues(for: $0))
                },
                onActions: { app in
                    if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                    openActions()
                },
                onActivateFavorite: { _ = launchFavorite(at: $0) },
                onFavoriteActions: {
                    vm.selection = $0 + (leadCard == nil ? 0 : 1)
                    openActions()
                },
                onDropped: { core.paletteCoordinator.dragLanded() },
                files: fileSection,
                fallbacks: fallbackSection
            )
        }
    }

    private var linearEmptyResultsText: String {
        let query = vm.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return String(localized: "Type a ticket number, key, or title") }
        guard LinearIssueLookup.parse(query) != nil else {
            return String(localized: "Type a valid ticket number, key, or at least 3 title characters")
        }
        switch core.linear.issueSearchState {
        case .idle: return String(localized: "Type a ticket number, key, or title")
        case .searching: return String(localized: "Searching Linear…")
        case .ready:
            return core.linear.issueSearchError == nil
                ? String(localized: "No Linear matches") : String(localized: "Some Linear workspaces were unavailable")
        case .failed: return String(localized: "Linear search is unavailable")
        }
    }

    private func isLinearIssue(_ app: AppEntry) -> Bool {
        guard app.kind == .linearTarget, let id = LinearTarget.id(fromEntryID: app.id) else {
            return false
        }
        return core.linear.isIssueTarget(id: id)
    }

    private var fileSection: LauncherList.FileSection? {
        guard !files.isEmpty else { return nil }
        return LauncherList.FileSection(
            results: files,
            onActivate: { activate(at: fileRow(at: $0)) },
            onActions: {
                vm.selection = fileRow(at: $0)
                openActions()
            })
    }

    private func fileRow(at index: Int) -> Int { rows.count - fallbacks.count - files.count + index }

    /// Nil when nothing is typed, which is the one state the section has no input for.
    private var fallbackSection: LauncherList.FallbackSection? {
        guard !fallbacks.isEmpty else { return nil }
        return LauncherList.FallbackSection(
            title: Fallback.sectionTitle(query: vm.query),
            entries: fallbacks.map(\.entry),
            onActivate: { activate(at: fallbackRow(at: $0)) },
            onActions: {
                vm.selection = fallbackRow(at: $0)
                openActions()
            },
            onConfigure: core.fallbackCoordinator.showSettings)
    }

    /// Fallbacks are the tail of `rows`, so a click maps to its flat index without a search.
    private func fallbackRow(at index: Int) -> Int { rows.count - fallbacks.count + index }
}
