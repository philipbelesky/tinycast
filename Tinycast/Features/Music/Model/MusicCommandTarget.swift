import Foundation

/// Which monitored player a rating command or the menu bar panel acts on.
enum MusicCommandTarget {
    static func player(
        monitored: Set<MusicPlayer>, snapshots: [MusicPlayer: MusicPlayback], preferred: MusicPlayer
    ) -> MusicPlayer? {
        let playing = candidates(monitored, snapshots, status: .playing)
        if playing.contains(preferred) { return preferred }
        if let playing = playing.first { return playing }
        let paused = candidates(monitored, snapshots, status: .paused)
        if paused.contains(preferred) { return preferred }
        return paused.first
    }

    static func playersWithTracks(
        monitored: Set<MusicPlayer>, snapshots: [MusicPlayer: MusicPlayback]
    ) -> [MusicPlayer] {
        MusicPlayer.allCases.filter { monitored.contains($0) && hasTrack(snapshots[$0]) }
    }

    static func hasTrack(_ state: MusicPlayback?) -> Bool {
        guard let state else { return false }
        return !state.trackID.isEmpty || !state.track.isEmpty
    }

    private static func candidates(
        _ monitored: Set<MusicPlayer>, _ snapshots: [MusicPlayer: MusicPlayback],
        status: MusicPlayback.Status
    ) -> [MusicPlayer] {
        MusicPlayer.allCases.filter {
            monitored.contains($0) && snapshots[$0]?.status == status && hasTrack(snapshots[$0])
        }
    }
}
