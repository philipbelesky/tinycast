import Foundation

/// One entry in the scope registry. The id is opaque here: `ScopeCatalog` owns what it points at,
/// because a target names `AppEntry.Kind` and `PaletteMode`, and neither compiles without AppKit.
struct ScopeDefinition: Equatable, Hashable, Sendable, Identifiable {
    /// Typed before the space that commits it, so it can hold no whitespace of its own.
    let keyword: String
    let id: String
    /// What the chip reads, and the section title while the scope is filtering.
    let title: String
    let symbol: String
}

/// The palette's scope grammar. See docs/features/palette.md#scope-keywords.
enum QueryScope {
    struct Adoption: Equatable, Sendable {
        let scope: ScopeDefinition
        /// Whatever followed the committing space — empty when typed, a tail when pasted.
        let remainder: String
    }

    /// Adoption is a *transition* into `keyword + " "`, never a reading of the text: a scope that
    /// popped back into the field as `"q"` would otherwise re-adopt itself on the next render.
    static func adopting(_ query: String, in registry: [ScopeDefinition]) -> Adoption? {
        guard let space = query.firstIndex(of: " ") else { return nil }
        let token = String(query[query.startIndex..<space])
        guard !token.isEmpty else { return nil }
        let scope = registry.first {
            !$0.keyword.isEmpty && $0.keyword.compare(token, options: .caseInsensitive) == .orderedSame
        }
        guard let scope else { return nil }
        return Adoption(
            scope: scope, remainder: String(query[query.index(after: space)...]))
    }

    /// What goes back in the field when a scope is popped: the token, minus the space that committed it.
    static func popped(_ scope: ScopeDefinition) -> String { scope.keyword }
}
