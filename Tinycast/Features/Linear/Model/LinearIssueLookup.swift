import Foundation

/// A ticket lookup inferred from the Linear scope's typed query.
enum LinearIssueLookup: Equatable, Hashable, Sendable {
    case number(Int)
    case identifier(teamKey: String, number: Int)
    case title(String)

    static let minimumTitleLength = 3

    /// Numbers search every team; full identifiers one team; longer text searches titles.
    static func parse(_ rawQuery: String) -> LinearIssueLookup? {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        if query.allSatisfy(\.isNumber) {
            guard let number = Int(query), number > 0 else { return nil }
            return .number(number)
        }
        let parts = query.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 2, let key = parts.first, let value = parts.last, !value.isEmpty,
            key.first?.isLetter == true, key.allSatisfy({ $0.isLetter || $0.isNumber }),
            value.allSatisfy(\.isNumber)
        {
            guard let number = Int(value), number > 0 else { return nil }
            return .identifier(teamKey: key.uppercased(), number: number)
        }
        guard query.count >= minimumTitleLength else { return nil }
        return .title(query)
    }
}
