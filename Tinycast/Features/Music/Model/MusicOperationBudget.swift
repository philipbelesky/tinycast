import Foundation

/// One runner operation's wall-clock limit. A fresh 8s timeout on every event can hold the queue for a minute.
struct MusicOperationBudget: Sendable, Equatable {
    static let eventCap: TimeInterval = 8
    static let state: TimeInterval = 8
    static let transport: TimeInterval = 8
    static let rate: TimeInterval = 8
    static let toggleConfirmation: TimeInterval = 1
    static let albumConfirmation: TimeInterval = 3

    let deadline: Date

    init(seconds: TimeInterval, now: Date) {
        deadline = now.addingTimeInterval(seconds)
    }

    /// Nil once the budget is spent, so the caller must not start another event.
    func eventTimeout(at now: Date) -> TimeInterval? {
        let remaining = deadline.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        return min(Self.eventCap, remaining)
    }
}
