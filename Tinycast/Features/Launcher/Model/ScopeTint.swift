import Foundation

/// A scope's tile colour, named rather than valued: `ScopeDefinition` lives in the pure layer and
/// `Theme` stays the only place a colour is chosen. See docs/ui.md#category-tiles.
/// Red is deliberately absent: on this surface it means destructive, and a tile means nothing at all.
enum ScopeTint: String, Sendable, CaseIterable {
    case blue, green, orange, purple, teal, indigo, pink, mint, brown, slate
}
