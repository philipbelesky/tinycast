import Foundation

/// A bounded, memory-only cache for repeated Linear ticket lookups within one app launch.
struct LinearIssueSearchCache: Sendable {
    static let lifetime: TimeInterval = 5 * 60
    static let capacity = 20

    private struct Entry: Sendable {
        let fetchedAt: Date
        let targets: [LinearTarget]
    }

    private var entries: [LinearIssueLookup: Entry] = [:]

    func targets(for lookup: LinearIssueLookup, now: Date) -> [LinearTarget]? {
        guard let entry = entries[lookup], now.timeIntervalSince(entry.fetchedAt) < Self.lifetime else {
            return nil
        }
        return entry.targets
    }

    mutating func store(_ targets: [LinearTarget], for lookup: LinearIssueLookup, fetchedAt: Date) {
        if entries[lookup] == nil, entries.count >= Self.capacity,
            let oldest = entries.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key
        {
            entries.removeValue(forKey: oldest)
        }
        entries[lookup] = Entry(fetchedAt: fetchedAt, targets: targets)
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: false)
    }
}
