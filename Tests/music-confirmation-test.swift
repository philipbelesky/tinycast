import Foundation

@main
@MainActor
struct MusicConfirmationTest {
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
