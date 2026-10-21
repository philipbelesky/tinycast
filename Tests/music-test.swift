import Foundation

@main
struct MusicTest {
    static func main() throws {
        var history = MusicAlbumHistory()
        assert(history.target(.previousAlbum, candidates: ["a", "b"], current: nil) == nil)
        history.confirm("a")
        history.confirm("b")
        assert(history.target(.previousAlbum, candidates: [], current: "b") == "a")
        history.confirm("a")
        assert(history.target(.nextAlbum, candidates: ["c"], current: "a") == "b")
        history.confirm("b")
        assert(history.target(.nextAlbum, candidates: ["b", "c"], current: "b") == "c")
        assert(history.target(.nextAlbum, candidates: [], current: "b") == nil)

        var listens = MusicListeningHistory()
        let now = Date(timeIntervalSince1970: 1234)
        var state = MusicPlayback(status: .playing, album: "Album", artist: "Artist", track: "Track", albumID: "a", trackID: "t")
        assert(listens.observe(state, player: .appleMusic, at: now))
        assert(!listens.observe(state, player: .appleMusic, at: now))
        state.status = .paused
        assert(!listens.observe(state, player: .appleMusic, at: now))
        state.status = .playing
        assert(!listens.observe(state, player: .appleMusic, at: now))
        assert(listens.observe(state, player: .tvTunes, at: now))
        state.trackID = "next"
        assert(listens.observe(state, player: .appleMusic, at: now))
        state.status = .error
        assert(!listens.observe(state, player: .appleMusic, at: now))
        let restored = try JSONDecoder().decode(MusicListeningHistory.self, from: JSONEncoder().encode(listens))
        assert(restored.entries.count == 3)
        assert(restored.entries.first?.player == .appleMusic)
        assert(restored.entries.first?.playedAt == now)

        let hello = Data(#"{"type":"hello","token":"a-test-token-that-is-long-enough"}"#.utf8)
        assert(MusicRemoteMessage.parse(hello) == .hello("a-test-token-that-is-long-enough"))
        let command = Data(#"{"type":"command","id":"1","command":"next_album"}"#.utf8)
        assert(MusicRemoteMessage.parse(command) == .command("1", .nextAlbum))
        assert(MusicRemoteMessage.parse(Data(#"{"type":"command","id":"","command":"toggle"}"#.utf8)) == nil)
        assert(MusicRemoteMessage.parse(Data(#"{"type":"telemetry","battery_percent":true}"#.utf8)) == nil)
        assert(MusicRemoteMessage.parse(Data(#"{"type":"telemetry","battery_percent":101}"#.utf8)) == nil)
        assert(MusicRemoteMessage.parse(Data(#"{"type":"telemetry","battery_percent":44}"#.utf8)) == .telemetry(44))
        assert(MusicRemoteMessage.parse(Data(repeating: 32, count: 4097)) == nil)
        assert(MusicRemoteMessage.tokensMatch("abc", "abc"))
        assert(!MusicRemoteMessage.tokensMatch("abc", "abd"))
        let wire = MusicRemoteState(player: .tvTunes, playback: state, canPrevious: false, ack: "press-1")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(wire)) as? [String: Any]
        assert(object?["type"] as? String == "state")
        assert(object?["source"] as? String == "TVTUNES")
        assert(object?["ack"] as? String == "press-1")
        assert(object?["can_previous"] as? Bool == false)
        print("Music history and gadget protocol checks passed")
    }
}
