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

        // MARK: - Suggest endpoints

        for engine in WebSearchEngine.builtIn {
            check(
                "\(engine.name) has a suggest endpoint, over https, carrying the query",
                {
                    guard let url = engine.suggestURL(for: "swift actors") else { return false }
                    return url.scheme == "https" && url.absoluteString.contains("swift%20actors")
                }())
        }
        check(
            "an engine with no suggest endpoint asks for nothing",
            WebSearchEngine(
                id: "custom", name: "Custom", keyword: "c",
                urlTemplate: "https://example.com/?q={argument}", symbol: "globe"
            ).suggestURL(for: "swift") == nil)
        check(
            "an empty query asks for nothing, so a bare keyword sends no keystrokes",
            WebSearchEngine.google.suggestURL(for: "   ") == nil)
        check(
            "a query that could add a parameter is encoded, not appended",
            WebSearchEngine.google.suggestURL(for: "tea&sugar=on")?.absoluteString
                .contains("tea%26sugar%3Don") == true)
        check(
            "a plaintext suggest endpoint is refused — a keystroke feed may not go in the clear",
            WebSearchEngine(
                id: "plain", name: "Plain", keyword: "p",
                urlTemplate: "https://example.com/?q={argument}", symbol: "globe",
                suggestTemplate: "http://example.com/ac?q={argument}"
            ).suggestURL(for: "swift") == nil)

        // MARK: - Parsing what a suggest endpoint answers

        /// The OpenSearch shape all four engines reply in.
        func reply(_ json: String) -> [String] {
            SearchSuggestions.parse(Data(json.utf8), typed: "swift act")
        }

        check(
            "the second element is the suggestion list, in the order it arrived",
            reply(#"["swift act",["swift actor","swift action","swift active"]]"#)
                == ["swift actor", "swift action", "swift active"])
        check(
            "Google's trailing metadata is ignored",
            reply(#"["swift act",["swift actor"],[],{"google:suggestsubtypes":[[512]]}]"#)
                == ["swift actor"])
        check(
            "the suggestion that repeats what was typed is dropped — its row is already above",
            reply(#"["swift act",["swift act","swift actor"]]"#) == ["swift actor"])
        check(
            "and case and surrounding space don't save it",
            reply(#"["swift act",["  Swift Act  ","swift actor"]]"#) == ["swift actor"])
        check(
            "duplicates collapse to the first",
            reply(#"["swift act",["swift actor","Swift Actor","swift action"]]"#)
                == ["swift actor", "swift action"])
        check(
            "no more than the row cap, however many arrive",
            SearchSuggestions.parse(
                Data(#"["q",["a","b","c","d","e","f","g","h","i"]]"#.utf8), typed: "q"
            ).count == SearchSuggestions.limit)
        check(
            "non-string elements are skipped rather than aborting the list",
            reply(#"["swift act",["swift actor",5,null,{"a":1},"swift action"]]"#)
                == ["swift actor", "swift action"])
        check(
            "a suggestion carrying a newline is dropped, since a row is one line",
            reply("[\"swift act\",[\"swift\\nactor\",\"swift action\"]]") == ["swift action"])
        check(
            "an absurdly long suggestion is dropped rather than truncated",
            reply(#"["swift act",["\#(String(repeating: "a", count: 200))","swift action"]]"#)
                == ["swift action"])
        check("empty data yields nothing", SearchSuggestions.parse(Data(), typed: "q").isEmpty)
        check("unparseable JSON yields nothing", reply("{not json").isEmpty)
        check("an object reply yields nothing", reply(#"{"suggestions":["a"]}"#).isEmpty)
        check("a one-element reply yields nothing", reply(#"["swift act"]"#).isEmpty)
        check(
            "a reply whose second element isn't a list yields nothing",
            reply(#"["swift act","swift actor"]"#).isEmpty)
        check(
            "a reply of nothing but the typed query yields nothing",
            reply(#"["swift act",["swift act"]]"#).isEmpty)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
