import Foundation

/// Music answers play/pause before its player state flips, so the reply would report the old state.
@MainActor
enum MusicToggleConfirmation {
    static let attemptLimit = 20

    static func wait(
        from previous: MusicPlayback.Status, reply: MusicPlayback,
        deadline: Date? = nil,
        now: () -> Date = Date.init,
        read: () async throws -> MusicPlayback,
        pause: () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(50))
        }
    ) async throws -> MusicPlayback {
        let limit = deadline ?? now().addingTimeInterval(MusicOperationBudget.toggleConfirmation)
        var state = reply
        var attempts = 0
        while state.status == previous, attempts < attemptLimit, now() < limit {
            try Task.checkCancellation()
            try await pause()
            guard now() < limit else { break }
            state = try await read()
            attempts += 1
        }
        return state
    }
}
