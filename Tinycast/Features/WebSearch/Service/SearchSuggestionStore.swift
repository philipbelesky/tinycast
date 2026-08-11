import Foundation

/// Query completions from the armed engine's suggest endpoint. The only feature that sends what the
/// user *types* anywhere, so it wears the consent shape twice over — see
/// docs/features/web-search.md#suggestions.
@MainActor
@Observable
final class SearchSuggestionStore {
    /// Long enough that a fast typist sends one request rather than a request per letter.
    private static let debounce: Duration = .milliseconds(200)
    /// A suggestion that lands after the user has read the list is noise, so the wait is short.
    private nonisolated static let timeout: TimeInterval = 4

    /// Consent. Deliberately not in `AppSettings`, so no import can start a keystroke feed.
    private(set) var isEnabled: Bool

    /// What the newest reply offered, and the query it answers — a stale reply must not be shown
    /// against a query the user has since changed.
    private(set) var suggestions: [String] = []
    private(set) var answering = ""

    private static let consentKey = "searchSuggestionsEnabled"
    private let defaults = UserDefaults.standard
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    /// Absent reads as false, the only safe default for anything that leaves the machine.
    /// There is no cache to read back: a query is never written to disk, not even once.
    init() { isEnabled = defaults.bool(forKey: Self.consentKey) }

    /// The read path: without consent there is nothing to show, whatever a stale field holds.
    func suggestions(for query: String) -> [String] {
        guard isEnabled, answering == query else { return [] }
        return suggestions
    }

    /// Ask what this query might become. Cancels whatever was in flight, so the reply on screen is
    /// always the one for the newest keystroke.
    func update(engine: WebSearchEngine, query: String) {
        inFlight?.cancel()
        guard isEnabled, let url = engine.suggestURL(for: query) else {
            clear()
            return
        }
        inFlight = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self, self.isEnabled else { return }
            let fetched = await Self.fetch(url: url, typed: query)
            // Consent can be withdrawn, and the query can move on, while a request is in flight.
            guard !Task.isCancelled, self.isEnabled else { return }
            self.suggestions = fetched
            self.answering = query
        }
    }

    /// Leaving the scope, closing the palette, or losing consent: the list is not kept around.
    func clear() {
        inFlight?.cancel()
        inFlight = nil
        suggestions = []
        answering = ""
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.consentKey)
        if !enabled { clear() }
    }

    /// Cacheless and cookieless, never `URLSession.shared`: a suggest request carries what the user
    /// is typing, so it may not accumulate a cookie jar that ties one query to the next.
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    /// Off-main, and total: a failed or malformed reply is an empty list, never a reported error.
    private nonisolated static func fetch(url: URL, typed: String) async -> [String] {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        // The endpoints answer JSON to anything, and a real browser's UA would be a lie about us.
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return [] }
        return SearchSuggestions.parse(data, typed: typed)
    }
}
