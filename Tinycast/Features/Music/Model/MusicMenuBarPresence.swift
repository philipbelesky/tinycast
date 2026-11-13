import Foundation

/// The menu bar item stays through a short gap so a track boundary does not flicker it away.
struct MusicMenuBarPresence: Equatable, Sendable {
    static let grace: TimeInterval = 5
    private(set) var hiddenSince: Date?
    private var wasShown = false

    mutating func shows(preference: Bool, eligible: Bool, now: Date) -> Bool {
        guard preference else {
            hiddenSince = nil
            wasShown = false
            return false
        }
        if eligible {
            hiddenSince = nil
            wasShown = true
            return true
        }
        guard wasShown else { return false }
        let since = hiddenSince ?? now
        if hiddenSince == nil { hiddenSince = now }
        wasShown = now.timeIntervalSince(since) < Self.grace
        return wasShown
    }

    static func isEligible(monitored: Set<MusicPlayer>, snapshots: [MusicPlayer: MusicPlayback]) -> Bool {
        MusicPlayer.allCases.contains { player in
            guard monitored.contains(player), let state = snapshots[player] else { return false }
            let active = state.status == .playing || state.status == .paused
            return active && MusicCommandTarget.hasTrack(state)
        }
    }
}
