import Foundation

/// Listening history records observed track starts, including playback started outside Tinycast.
struct MusicListeningHistory: Codable, Sendable {
    struct Entry: Identifiable, Codable, Sendable {
        let id: UUID
        let player: MusicPlayer
        let playedAt: Date
        let playback: MusicPlayback
    }

    private(set) var entries: [Entry] = []
    private var observedTracks: [MusicPlayer: String] = [:]
    private enum CodingKeys: CodingKey { case entries }

    @discardableResult
    mutating func observe(_ state: MusicPlayback, player: MusicPlayer, at now: Date) -> Bool {
        if state.status == .stopped { observedTracks[player] = nil }
        guard state.status == .playing, !state.track.isEmpty else { return false }
        let identity = state.trackID.isEmpty
            ? "\(state.album)\u{1F}\(state.artist)\u{1F}\(state.track)" : state.trackID
        guard observedTracks[player] != identity else { return false }
        observedTracks[player] = identity
        entries.insert(Entry(id: UUID(), player: player, playedAt: now, playback: state), at: 0)
        entries = Array(entries.prefix(1000))
        return true
    }

    mutating func clear() {
        entries.removeAll()
    }
}
