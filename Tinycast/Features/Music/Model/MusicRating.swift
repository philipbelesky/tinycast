import Foundation

/// Half-stars from 0 to 10. Zero is ratable but unrated; nil on a playback is a different fact.
struct MusicRating: Equatable, Sendable, Hashable {
    static let maximumHalfStars = 10

    var halfStars: Int

    static let unrated = MusicRating(halfStars: 0)

    init(halfStars: Int) {
        self.halfStars = min(Self.maximumHalfStars, max(0, halfStars))
    }

    var wholeStars: Int { halfStars / 2 }
    var hasHalfStar: Bool { !halfStars.isMultiple(of: 2) }

    enum StarFill: Equatable, Sendable {
        case empty, half, full
    }

    func fill(for star: Int) -> StarFill {
        if star <= wholeStars { return .full }
        if hasHalfStar && star == wholeStars + 1 { return .half }
        return .empty
    }

    var hudGlyphs: String {
        String(repeating: "★", count: wholeStars) + String(repeating: "☆", count: 5 - wholeStars)
    }

    static func whole(_ stars: Int) -> Self {
        Self(halfStars: min(5, max(0, stars)) * 2)
    }

    /// A computed value is the album's or absent, so it must not appear as the user's stars.
    static func apple(points: Int, kind: String) -> Self {
        guard kind.caseInsensitiveCompare("computed") != .orderedSame else { return .unrated }
        return Self(halfStars: min(100, max(0, points)) / 10)
    }

    var applePoints: Int { wholeStars * 20 }

    /// Missing, negative, or out of range is the contract's "cannot be rated".
    static func tvTunes(_ value: Int?) -> Self? {
        guard let value, (0...maximumHalfStars).contains(value) else { return nil }
        return Self(halfStars: value)
    }

    var tvTunesValue: Int { halfStars }
}
