import Foundation

/// The menu bar item stays through a short gap so a track boundary does not flicker it away.
struct MusicMenuBarPresence: Equatable, Sendable {
    static let grace: TimeInterval = 5
    private(set) var hiddenSince: Date?

    mutating func shows(preference: Bool, eligible: Bool, now: Date) -> Bool {
        guard preference else {
            hiddenSince = nil
            return false
        }
        if eligible {
            hiddenSince = nil
            return true
        }
        let since = hiddenSince ?? now
        if hiddenSince == nil { hiddenSince = now }
        return now.timeIntervalSince(since) < Self.grace
    }

    static func isEligible(monitored: Set<MusicPlayer>, snapshots: [MusicPlayer: MusicPlayback]) -> Bool {
        MusicPlayer.allCases.contains { player in
            guard monitored.contains(player), let state = snapshots[player] else { return false }
            let active = state.status == .playing || state.status == .paused
            return active && MusicCommandTarget.hasTrack(state)
        }
    }
}
