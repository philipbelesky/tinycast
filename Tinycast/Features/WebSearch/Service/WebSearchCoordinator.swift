import AppKit

/// Opens a search in the default browser. Nothing here fetches — see docs/features/web-search.md.
@MainActor
final class WebSearchCoordinator {
    private let paletteCoordinator: PaletteCoordinator
    /// Injected like `QuicklinkCoordinator`'s, so a template's `{clipboard}` reads the same history.
    private let clipboardHistory: @MainActor () -> [String]

    init(
        paletteCoordinator: PaletteCoordinator,
        clipboardHistory: @escaping @MainActor () -> [String]
    ) {
        self.paletteCoordinator = paletteCoordinator
        self.clipboardHistory = clipboardHistory
    }

    /// What the scoped row reads. The engine's name, not the query, is the subject.
    func rowTitle(engine: WebSearchEngine, query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? "Search \(engine.name)" : "Search \(engine.name) for “\(trimmed)”"
    }

    func canSearch(engine: WebSearchEngine, query: String) -> Bool {
        url(engine: engine, query: query) != nil
    }

    func search(engine: WebSearchEngine, query: String) {
        guard let url = url(engine: engine, query: query) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.open(url)
    }

    /// A template may reach for `{clipboard}` or `{date}`, so the context is captured per search.
    private func url(engine: WebSearchEngine, query: String) -> URL? {
        engine.url(
            for: query,
            context: SnippetTemplateEngine.ExpansionContext(
                clipboardHistory: clipboardHistory(),
                selection: "",
                now: Date(),
                calendar: .current,
                locale: .current,
                timeZone: .current))
    }
}
