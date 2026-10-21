import Foundation

/// Music may acknowledge play before changing its queue, or briefly revert an unavailable cloud track.
enum MusicAlbumConfirmation {
    @concurrent static func wait(
        for album: MusicAlbum, queueID: String,
        read: @escaping @Sendable () async throws -> MusicPlayback,
        pause: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(500))
        }
    ) async throws -> MusicPlayback {
        var matched = false
        for _ in 0..<6 {
            try Task.checkCancellation()
            try await pause()
            var state = try await read()
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
