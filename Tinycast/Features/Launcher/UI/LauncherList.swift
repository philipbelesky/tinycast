import SwiftUI

struct LauncherList: View {
    let results: [AppEntry]
    /// The flat row id the screen has selected, not an entry id: a fallback can repeat a result.
    let selectedRowID: String?
    let favoriteCount: Int
    let showSections: Bool
    /// Changes only when the list should scroll, so mouse selection never yanks it.
    let scroll: ScrollIntent
    /// The card at flat index 0, when one leads. At most one ever does.
    var card: LeadCard?
    var cardSelected = false
    var onActivateCard: () -> Void = {}
    var onCardActions: () -> Void = {}
    /// The one row a web scope shows; it replaces the list rather than joining it.
    var webSearch: WebSearchPrompt?
    /// Completions for what is typed, beneath that row. Empty without consent — see the store.
    var suggestions: [String] = []
    var onActivateWebSearch: () -> Void = {}
    var onActivateSuggestion: (String) -> Void = { _ in }
    let onActivate: (AppEntry) -> Void
    let onActions: (AppEntry) -> Void
    /// The `Use "…" with` section, always last; nil when nothing is typed.
    var fallbacks: FallbackSection?
    @Environment(RunningAppsMonitor.self) private var runningApps

    /// What the fallback section draws and where its rows go, addressed by position.
    struct FallbackSection {
        let title: String
        let entries: [AppEntry]
        let onActivate: (Int) -> Void
        let onActions: (Int) -> Void
        let onConfigure: () -> Void
    }

    /// Calc answers a typed query and the card an empty one, so only one ever leads.
    enum LeadCard: Equatable {
        case calc(CalcResult)
        case meeting(MeetingEvent, now: Date)

        var sectionTitle: String {
            switch self {
            case .calc: return "Calculator"
            case .meeting: return "Meeting"
            }
        }

        var rowID: String {
            switch self {
            case .calc: return "calc-card"
            case .meeting: return "meeting-card"
            }
        }
    }

    /// What the scoped search row draws: already-composed text, so the list stays presentational.
    struct WebSearchPrompt: Equatable {
        /// The engine's entry id, which is also what the screen calls this row.
        let id: String
        let title: String
        let symbol: String
        let sectionTitle: String
    }

    private enum Row: Identifiable {
        case header(String)
        /// Its own case, because only this header carries a gear.
        case fallbackHeader(String)
        case card(LeadCard)
        case webSearch(WebSearchPrompt)
        case suggestion(String)
        /// `slot` is the row's ⌘-digit, carried from the section build rather than searched.
        case app(AppEntry, slot: Character?)
        case fallback(AppEntry, index: Int)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .fallbackHeader: return "fallback-header"
            case .card(let card): return card.rowID
            case .webSearch(let prompt): return prompt.id
            case .suggestion(let text): return SearchSuggestions.rowID(text)
            case .app(let app, _): return app.id
            case .fallback(let app, _): return "fallback-" + app.id
            }
        }
    }

    /// Whether the selection sits on flat index 0: the search row, the card, else the first result.
    private var firstRowSelected: Bool {
        if let webSearch { return selectedRowID == webSearch.id }
        return card != nil ? cardSelected : selectedRowID != nil && selectedRowID == results.first?.id
    }

    /// Every row the fallback section contributes, always after the results.
    private var fallbackRows: [Row] {
        guard let fallbacks else { return [] }
        return [.fallbackHeader(fallbacks.title)]
            + fallbacks.entries.enumerated().map { Row.fallback($1, index: $0) }
    }

    private var rows: [Row] {
        // A web scope owns the query outright, so nothing else can be on screen to index into.
        if let webSearch {
            return [.header(webSearch.sectionTitle), .webSearch(webSearch)]
                + suggestions.map(Row.suggestion)
        }
        var cardRows: [Row] = []
        if let card { cardRows = [.header(card.sectionTitle), .card(card)] }
        guard showSections else {
            guard !results.isEmpty else { return cardRows + fallbackRows }
            return cardRows + [.header("Results")] + results.map { .app($0, slot: nil) }
                + fallbackRows
        }
        var rows: [Row] = cardRows
        let favorites = results.prefix(favoriteCount)
        let rest = results.dropFirst(favoriteCount)
        var grouped: [AppEntry.Kind: [AppEntry]] = [:]
        for app in rest { grouped[app.kind, default: []].append(app) }
        if !favorites.isEmpty {
            rows.append(.header("Favorites"))
            rows.append(
                contentsOf: favorites.enumerated().map {
                    .app($1, slot: FavoriteSlots.digit(at: $0))
                })
        }
        // Publication order, so rows match the flat index.
        let kinds: [AppEntry.Kind] = [
            .scope, .meeting,
            .application, .systemSettings, .extensionCommand, .quicklink, .vsCodeProject,
            .herdrTarget, .linearTarget, .webSearch, .snippet,
            .systemAction, .windowCommand, .customCommand, .command
        ]
        for kind in kinds {
            guard let group = grouped[kind], !group.isEmpty else { continue }
            rows.append(.header(kind.descriptor.sectionTitle))
            rows.append(contentsOf: group.map { .app($0, slot: nil) })
        }
        // A missing kind would make every later row activate its neighbour: assert instead.
        assert(
            grouped.keys.allSatisfy(kinds.contains),
            "kind missing from the launcher's section order: "
                + grouped.keys.filter { !kinds.contains($0) }.map(\.rawValue).joined(separator: ", "))
        return rows + fallbackRows
    }

    var body: some View {
        let rows = rows
        return Group {
            if results.isEmpty && card == nil && webSearch == nil && fallbacks == nil {
                EmptyResults(text: "No apps found")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                switch row {
                                case .header(let title):
                                    SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                                case .fallbackHeader(let title):
                                    SectionHeader(
                                        title: title, isFirst: row.id == rows.first?.id,
                                        configure: fallbacks?.onConfigure,
                                        configureHelp: "Configure Fallbacks…")
                                case .card(let card):
                                    LeadCardView(card: card, selected: cardSelected)
                                        .contentShape(Rectangle())
                                        .onTapGesture(perform: onActivateCard)
                                        .onRightClick(perform: onCardActions)
                                        .padding(.bottom, Theme.Spacing.xs)
                                        .selectionFrame(cardSelected)
                                case .webSearch(let prompt):
                                    WebSearchRow(prompt: prompt, selected: selectedRowID == prompt.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture(perform: onActivateWebSearch)
                                        .selectionFrame(selectedRowID == prompt.id)
                                case .suggestion(let text):
                                    SuggestionRow(
                                        text: text, symbol: webSearch?.symbol ?? "magnifyingglass",
                                        selected: selectedRowID == SearchSuggestions.rowID(text)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { onActivateSuggestion(text) }
                                    .selectionFrame(selectedRowID == SearchSuggestions.rowID(text))
                                case .app(let app, let slot):
                                    AppRow(
                                        app: app,
                                        selected: app.id == selectedRowID,
                                        running: runningApps.isRunning(app),
                                        slot: slot
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { onActivate(app) }
                                    .onRightClick { onActions(app) }
                                    .selectionFrame(app.id == selectedRowID)
                                case .fallback(let app, let index):
                                    AppRow(
                                        app: app, selected: row.id == selectedRowID, running: false,
                                        slot: nil
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { fallbacks?.onActivate(index) }
                                    .onRightClick { fallbacks?.onActions(index) }
                                    .selectionFrame(row.id == selectedRowID)
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.xs)
                        .padding(.bottom, Theme.Spacing.md)
                        .hideNativeScrollers()
                        .scrollOriginAnchor()
                    }
                    .edgeDissolve()
                    .thinScrollbar()
                    // Snap to the origin on the first row so its header shows too.
                    .scrollFollowsSelection(
                        scroll, row: selectedRowID, atOrigin: firstRowSelected, proxy: proxy)
                }
            }
        }
    }
}

/// One completion offered by the engine. It searches for itself, so it reads as the query it is.
private struct SuggestionRow: View {
    let text: String
    let symbol: String
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: symbol)
                .font(Theme.Typography.rowTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            Text(text)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("Suggestion")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(selected ? Theme.Colors.selection : (hovered ? Theme.Colors.rowHover : .clear))
        )
        .armedHover($hovered)
    }
}

/// The scoped search row: the query verbatim, above whatever the engine suggests it might become.
private struct WebSearchRow: View {
    let prompt: LauncherList.WebSearchPrompt
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: prompt.symbol)
                .font(Theme.Typography.rowTitle)
                .symbolRenderingMode(.hierarchical)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            Text(prompt.title)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(AppEntry.Kind.webSearch.descriptor.label)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(selected ? Theme.Colors.selection : (hovered ? Theme.Colors.rowHover : .clear))
        )
        .armedHover($hovered)
    }
}

/// Draws whichever card leads; each feature still owns how its own card looks.
private struct LeadCardView: View {
    let card: LauncherList.LeadCard
    let selected: Bool

    var body: some View {
        switch card {
        case .calc(let result):
            CalculatorCard(result: result, selected: selected)
        case .meeting(let meeting, let now):
            MeetingCard(meeting: meeting, now: now, selected: selected)
        }
    }
}

private struct AppRow: View {
    let app: AppEntry
    let selected: Bool
    let running: Bool
    /// This row's ⌘-digit, or nil for a row no chord launches.
    let slot: Character?
    /// Observed so a hotkey set/cleared in Settings re-renders the row's keycaps immediately.
    @Environment(HotKeyManager.self) private var hotKeys
    @Environment(AppSettings.self) private var settings
    /// Observed for the same reason: an alias edit re-renders the row's badge at once.
    @Environment(AliasStore.self) private var aliases
    /// Observed here rather than up in the list, so a ⌘ press re-renders rows and not the palette.
    @Environment(PaletteState.self) private var palette
    @State private var hovered = false

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// Keycaps for this entry's hotkey — or, for a scope, the keyword that arms it. Read from the
    /// catalog rather than carried on the entry, so an edited keyword is never a stale row.
    private var shortcutCaps: [String]? {
        if app.kind == .scope {
            let keyword = ScopeCatalog.definition(id: app.id, settings: settings)?.keyword
            return keyword.flatMap { $0.isEmpty ? nil : [$0] }
        }
        guard let action = app.hotKeyAction else { return nil }
        return hotKeys.binding(for: action)?.keycaps
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            AppIconView(app: app, source: app.categoryIconSource)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                .overlay(alignment: .bottom) {
                    if running {
                        Circle()
                            .fill(.secondary)
                            .frame(width: Theme.Size.runningDot, height: Theme.Size.runningDot)
                            .offset(y: Theme.Size.runningDot)
                    }
                }
            Text(app.name)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
            if let subtitle = app.subtitle {
                Text(subtitle)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let alias = aliases.alias(for: app.preferenceKey) {
                Text(alias)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                            .fill(Theme.Colors.controlSurface))
            }
            if let caps = shortcutCaps {
                HStack(spacing: Theme.Spacing.xxs) {
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
            Spacer()
            // Holding ⌘ turns the trailing label into the chord that launches this row.
            if let slot, palette.commandHeld {
                HStack(spacing: Theme.Spacing.xxs) {
                    KeyCapChip(text: "⌘", style: .outline)
                    KeyCapChip(text: String(slot), style: .outline)
                }
            } else {
                Text(app.kindLabel)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}

#if DEBUG
    /// The empty query: favorites, then a section per kind, including two coloured scope tiles.
    #Preview("Launcher · sections") {
        LauncherList(
            results: PreviewData.launcherResults,
            selectedRowID: PreviewData.notes.id,
            favoriteCount: PreviewData.launcherFavoriteCount,
            showSections: true,
            scroll: ScrollIntent(kind: .top),
            onActivate: { _ in },
            onActions: { _ in }
        )
        .previewInPalette()
    }

    #Preview("Launcher · results with a calc card") {
        LauncherList(
            results: PreviewData.launcherResults,
            selectedRowID: nil,
            favoriteCount: 0,
            showSections: false,
            scroll: ScrollIntent(kind: .top),
            card: .calc(PreviewData.calcArithmetic),
            cardSelected: true,
            onActivate: { _ in },
            onActions: { _ in }
        )
        .previewInPalette()
    }

    /// A web scope owns the query outright: one search row, then whatever the engine suggests.
    #Preview("Launcher · web scope") {
        LauncherList(
            results: [],
            selectedRowID: "web-search:google",
            favoriteCount: 0,
            showSections: false,
            scroll: ScrollIntent(kind: .top),
            webSearch: LauncherList.WebSearchPrompt(
                id: "web-search:google", title: "Search Google for “liquid glass”",
                symbol: "magnifyingglass", sectionTitle: "Google"),
            suggestions: ["liquid glass swiftui", "liquid glass macos 26", "liquid glass tahoe"],
            onActivate: { _ in },
            onActions: { _ in }
        )
        .previewInPalette()
    }

    #Preview("Launcher · empty") {
        LauncherList(
            results: [],
            selectedRowID: nil,
            favoriteCount: 0,
            showSections: true,
            scroll: ScrollIntent(kind: .top),
            onActivate: { _ in },
            onActions: { _ in }
        )
        .previewInPalette()
    }
#endif
