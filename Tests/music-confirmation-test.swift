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
        print("Delayed album changes, transient fallback and wrong-queue confirmation checks passed")
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
