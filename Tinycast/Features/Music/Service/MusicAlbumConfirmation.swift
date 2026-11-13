import Foundation

/// Music may acknowledge play before changing its queue, or briefly revert an unavailable cloud track.
enum MusicAlbumConfirmation {
    static let attemptLimit = 6

    @concurrent static func wait(
        for album: MusicAlbum, queueID: String,
        deadline: Date? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        read: @escaping @Sendable () async throws -> MusicPlayback,
        pause: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(500))
        }
    ) async throws -> MusicPlayback {
        let limit = deadline ?? now().addingTimeInterval(MusicOperationBudget.albumConfirmation)
        var matched = false
        var attempts = 0
        while attempts < attemptLimit, now() < limit {
            try Task.checkCancellation()
            try await pause()
            guard now() < limit else { break }
            var state = try await read()
            attempts += 1
            let currentMatches = state.queueID == queueID && album.tracks.contains(state.trackID)
                && (state.status == .playing || state.status == .paused)
            if currentMatches && matched {
                state.albumID = album.id
                return state
            }
            matched = currentMatches
        }
        throw MusicAutomationFailure("Music did not retain the selected album queue. Check its tracks in Music.")
    }
}
