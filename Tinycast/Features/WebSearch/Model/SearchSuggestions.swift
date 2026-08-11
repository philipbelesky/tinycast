import Foundation

/// An OpenSearch suggestion reply — `["typed", ["first", "second", …], …]`, which is the shape all
/// four engines answer in. See docs/features/web-search.md#suggestions.
enum SearchSuggestions {
    /// The list is a shortcut past typing, not a page of results.
    static let limit = 6
    /// Longer than any query worth completing, and long enough that a row would truncate anyway.
    static let maximumLength = 120

    /// Total on purpose: a malformed, hostile or empty reply is "no suggestions", never an error.
    /// `typed` is dropped from the list — the row that searches for it verbatim is already above.
    static func parse(_ data: Data, typed: String) -> [String] {
        guard !data.isEmpty,
            let reply = try? JSONSerialization.jsonObject(with: data) as? [Any],
            reply.count > 1, let candidates = reply[1] as? [Any]
        else { return [] }

        let typedKey = key(typed)
        var seen: Set<String> = [typedKey]
        var suggestions: [String] = []
        for candidate in candidates {
            guard suggestions.count < limit, let text = candidate as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= maximumLength,
                // A row is one line, and a control character in it is a reply worth distrusting.
                trimmed.rangeOfCharacter(from: .controlCharacters) == nil,
                seen.insert(key(trimmed)).inserted
            else { continue }
            suggestions.append(trimmed)
        }
        return suggestions
    }

    /// Identity for deduplication: what the user would consider the same search.
    private static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The row id, shared by the screen that indexes rows and the list that draws them — two
    /// spellings of it would misalign the selection from the row under it.
    static func rowID(_ suggestion: String) -> String { "suggestion:" + suggestion }
}
