enum SyncTrigger: Sendable {
    case startup, localChange, remoteNotification
}

enum SyncDecision: Equatable, Sendable {
    case noop, writeLocal, applyRemote
}

/// Decides which way a sync pass moves data, from content hashes alone. docs/features/sync.md
enum SyncPlan {
    /// KVS caps a value at 1 MB; the headroom keeps a near-limit write from failing mid-flight.
    static let maximumPayloadBytes = 900 * 1024

    static func fitsQuota(byteCount: Int) -> Bool {
        byteCount <= maximumPayloadBytes
    }

    static func decide(
        trigger: SyncTrigger,
        localHash: String,
        remoteHash: String?,
        syncedLocalHash: String?,
        syncedRemoteHash: String?
    ) -> SyncDecision {
        // An absent envelope means iCloud has nothing yet — seed it, never clear local state.
        guard let remoteHash else { return .writeLocal }
        if remoteHash == localHash { return .noop }
        let localChanged = localHash != syncedLocalHash
        let remoteChanged = remoteHash != syncedRemoteHash
        switch (localChanged, remoteChanged) {
        case (false, false): return .noop
        case (true, false): return .writeLocal
        case (false, true): return .applyRemote
        // Both moved: a local edit is what the user just did here, so it wins on that trigger.
        case (true, true): return trigger == .localChange ? .writeLocal : .applyRemote
        }
    }
}
