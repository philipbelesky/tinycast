import Foundation

@main
struct WebSearchTest {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // Fixed, because a search template must not depend on the machine it expands on.
        let context = SnippetTemplateEngine.ExpansionContext(
            clipboardHistory: ["copied"],
            selection: "picked",
            now: Date(timeIntervalSince1970: 1_700_000_000),
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(identifier: "UTC")!)

        let google = WebSearchEngine.google

        // MARK: - The catalogue

        check("Google is the default engine", WebSearchEngine.default == google)
        check(
            "every built-in template takes an argument",
            WebSearchEngine.builtIn.allSatisfy { $0.urlTemplate.contains("{argument") })
        check(
            "every built-in resolves by id",
            WebSearchEngine.builtIn.allSatisfy { WebSearchEngine.engine(id: $0.id) == $0 })
        check("an unknown id resolves to nil", WebSearchEngine.engine(id: "askjeeves") == nil)
        check(
            "engine ids are unique",
            Set(WebSearchEngine.builtIn.map(\.id)).count == WebSearchEngine.builtIn.count)
        check(
            "engine keywords are unique",
            Set(WebSearchEngine.builtIn.map(\.keyword)).count == WebSearchEngine.builtIn.count)
        check(
            "no engine keyword collides with a filter or mode keyword",
            WebSearchEngine.builtIn.allSatisfy { engine in
                !["a", "q", "s", "c", "w", "e", "v"].contains(engine.keyword)
            })

        // MARK: - Launcher entry identity

        check("an entry id carries the engine", google.entryID == "web-search:google")
        check(
            "the engine round-trips out of its entry id",
            WebSearchEngine.id(fromEntryID: google.entryID) == google.id)
        check(
            "another kind's entry id yields no engine",
            WebSearchEngine.id(fromEntryID: "quicklink:1234") == nil)
        check(
            "entry ids are unique across the built-ins",
            Set(WebSearchEngine.builtIn.map(\.entryID)).count == WebSearchEngine.builtIn.count)

        // MARK: - URL building

        check(
            "a plain query lands in the query string",
            google.url(for: "swift", context: context)?.absoluteString
                == "https://www.google.com/search?q=swift")
        check(
            "spaces are percent-encoded, never left raw",
            google.url(for: "swift actors", context: context)?.absoluteString
                == "https://www.google.com/search?q=swift%20actors")
        check(
            "a query cannot inject a second parameter",
            google.url(for: "a&b=c", context: context)?.absoluteString
                == "https://www.google.com/search?q=a%26b%3Dc")
        check(
            "a query cannot escape the path",
            google.url(for: "x/../y?z", context: context)?.absoluteString
                == "https://www.google.com/search?q=x%2F..%2Fy%3Fz")
        check(
            "unicode survives as UTF-8 percent escapes",
            google.url(for: "café", context: context)?.absoluteString
                == "https://www.google.com/search?q=caf%C3%A9")
        check(
            "surrounding whitespace is trimmed before encoding",
            google.url(for: "  swift  ", context: context)?.absoluteString
                == "https://www.google.com/search?q=swift")

        // MARK: - Refusals

        check("an empty query builds no URL", google.url(for: "", context: context) == nil)
        check(
            "a whitespace-only query builds no URL",
            google.url(for: "   ", context: context) == nil)
        check(
            "a template that lost its argument builds no URL",
            WebSearchEngine(
                id: "broken", name: "Broken", keyword: "b",
                urlTemplate: "https://example.com/search", symbol: "globe")
                .url(for: "swift", context: context) == nil)
        check(
            "a template that isn't a URL builds no URL",
            WebSearchEngine(
                id: "nonsense", name: "Nonsense", keyword: "n",
                urlTemplate: "not a url {argument}", symbol: "globe")
                .url(for: "swift", context: context) == nil)

        // MARK: - Every built-in actually resolves

        for engine in WebSearchEngine.builtIn {
            check(
                "\(engine.name) builds an https URL carrying the query",
                {
                    guard let url = engine.url(for: "swift actors", context: context) else {
                        return false
                    }
                    return url.scheme == "https" && url.absoluteString.contains("swift%20actors")
                }())
        }

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
