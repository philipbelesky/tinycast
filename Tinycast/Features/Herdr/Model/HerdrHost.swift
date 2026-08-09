import Foundation

/// Finds the GUI app hosting herdr. `herdr` is a terminal program, so the app to raise is whichever
/// bundle owns its pty — `herdr → zsh → login → Ghostty.app` on this machine.
enum HerdrHost {
    /// One process, flattened to what the walk needs. Injected, so the harness can test the walk.
    struct Entry: Equatable, Sendable {
        let pid: Int32
        let parentPID: Int32
        /// Set only for a process AppKit knows as a running application.
        let bundleID: String?

        init(pid: Int32, parentPID: Int32, bundleID: String?) {
            self.pid = pid
            self.parentPID = parentPID
            self.bundleID = bundleID
        }
    }

    /// The first bundled ancestor of `client`, or nil when the chain reaches launchd without one —
    /// herdr over ssh or mosh has no local app to raise, and that is a normal outcome, not a failure.
    static func bundleID(forClient client: Int32, in table: [Entry]) -> String? {
        var byPID: [Int32: Entry] = [:]
        for entry in table { byPID[entry.pid] = entry }
        var seen: Set<Int32> = []
        var current = client
        // Bounded by `seen`: a pid cycle is impossible on a healthy system and fatal if trusted.
        while let entry = byPID[current], seen.insert(current).inserted {
            if let bundleID = entry.bundleID, current != client { return bundleID }
            current = entry.parentPID
        }
        return nil
    }
}
