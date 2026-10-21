import Foundation

@main
@MainActor
struct MusicServiceTest {
    static func main() async throws {
        let suite = "tinycast-music-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appending(path: suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let file = directory.appending(path: "history.json")
        let store = MusicStore(defaults: defaults, historyURL: file)
        store.load()
        assert(store.monitored.isEmpty && !store.remoteEnabled && !store.historyEnabled)
        store.setMonitoring(.appleMusic, enabled: true)
        store.setMonitoring(.tvTunes, enabled: true)
        store.setHistoryEnabled(true)
        let fake = MusicFakePlayer()
        var now = Date(timeIntervalSince1970: 1_000)
        let service = MusicPlaybackService(store: store, runner: fake, now: { now })

        let first = await service.perform(.nextAlbum, player: .appleMusic)
        assert(first.status == .playing && !service.canPrevious(.appleMusic))
        let second = await service.perform(.nextAlbum, player: .appleMusic)
        assert(first.albumID != second.albumID && service.canPrevious(.appleMusic))
        let back = await service.perform(.previousAlbum, player: .appleMusic)
        assert(back.albumID == first.albumID)
        let forward = await service.perform(.nextAlbum, player: .appleMusic)
        assert(forward.albumID == second.albumID)
        assert(!service.canPrevious(.tvTunes))

        async let result1 = service.remoteCommand(id: "same-press", command: .toggle)
        async let result2 = service.remoteCommand(id: "same-press", command: .toggle)
        let duplicate = await (result1, result2)
        assert(duplicate.0.status == duplicate.1.status)
        assert(fake.transportCount == 1)
        let conflict = await service.remoteCommand(id: "same-press", command: .nextTrack)
        assert(conflict.status == .error && fake.transportCount == 1)

        store.selectedPlayer = .tvTunes
        let replay = await service.remoteCommand(id: "same-press", command: .toggle)
        assert(replay.source == "APPLE MUSIC" && fake.transportCount == 1)
        fake.failTransport = true
        let failed = await service.remoteCommand(id: "failed-press", command: .nextTrack)
        let retry = await service.remoteCommand(id: "failed-press", command: .nextTrack)
        assert(failed.status == .error && retry.status == .error && fake.transportCount == 2)
        fake.failTransport = false
        now.addTimeInterval(11)
        await service.refresh()
        assert(store.snapshots[.tvTunes]?.status != .error, "State polling must recover an uncertain command result")
        let failedReplay = await service.remoteCommand(id: "failed-press", command: .nextTrack)
        assert(failedReplay.status == .error && fake.transportCount == 2, "Recovery must never replay a command")

        store.selectedPlayer = .appleMusic
        fake.readFailures[.appleMusic] = [MusicAutomationFailure("Player read timed out.")]
        let timeout = await service.refresh(.appleMusic)
        assert(timeout.status == .error)
        let readsBeforeRecovery = fake.readCounts[.appleMusic]
        await service.refresh()
        assert(fake.readCounts[.appleMusic] == readsBeforeRecovery, "Failed reads need a retry delay")
        now.addTimeInterval(11)
        await service.refresh()
        assert(fake.readCounts[.appleMusic] == readsBeforeRecovery! + 1)
        assert(service.remoteState().status != .error)
        assert(store.snapshots[.appleMusic]?.status != .error)
        assert(fake.transportCount == 2 && fake.authorizationCount == 0)

        fake.readFailures[.appleMusic] = [MusicAutomationFailure("Automation denied.", requiresReconnect: true)]
        _ = await service.refresh(.appleMusic)
        let readsAfterDenial = fake.readCounts[.appleMusic]
        now.addTimeInterval(60)
        await service.refresh()
        assert(fake.readCounts[.appleMusic] == readsAfterDenial, "Permission failures require explicit reconnect")
        assert(store.snapshots[.appleMusic]?.status == .error)
        await service.connect(.appleMusic)
        assert(fake.authorizationCount == 1 && store.snapshots[.appleMusic]?.status != .error)
        store.selectedPlayer = .tvTunes

        let restored = MusicStore(defaults: defaults, historyURL: file)
        restored.load()
        assert(restored.listeningHistory.entries.count >= 2)
        assert(restored.monitored == store.monitored && restored.historyEnabled)
        assert(restored.selectedPlayer == .tvTunes)

        fake.blockRead = true
        let count = fake.playCount
        let pending = Task { await service.perform(.nextAlbum, player: .appleMusic) }
        while fake.readContinuation == nil { await Task.yield() }
        await service.setMonitoring(.appleMusic, enabled: false)
        fake.readContinuation?.resume()
        fake.readContinuation = nil
        let cancelled = await pending.value
        assert(cancelled.status == .error && fake.playCount == count)
        assert(store.snapshots[.appleMusic] == nil)

        let damagedURL = directory.appending(path: "damaged-history.json")
        let damaged = Data("not a history file".utf8)
        try damaged.write(to: damagedURL)
        let damagedStore = MusicStore(defaults: defaults, historyURL: damagedURL)
        damagedStore.load()
        damagedStore.setHistoryEnabled(true)
        damagedStore.observe(fake.playback, player: .tvTunes, at: Date())
        let preserved = try Data(contentsOf: damagedURL)
        assert(preserved == damaged)
        damagedStore.clearHistory()
        let cleared = try JSONDecoder().decode(MusicListeningHistory.self, from: Data(contentsOf: damagedURL))
        assert(cleared.entries.isEmpty && damagedStore.persistenceError == nil)
        service.stop()
        print("Music service sequencing, deduplication, history persistence and disconnect checks passed")
    }
}

@MainActor
private final class MusicFakePlayer: MusicPlayerControlling {
    var transportCount = 0
    var playCount = 0
    var failTransport = false
    var blockRead = false
    var readFailures: [MusicPlayer: [MusicAutomationFailure]] = [:]
    var readCounts: [MusicPlayer: Int] = [:]
    var authorizationCount = 0
    var readContinuation: CheckedContinuation<Void, Never>?
    var playback = MusicPlayback()

    func authorize(_ player: MusicPlayer) async throws { authorizationCount += 1 }

    func state(_ player: MusicPlayer) async throws -> MusicPlayback {
        readCounts[player, default: 0] += 1
        if readFailures[player]?.isEmpty == false { throw readFailures[player]!.removeFirst() }
        if blockRead {
            blockRead = false
            await withCheckedContinuation { readContinuation = $0 }
        }
        return playback
    }

    func albums(_ player: MusicPlayer) async throws -> [MusicAlbum] {
        [MusicAlbum(id: "a", title: "First", artist: "Artist"),
         MusicAlbum(id: "b", title: "Second", artist: "Artist")]
    }

    func transport(_ command: MusicCommand, player: MusicPlayer) async throws -> MusicPlayback {
        transportCount += 1
        if failTransport { throw MusicAutomationFailure("Playback result unknown.") }
        playback.status = playback.status == .playing ? .paused : .playing
        return playback
    }

    func play(_ album: MusicAlbum, player: MusicPlayer) async throws -> MusicPlayback {
        playCount += 1
        playback = MusicPlayback(status: .playing, album: album.title, artist: album.artist,
            track: album.title + " track", albumID: album.id, trackID: album.id + "1")
        return playback
    }
}
