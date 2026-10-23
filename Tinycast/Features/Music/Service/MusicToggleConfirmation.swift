import Foundation

/// Music answers play/pause before its player state flips, so the reply would report the old state.
@MainActor
enum MusicToggleConfirmation {
    static func wait(
        from previous: MusicPlayback.Status, reply: MusicPlayback,
        read: () async throws -> MusicPlayback,
        pause: () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(50))
        }
    ) async throws -> MusicPlayback {
        var state = reply
        for _ in 0..<20 where state.status == previous {
            try Task.checkCancellation()
            try await pause()
            state = try await read()
        }
        return state
    }
}
