import Foundation

/// A search destination: a URL template whose `{argument}` the palette fills. See
/// docs/features/web-search.md — nothing here fetches, so no consent gate applies.
struct WebSearchEngine: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// The scope keyword that routes a query here; unique across the whole scope registry.
    let keyword: String
    /// Expanded through `SnippetTemplateEngine`, so a template may also use `{clipboard}`, `{date}`…
    let urlTemplate: String
    let symbol: String
    /// The engine's OpenSearch suggest endpoint, or nil for one that has none. Only `{argument}` is
    /// substituted here: this is asked per keystroke, so it reads neither clock nor clipboard.
    var suggestTemplate: String?

    static let google = WebSearchEngine(
        id: "google", name: "Google", keyword: "g",
        urlTemplate: "https://www.google.com/search?q={argument}", symbol: "magnifyingglass",
        suggestTemplate: "https://suggestqueries.google.com/complete/search?client=firefox&q={argument}"
    )
    static let duckDuckGo = WebSearchEngine(
        id: "duckduckgo", name: "DuckDuckGo", keyword: "d",
        urlTemplate: "https://duckduckgo.com/?q={argument}", symbol: "hand.raised",
        suggestTemplate: "https://duckduckgo.com/ac/?type=list&q={argument}")
    static let bing = WebSearchEngine(
        id: "bing", name: "Bing", keyword: "b",
        urlTemplate: "https://www.bing.com/search?q={argument}", symbol: "globe",
        suggestTemplate: "https://api.bing.com/osjson.aspx?query={argument}")
    static let kagi = WebSearchEngine(
        id: "kagi", name: "Kagi", keyword: "k",
        urlTemplate: "https://kagi.com/search?q={argument}", symbol: "sparkle.magnifyingglass",
        suggestTemplate: "https://kagi.com/api/autosuggest?q={argument}")

    static let builtIn: [WebSearchEngine] = [google, duckDuckGo, bing, kagi]

    /// The one an unscoped "Search the Web" and a fresh install resolve to.
    static let `default` = google

    static func engine(id: String) -> WebSearchEngine? { builtIn.first { $0.id == id } }

    static let entryIDPrefix = "web-search:"

    var entryID: String { Self.entryIDPrefix + id }

    static func id(fromEntryID entryID: String) -> String? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return String(entryID.dropFirst(entryIDPrefix.count))
    }

    /// The `{argument}` a template with no `name=` declares; the engine fills it rather than prompting.
    static let argumentName = "Argument"

    /// Nil rather than a blank search: an empty query, a template missing its argument, or a
    /// result that isn't an absolute web URL are all "nothing to open", not an error to report.
    /// `context` is injected because expansion reads the clock and the clipboard.
    func url(for query: String, context: SnippetTemplateEngine.ExpansionContext) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, urlTemplate.contains("{argument") else { return nil }
        let expansion = SnippetTemplateEngine.expand(
            text: urlTemplate, context: context,
            userArguments: [Self.argumentName: trimmed], encoding: .percentEncoding)
        guard expansion.missingArguments.isEmpty, let url = URL(string: expansion.text),
            let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }

    /// Everything a query could otherwise mean to a URL, escaped — a suggest reply is worthless if
    /// the request it answers was rewritten by an `&` the user typed.
    private static let queryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#;?/")
        return allowed
    }()

    /// Where to ask what this query might become. **https only**, unlike `url(for:context:)`: an
    /// opened link is the user's own browser request, whereas this is the app posting keystrokes.
    func suggestURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let suggestTemplate, !trimmed.isEmpty,
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed),
            let url = URL(
                string: suggestTemplate.replacingOccurrences(of: "{argument}", with: encoded)),
            url.scheme?.lowercased() == "https"
        else { return nil }
        return url
    }
}
