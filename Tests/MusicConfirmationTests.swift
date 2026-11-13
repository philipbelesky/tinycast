import Foundation
import Synchronization

@main
@MainActor
struct MusicConfirmationTests {
    static func main() async throws {
        let album = MusicAlbum(id: "album", title: "Album", artist: "Artist", tracks: ["track"])
        let waiting = MusicPlayback(status: .paused, trackID: "old", queueID: "old-queue")
        let playing = MusicPlayback(status: .playing, trackID: "track", queueID: "new-queue")
        let delayed = MusicConfirmationFixture([waiting, waiting, playing, playing])
        let state = try await MusicAlbumConfirmation.wait(for: album, queueID: "new-queue",
            read: { await delayed.read() }, pause: {})
        assert(state.albumID == album.id && delayed.readCount == 4)

        let reverted = MusicConfirmationFixture([playing, waiting])
        do {
            _ = try await MusicAlbumConfirmation.wait(for: album, queueID: "new-queue",
                read: { await reverted.read() }, pause: {})
            assertionFailure("A transient playing state must not confirm the album")
        } catch { assert(reverted.readCount == 6) }

        let wrongQueue = MusicConfirmationFixture([MusicPlayback(status: .playing, trackID: "track", queueID: "other")])
        do {
            _ = try await MusicAlbumConfirmation.wait(for: album, queueID: "new-queue",
                read: { await wrongQueue.read() }, pause: {})
            assertionFailure("A matching track in the wrong queue must not confirm the album")
        } catch { assert(wrongQueue.readCount == 6) }
        let stale = MusicConfirmationFixture([waiting, playing])
        let toggled = try await MusicToggleConfirmation.wait(from: .paused, reply: waiting,
            read: { stale.read() }, pause: {})
        assert(toggled.status == .playing && stale.readCount == 2)

        let prompt = MusicConfirmationFixture([waiting])
        let immediate = try await MusicToggleConfirmation.wait(from: .paused, reply: playing,
            read: { prompt.read() }, pause: {})
        assert(immediate.status == .playing && prompt.readCount == 0)

        let unchanged = MusicConfirmationFixture([waiting])
        let ignored = try await MusicToggleConfirmation.wait(from: .paused, reply: waiting,
            read: { unchanged.read() }, pause: {})
        assert(ignored.status == .paused && unchanged.readCount == 20, "An ignored toggle reports its real state")

        let started = Date(timeIntervalSince1970: 0)
        let budget = MusicOperationBudget(seconds: 8, now: started)
        assert(budget.eventTimeout(at: started) == 8)
        assert(budget.eventTimeout(at: started.addingTimeInterval(6)) == 2)
        assert(budget.eventTimeout(at: started.addingTimeInterval(8)) == nil)
        assert(MusicOperationBudget(seconds: 1, now: started).eventTimeout(at: started) == 1)

        let albumClock = Mutex(Date(timeIntervalSince1970: 10_000))
        let slowAlbum = MusicConfirmationFixture([waiting])
        do {
            _ = try await MusicAlbumConfirmation.wait(
                for: album, queueID: "new-queue",
                now: { albumClock.withLock { $0 } },
                read: {
                    albumClock.withLock { $0.addTimeInterval(2) }
                    return await slowAlbum.read()
                },
                pause: {})
            assertionFailure("A slow album read must stop at the deadline")
        } catch {
            let reads = await slowAlbum.readCount
            assert(reads == 2, "album confirmation started \(reads) reads after the deadline")
        }

        var toggleClock = Date(timeIntervalSince1970: 20_000)
        let slowToggle = MusicConfirmationFixture([waiting])
        let stalled = try await MusicToggleConfirmation.wait(
            from: .paused, reply: waiting, now: { toggleClock },
            read: {
                toggleClock.addTimeInterval(2)
                return slowToggle.read()
            },
            pause: {})
        assert(stalled.status == .paused && slowToggle.readCount == 1,
            "toggle confirmation started \(slowToggle.readCount) reads past its one-second deadline")
        print("Delayed album changes, transient fallback, wrong-queue and toggle confirmation checks passed")
    }
}

@MainActor
private final class MusicConfirmationFixture {
    private let states: [MusicPlayback]
    private(set) var readCount = 0
    init(_ states: [MusicPlayback]) { self.states = states }
    func read() -> MusicPlayback {
        let state = states[min(readCount, states.count - 1)]
        readCount += 1
        return state
    }
}
