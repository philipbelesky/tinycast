import Foundation

@main
struct ScopeTest {
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

        let quicklinks = ScopeDefinition(
            keyword: "q", id: "scope:quicklinks", title: "Quicklinks", symbol: "link")
        let google = ScopeDefinition(
            keyword: "g", id: "scope:web:google", title: "Google", symbol: "globe")
        let emoji = ScopeDefinition(
            keyword: "e", id: "scope:emoji", title: "Emoji & Symbols", symbol: "face.smiling")
        let registry = [quicklinks, google, emoji]

        // MARK: - Adoption is a transition, not a parse

        check(
            "a keyword plus space adopts the scope",
            QueryScope.adopting("q ", in: registry)
                == QueryScope.Adoption(scope: quicklinks, remainder: ""))
        check(
            "the keyword alone adopts nothing — the space is the commit",
            QueryScope.adopting("q", in: registry) == nil)
        check(
            "an unregistered token is left alone",
            QueryScope.adopting("z ", in: registry) == nil)
        check(
            "a word that merely starts with a keyword is left alone",
            QueryScope.adopting("quicklinks ", in: registry) == nil)
        check(
            "text before the keyword is left alone",
            QueryScope.adopting("open q ", in: registry) == nil)
        check("empty text adopts nothing", QueryScope.adopting("", in: registry) == nil)
        check("a bare space adopts nothing", QueryScope.adopting(" ", in: registry) == nil)

        // MARK: - Case and pasted remainders

        check(
            "matching is case-insensitive",
            QueryScope.adopting("Q ", in: registry)?.scope == quicklinks)
        check(
            "a pasted remainder survives the commit",
            QueryScope.adopting("g swift actors", in: registry)
                == QueryScope.Adoption(scope: google, remainder: "swift actors"))
        check(
            "only the first space is consumed",
            QueryScope.adopting("g  padded", in: registry)?.remainder == " padded")

        // MARK: - Popping, and why it can't re-adopt

        check("popping restores the token", QueryScope.popped(quicklinks) == "q")
        check(
            "the restored token has no trailing space, so it cannot re-adopt",
            QueryScope.adopting(QueryScope.popped(quicklinks), in: registry) == nil)

        // MARK: - Registry integrity

        check(
            "keywords are unique",
            Set(registry.map(\.keyword)).count == registry.count)
        check(
            "ids are unique",
            Set(registry.map(\.id)).count == registry.count)
        check(
            "a duplicate keyword resolves to the first definition",
            QueryScope.adopting("q ", in: registry + [
                ScopeDefinition(keyword: "q", id: "scope:other", title: "Other", symbol: "star")
            ])?.scope == quicklinks)
        check(
            "a keyword carrying whitespace can never be typed, so it never matches",
            QueryScope.adopting("bad word ", in: [
                ScopeDefinition(keyword: "bad word", id: "scope:bad", title: "Bad", symbol: "star")
            ]) == nil)
        check(
            "an empty keyword never matches",
            QueryScope.adopting(" ", in: [
                ScopeDefinition(keyword: "", id: "scope:blank", title: "Blank", symbol: "star")
            ]) == nil)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
