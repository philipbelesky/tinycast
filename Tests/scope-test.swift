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

        // MARK: - Custom keywords

        check("an unset keyword normalizes to nothing", ScopeKeywords.normalized("") == "")
        check("surrounding whitespace is trimmed", ScopeKeywords.normalized("  q  ") == "q")
        check("a keyword is lowercased, since adoption ignores case", ScopeKeywords.normalized("Q") == "q")
        check(
            "everything from the first inner space is dropped, so the space still commits",
            ScopeKeywords.normalized("go og") == "go")
        check(
            "an over-long keyword is truncated rather than rejected",
            ScopeKeywords.normalized("quicklinks") == "quic")
        check("the cap is what the field allows", ScopeKeywords.maximumLength == 4)

        check(
            "no override leaves the shipped keyword",
            ScopeKeywords.resolve(registry, overrides: [:]) == registry)
        let renamed = ScopeKeywords.resolve(registry, overrides: ["scope:quicklinks": "L"])
        check("an override replaces one keyword", renamed.first?.keyword == "l")
        check("and leaves the others alone", renamed.map(\.keyword) == ["l", "g", "e"])
        check(
            "the renamed scope is what the grammar now adopts",
            QueryScope.adopting("l ", in: renamed)?.scope.id == "scope:quicklinks")
        check(
            "and its shipped keyword no longer adopts",
            QueryScope.adopting("q ", in: renamed) == nil)
        check(
            "an override to empty leaves the scope unreachable rather than restoring the default",
            ScopeKeywords.resolve(registry, overrides: ["scope:quicklinks": ""]).first?.keyword == "")
        check(
            "an override for an unknown scope is ignored",
            ScopeKeywords.resolve(registry, overrides: ["scope:nope": "n"]) == registry)

        // A collision can only arrive from an edited backup or a stale write; the earlier scope keeps
        // the keyword, so the registry is never ambiguous about what a token adopts.
        let collided = ScopeKeywords.resolve(registry, overrides: ["scope:web:google": "q"])
        check("a collision leaves the earlier scope holding the keyword", collided[0].keyword == "q")
        check("and strips it from the later one", collided[1].keyword == "")
        check(
            "so a colliding token still adopts exactly one scope",
            QueryScope.adopting("q ", in: collided)?.scope.id == "scope:quicklinks")

        check(
            "a keyword already in use is reported as a conflict",
            ScopeKeywords.conflict(for: "g", assignedTo: "scope:quicklinks", in: registry)?.id
                == "scope:web:google")
        check(
            "a scope keeping its own keyword conflicts with nothing",
            ScopeKeywords.conflict(for: "q", assignedTo: "scope:quicklinks", in: registry) == nil)
        check(
            "an unused keyword conflicts with nothing",
            ScopeKeywords.conflict(for: "z", assignedTo: "scope:quicklinks", in: registry) == nil)
        check(
            "clearing a keyword conflicts with nothing, however many are already empty",
            ScopeKeywords.conflict(
                for: "", assignedTo: "scope:quicklinks",
                in: ScopeKeywords.resolve(registry, overrides: ["scope:emoji": ""])) == nil)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
