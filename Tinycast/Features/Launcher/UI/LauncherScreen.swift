import SwiftUI

/// The root search: favorites first, then one section per entry kind, led by the calculator card.
struct LauncherScreen: PaletteScreen {
    let appIndex: AppIndex
    let favorites: FavoritesStore
    let visibility: VisibilityStore
    let core: AppCore
    let vm: PaletteState
    /// Sampled by `openActions`, so the Quit row can't appear or vanish while the menu is up.
    let running: Bool
    let openActions: () -> Void

    /// The one ordered result list; an empty query pins favorites above the ranked matches.
    private let results: [AppEntry]
    private let calc: CalcResult?
    /// Set only while a web scope is committed; it owns row 0 the way the calc card does.
    private let webSearch: WebSearchEngine?
    /// What the engine offers for the query, beneath that row; consent-gated by the store.
    private let suggestions: [String]
    /// Resolved in `init`: the palette indexes this several times per event, so it can't recompute.
    let rows: [Row]

    init(
        appIndex: AppIndex, favorites: FavoritesStore, visibility: VisibilityStore,
        currencyRates: CurrencyRateStore, core: AppCore, vm: PaletteState, running: Bool,
        openActions: @escaping () -> Void
    ) {
        self.appIndex = appIndex
        self.favorites = favorites
        self.visibility = visibility
        self.core = core
        self.vm = vm
        self.running = running
        self.openActions = openActions

        // A scope decides what the query may match before the query is scored at all.
        let target = vm.scope.flatMap { ScopeCatalog.target(for: $0, settings: core.settings) }
        var kinds: Set<AppEntry.Kind>?
        var engine: WebSearchEngine?
        switch target {
        case .kinds(let scoped): kinds = scoped
        case .webSearch(let scoped): engine = scoped
        // A mode scope never reaches here: adopting one switches screen instead of setting a scope.
        case .mode, nil: break
        }
        let results =
            engine == nil
            ? appIndex.orderedResults(
                query: vm.query, visibility: visibility, favorites: favorites,
                scope: vm.scope, kinds: kinds)
            : []
        // A web scope owns the whole query, so a bare number in it is a search, not a sum.
        let calc =
            engine == nil ? CalcMemo.evaluate(vm.query, currency: currencyRates.source) : nil
        let entries = results.map(Row.entry)
        self.results = results
        self.calc = calc
        self.webSearch = engine
        // Empty until the query's own reply lands, and empty forever without consent.
        self.suggestions =
            engine == nil ? [] : core.searchSuggestions.suggestions(for: vm.query)
        if let engine {
            self.rows = [.webSearch(engine)] + suggestions.map(Row.suggestion)
        } else {
            self.rows = calc.map { [.calc($0)] + entries } ?? entries
        }
    }

    /// The card is a row like any other, so the flat selection indexes `rows` with no offset.
    enum Row: Equatable, Identifiable {
        case calc(CalcResult)
        case webSearch(WebSearchEngine)
        case suggestion(String)
        case entry(AppEntry)

        var id: String {
            switch self {
            case .calc: return "calc-card"
            case .webSearch(let engine): return engine.entryID
            case .suggestion(let text): return SearchSuggestions.rowID(text)
            case .entry(let app): return app.id
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
        case .calc: return "Copy Answer"
        case .webSearch(let engine): return "Search \(engine.name)"
        case .suggestion: return webSearch.map { "Search \($0.name)" } ?? "Search"
        case .entry(let app): return app.kind.descriptor.openVerb
        case nil: return "Open Application"
        }
    }

    private func row(at selection: Int) -> Row? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    private func entry(at selection: Int) -> AppEntry? {
        guard case .entry(let app) = row(at: selection) else { return nil }
        return app
    }

    private func isCardSelected(_ selection: Int) -> Bool {
        if case .calc = row(at: selection) { return true }
        return false
    }

    /// An error card is selectable but has no action: it must drive neither the pill nor ⌘K.
    func hasPrimaryAction(at selection: Int) -> Bool {
        switch row(at: selection) {
        case .calc(let result): return result.isActionable
        // An empty scoped query has nothing to search for yet; the row still invites text.
        case .webSearch(let engine):
            return core.webSearchCoordinator.canSearch(engine: engine, query: vm.query)
        case .suggestion, .entry, nil: return true
        }
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        switch row(at: selection) {
        case .calc(let result):
            return result.isActionable ? CalcActionsMenu.content(result: result, core: core) : nil
        case .entry(let app):
            return AppActionsMenu.content(
                app: app, searchQuery: vm.query, core: core, favorites: favorites, running: running,
                onResetRanking: {
                    core.launcherCoordinator.resetRanking(for: app)
                    // Reset can move the item; keep the highlight on the item whose action ran.
                    if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                })
        // A search has one action, and ↵ already is it.
        case .webSearch, .suggestion, nil:
            return nil
        }
    }

    func activate(at selection: Int) {
        switch row(at: selection) {
        // Error cards no-op — copyCalculatorResult only acts on value payloads.
        case .calc(let result): core.calculatorCoordinator.copyCalculatorResult(result)
        case .webSearch(let engine):
            core.webSearchCoordinator.search(engine: engine, query: vm.query)
        // A suggestion searches for itself, not for what is still in the field.
        case .suggestion(let text):
            guard let engine = webSearch else { break }
            core.webSearchCoordinator.search(engine: engine, query: text)
        case .entry(let app): core.launcherCoordinator.launch(app, searchQuery: vm.query)
        case nil: break
        }
    }

    /// ⌘↵ — only an entry backed by a file on disk has somewhere to be revealed.
    func secondary(at selection: Int) -> Bool {
        guard let app = entry(at: selection), app.canRevealInFinder else { return false }
        core.launcherCoordinator.showInFinder(app)
        return true
    }

    /// ⌃⇧Q — the screen owns the chord, but only a running application has anything to quit.
    func quit(at selection: Int) -> Bool {
        guard let app = entry(at: selection), app.kind == .application,
            core.runningApps.isRunning(app)
        else { return false }
        core.launcherCoordinator.quit(app)
        return true
    }

    /// The sample `openActions` takes; only an app row can ever carry a Quit action.
    func isRunning(at selection: Int) -> Bool {
        guard let app = entry(at: selection) else { return false }
        return core.runningApps.isRunning(app)
    }

    /// The compact bar's favorite slots: 5 apps, or 4 plus an overflow that expands.
    var compactFavoriteSlots: [CompactFavoriteSlot] {
        let ordered = appIndex.orderedResults(
            query: "", visibility: visibility, favorites: favorites)
        let favs = ordered.prefix(while: favorites.isFavorite)
        if favs.count <= 5 { return favs.map(CompactFavoriteSlot.app) }
        return favs.prefix(4).map(CompactFavoriteSlot.app) + [.more]
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        // Sections stand in for the ranked Results list, which a typed query collapses to.
        let showSections = vm.query.trimmingCharacters(in: .whitespaces).isEmpty
        LauncherList(
            results: results,
            selectedID: row(at: selection)?.id,
            favoriteCount: showSections ? results.prefix(while: favorites.isFavorite).count : 0,
            showSections: showSections,
            scroll: scroll,
            calc: calc,
            calcSelected: isCardSelected(selection),
            onActivateCalc: {
                vm.selection = 0
                activate(at: 0)
            },
            onCalcActions: {
                guard let calc, case .value = calc.payload else { return }
                vm.selection = 0
                openActions()
            },
            webSearch: webSearch.map {
                LauncherList.WebSearchPrompt(
                    id: $0.entryID,
                    title: core.webSearchCoordinator.rowTitle(engine: $0, query: vm.query),
                    symbol: $0.symbol,
                    sectionTitle: AppEntry.Kind.webSearch.descriptor.sectionTitle)
            },
            suggestions: suggestions,
            onActivateWebSearch: { activate(at: 0) },
            onActivateSuggestion: { text in
                guard let index = rows.firstIndex(of: .suggestion(text)) else { return }
                vm.selection = index
                activate(at: index)
            },
            onActivate: { core.launcherCoordinator.launch($0, searchQuery: vm.query) },
            onActions: { app in
                if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                openActions()
            }
        )
    }
}
