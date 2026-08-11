import Foundation

/// User-chosen scope keywords, layered over the shipped ones. See docs/features/palette.md#scope-keywords.
enum ScopeKeywords {
    /// Long enough for `gh` or `docs`, short enough that the space still arrives before a real word.
    static let maximumLength = 4

    /// Total on purpose: the field accepts anything and this is what the grammar ends up seeing.
    /// An empty result is a scope with no keyword, which is how a user turns one off.
    static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Adoption reads the token before the first space, so anything past one could never match.
        let token = trimmed.prefix { !$0.isWhitespace }
        return String(token.prefix(maximumLength))
    }

    /// The registry as the palette should see it. A duplicate keyword is stripped from the *later*
    /// scope rather than dropping either, so a bad backup can never make a token ambiguous.
    static func resolve(
        _ definitions: [ScopeDefinition], overrides: [String: String]
    ) -> [ScopeDefinition] {
        var taken: Set<String> = []
        return definitions.map { definition in
            var keyword = overrides[definition.id].map(normalized) ?? definition.keyword
            if keyword.isEmpty || !taken.insert(keyword).inserted { keyword = "" }
            return ScopeDefinition(
                keyword: keyword, id: definition.id, title: definition.title,
                symbol: definition.symbol, tint: definition.tint)
        }
    }

    /// The scope already holding `candidate`, for the field to refuse before it writes. Clearing a
    /// keyword never conflicts, however many scopes are already empty.
    static func conflict(
        for candidate: String, assignedTo scopeID: String, in definitions: [ScopeDefinition]
    ) -> ScopeDefinition? {
        let keyword = normalized(candidate)
        guard !keyword.isEmpty else { return nil }
        return definitions.first { $0.id != scopeID && $0.keyword == keyword }
    }
}
