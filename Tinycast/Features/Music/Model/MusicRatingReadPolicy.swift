import Foundation

/// The last resolved rating for one player. The runner stores it; the policy only decides when it is stale.
struct MusicRatingCache: Equatable, Sendable {
    var trackID: String
    var rating: MusicRating?
    var readAt: Date
}

enum MusicRatingReadPolicy {
    static let freshness: TimeInterval = 30

    static func needsRead(
        cached: MusicRatingCache?, trackID: String, now: Date, afterOwnWrite: Bool
    ) -> Bool {
        guard !trackID.isEmpty else { return false }
        if afterOwnWrite { return true }
        guard let cached, cached.trackID == trackID else { return true }
        return now.timeIntervalSince(cached.readAt) >= freshness
    }
}
