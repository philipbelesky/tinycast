import Foundation

/// A scope's tile colour, named rather than valued: `ScopeDefinition` lives in the pure layer and
/// `Theme` stays the only place a colour is chosen. See docs/ui.md#category-tiles.
enum ScopeTint: String, Sendable, CaseIterable {
    case red, blue, teal, orange, purple, brown, black, indigo, yellow, slate
}
