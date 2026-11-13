import Foundation

@main
@MainActor
struct MusicRatingTests {
    static func main() async throws {
        conversions()
        try historyAndWire()
        targeting()
        cachePolicy()
        try await refusesWithoutWriting()
        try await sameStarSkipsTheWrite()
        try await halfStarClickWritesWholeStars()
        try await writeKeepsTheTrackCapturedAtTheClick()
        try await failureRevertsAndPollingContinues()
        try await cacheRefreshesOnTrackChangeAndAge()
        menuBarPresence()
        print("Music rating checks passed")
    }

    private static func conversions() {
        assert(MusicRating.apple(points: 80, kind: "computed") == .unrated)
        assert(MusicRating.apple(points: 0, kind: "computed") == .unrated)
        assert(MusicRating.apple(points: 80, kind: "user") == MusicRating(halfStars: 8))
        assert(MusicRating.apple(points: 70, kind: "USER").halfStars == 7)
        let half = MusicRating.apple(points: 70, kind: "user")
        assert(half.wholeStars == 3 && half.hasHalfStar)
        assert(half.fill(for: 3) == .full && half.fill(for: 4) == .half && half.fill(for: 5) == .empty)
        assert(MusicRating.whole(4).hudGlyphs == "★★★★☆")
        assert(MusicRating.whole(4).applePoints == 80)
        assert(MusicRating.whole(4).tvTunesValue == 8)
        assert(MusicRating.tvTunes(nil) == nil)
        assert(MusicRating.tvTunes(-1) == nil)
        assert(MusicRating.tvTunes(0) == .unrated)
        assert(MusicRating.tvTunes(7)?.halfStars == 7)
        assert(MusicRating.tvTunes(11) == nil)
    }

    private static func historyAndWire() throws {
        var listens = MusicListeningHistory()
        let now = Date(timeIntervalSince1970: 50)
        var playing = MusicPlayback(status: .playing, track: "Track", trackID: "t", rating: .whole(1))
        assert(listens.observe(playing, player: .appleMusic, at: now))
        playing.rating = .whole(5)
        assert(!listens.observe(playing, player: .appleMusic, at: now))
        assert(listens.entries.count == 1)

        let encoded = try JSONEncoder().encode(playing)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        assert(object?["rating"] == nil && object?["trackID"] as? String == "t")
        let restored = try JSONDecoder().decode(MusicPlayback.self, from: encoded)
        assert(restored.rating == nil && restored.track == "Track")

        let wire = MusicRemoteState(player: .tvTunes, playback: playing, canPrevious: true)
        let wireObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(wire)) as? [String: Any]
        assert(wireObject?["rating"] == nil && wireObject?["Rtng"] == nil)
        assert(wireObject?["track"] as? String == "Track")
        assert(wireObject?["can_previous"] as? Bool == true)
    }

    private static func targeting() {
        let playing = MusicPlayback(status: .playing, track: "A", trackID: "a")
        let paused = MusicPlayback(status: .paused, track: "B", trackID: "b")
        let stopped = MusicPlayback(status: .stopped, track: "C", trackID: "c")
        let monitored = Set(MusicPlayer.allCases)
        var snapshots: [MusicPlayer: MusicPlayback] = [.appleMusic: playing, .tvTunes: playing]
        assert(MusicCommandTarget.player(monitored: monitored, snapshots: snapshots, preferred: .tvTunes) == .tvTunes)
        assert(MusicCommandTarget.player(monitored: monitored, snapshots: snapshots, preferred: .appleMusic) == .appleMusic)
        snapshots[.appleMusic] = stopped
        assert(MusicCommandTarget.player(monitored: monitored, snapshots: snapshots, preferred: .appleMusic) == .tvTunes)
        snapshots = [.appleMusic: paused, .tvTunes: stopped]
        assert(MusicCommandTarget.player(monitored: [.appleMusic], snapshots: snapshots, preferred: .tvTunes) == .appleMusic)
        snapshots = [.appleMusic: stopped, .tvTunes: playing]
        assert(MusicCommandTarget.player(monitored: [.appleMusic], snapshots: snapshots, preferred: .tvTunes) == nil)
        let withTracks = MusicCommandTarget.playersWithTracks(
            monitored: monitored, snapshots: [.appleMusic: playing, .tvTunes: paused])
        assert(withTracks.count == 2)
    }

    private static func menuBarPresence() {
        let start = Date(timeIntervalSince1970: 100)
        let playing = MusicPlayback(status: .playing, track: "A", trackID: "a")
        let paused = MusicPlayback(status: .paused, track: "B", trackID: "b")
        let stopped = MusicPlayback(status: .stopped)
        assert(MusicMenuBarPresence.isEligible(monitored: [.appleMusic], snapshots: [.appleMusic: playing]))
        assert(MusicMenuBarPresence.isEligible(monitored: [.tvTunes], snapshots: [.tvTunes: paused]))
        assert(!MusicMenuBarPresence.isEligible(monitored: [.appleMusic], snapshots: [.appleMusic: stopped]))
        assert(!MusicMenuBarPresence.isEligible(monitored: [], snapshots: [.appleMusic: playing]))
        assert(!MusicMenuBarPresence.isEligible(
            monitored: [.appleMusic], snapshots: [.appleMusic: MusicPlayback(status: .playing)]))
        var neverShown = MusicMenuBarPresence()
        assert(!neverShown.shows(preference: true, eligible: false, now: start), "No grace before a first showing")
        var presence = MusicMenuBarPresence()
        assert(!presence.shows(preference: false, eligible: true, now: start))
        assert(presence.shows(preference: true, eligible: true, now: start))
        assert(presence.shows(preference: true, eligible: false, now: start))
        assert(presence.shows(preference: true, eligible: false, now: start.addingTimeInterval(4)))
        assert(!presence.shows(preference: true, eligible: false, now: start.addingTimeInterval(5)))
        assert(presence.shows(preference: true, eligible: true, now: start.addingTimeInterval(6)))
        assert(presence.shows(preference: true, eligible: false, now: start.addingTimeInterval(6)))
        assert(!presence.shows(preference: true, eligible: false, now: start.addingTimeInterval(11)))
    }

    private static func cachePolicy() {
        let start = Date(timeIntervalSince1970: 0)
        assert(MusicRatingReadPolicy.needsRead(cached: nil, trackID: "t", now: start, afterOwnWrite: false))
        let cache = MusicRatingCache(trackID: "t", rating: .whole(1), readAt: start)
        assert(!MusicRatingReadPolicy.needsRead(
            cached: cache, trackID: "t", now: start.addingTimeInterval(29), afterOwnWrite: false))
        assert(MusicRatingReadPolicy.needsRead(
            cached: cache, trackID: "t", now: start.addingTimeInterval(30), afterOwnWrite: false))
        assert(MusicRatingReadPolicy.needsRead(cached: cache, trackID: "other", now: start, afterOwnWrite: false))
        assert(MusicRatingReadPolicy.needsRead(cached: cache, trackID: "t", now: start, afterOwnWrite: true))
        assert(!MusicRatingReadPolicy.needsRead(cached: nil, trackID: "", now: start, afterOwnWrite: true))
    }

    private static func refusesWithoutWriting() async throws {
        let harness = try Harness()
        defer { harness.cleanup() }
        harness.store.setMonitoring(.appleMusic, enabled: true)
        harness.store.observe(
            MusicPlayback(status: .playing, track: "Cloud", trackID: "cloud"), player: .appleMusic, at: harness.clock.now)
        let refused = await harness.service.rate(3, player: .appleMusic)
        assert(refused == .refused("This track cannot be rated."))
        assert(harness.player.rateCount == 0)
        harness.store.observe(MusicPlayback(status: .stopped), player: .appleMusic, at: harness.clock.now)
        let idle = await harness.service.rate(3, player: .appleMusic)
        assert(idle == .refused("Nothing is playing."))
        assert(harness.player.rateCount == 0)
    }

    private static func sameStarSkipsTheWrite() async throws {
        let harness = try Harness()
        defer { harness.cleanup() }
        harness.store.setMonitoring(.appleMusic, enabled: true)
        harness.store.observe(
            MusicPlayback(status: .playing, track: "Song", trackID: "song", rating: .whole(4)),
            player: .appleMusic, at: harness.clock.now)
        let same = await harness.service.rate(4, player: .appleMusic)
        assert(same == .unchanged && harness.player.rateCount == 0)
        let outOfRange = await harness.service.rate(0, player: .appleMusic)
        assert(outOfRange == .refused("Choose a rating from 1 to 5 stars."))
        assert(harness.player.rateCount == 0)
    }

    private static func halfStarClickWritesWholeStars() async throws {
        let harness = try Harness()
        defer { harness.cleanup() }
        harness.store.setMonitoring(.appleMusic, enabled: true)
        harness.player.playback = MusicPlayback(
            status: .playing, track: "Song", trackID: "song", rating: MusicRating(halfStars: 7))
        harness.store.observe(harness.player.playback, player: .appleMusic, at: harness.clock.now)
        let result = await harness.service.rate(3, player: .appleMusic)
        guard case .applied = result else { return assertionFailure("a half star must still accept a whole-star write") }
        assert(harness.player.ratedStars == [3] && harness.player.ratedTrackIDs == ["song"])
        assert(harness.service.displayedRating(for: .appleMusic) == .whole(3))
    }

    private static func writeKeepsTheTrackCapturedAtTheClick() async throws {
        let harness = try Harness()
        defer { harness.cleanup() }
        harness.store.setMonitoring(.appleMusic, enabled: true)
        harness.player.playback = MusicPlayback(status: .playing, track: "Old", trackID: "old", rating: .unrated)
        harness.store.observe(harness.player.playback, player: .appleMusic, at: harness.clock.now)
        harness.player.blockRate = true
        let pending = Task { await harness.service.rate(4, player: .appleMusic) }
        while harness.player.rateContinuation == nil { await Task.yield() }
        harness.store.observe(
            MusicPlayback(status: .playing, track: "Old", trackID: "old", rating: .unrated),
            player: .appleMusic, at: harness.clock.now)
        assert(harness.service.displayedRating(for: .appleMusic) == .whole(4),
            "a poll of the same track must not replace the pending rating")
        harness.player.playback = MusicPlayback(status: .playing, track: "New", trackID: "new", rating: .unrated)
        harness.store.observe(harness.player.playback, player: .appleMusic, at: harness.clock.now)
        assert(harness.service.displayedRating(for: .appleMusic) != .whole(4),
            "a pending rating must not appear on the track that replaced it")
        harness.player.rateContinuation?.resume()
        harness.player.rateContinuation = nil
        _ = await pending.value
        assert(harness.player.ratedTrackIDs == ["old"])
        assert(harness.service.displayedRating(for: .appleMusic) != .whole(4))
    }

    private static func failureRevertsAndPollingContinues() async throws {
        let harness = try Harness()
        defer { harness.cleanup() }
        harness.store.setMonitoring(.appleMusic, enabled: true)
        let confirmed = MusicPlayback(status: .playing, track: "Song", trackID: "song", rating: .whole(2))
        harness.player.playback = confirmed
        harness.store.observe(confirmed, player: .appleMusic, at: harness.clock.now)
        harness.player.rememberRating(.whole(2), trackID: "song", player: .appleMusic, at: harness.clock.now)
        harness.player.failRate = true
        let failed = await harness.service.rate(5, player: .appleMusic)
        assert(failed == .failed(
            "The player timed out. The playback result is unknown; check the player before retrying."))
        assert(harness.store.snapshots[.appleMusic]?.status != .error)
        assert(harness.service.displayedRating(for: .appleMusic) == .whole(2))
        let reads = harness.player.readCounts[.appleMusic, default: 0]
        let rates = harness.player.rateCount
        await harness.service.refresh(.appleMusic)
        assert(harness.player.readCounts[.appleMusic, default: 0] > reads, "polling must continue after a rating failure")
        assert(harness.player.rateCount == rates, "a failed rating must not be replayed")
        assert(harness.store.snapshots[.appleMusic]?.status != .error)
    }

    private static func cacheRefreshesOnTrackChangeAndAge() async throws {
        let harness = try Harness()
        defer { harness.cleanup() }
        harness.store.setMonitoring(.appleMusic, enabled: true)
        harness.player.playback = MusicPlayback(status: .playing, track: "T", trackID: "t")
        harness.player.ratings["t"] = .whole(3)
        await harness.service.refresh(.appleMusic)
        assert(harness.player.ratingReads == 1)
        assert(harness.service.displayedRating(for: .appleMusic) == .whole(3))
        await harness.service.refresh(.appleMusic)
        assert(harness.player.ratingReads == 1, "a fresh cache must not be read again")
        harness.clock.now.addTimeInterval(31)
        await harness.service.refresh(.appleMusic)
        assert(harness.player.ratingReads == 2, "a rating older than 30 seconds must be read again")
        harness.player.playback.trackID = "other"
        harness.player.playback.track = "Other"
        harness.player.ratings["other"] = .unrated
        await harness.service.refresh(.appleMusic)
        assert(harness.player.ratingReads == 3, "a track change must read that track's rating")
        let readsBeforeWrite = harness.player.ratingReads
        let written = await harness.service.rate(5, player: .appleMusic)
        guard case .applied = written else { return assertionFailure("the write should apply") }
        await harness.service.refresh(.appleMusic)
        assert(harness.player.ratingReads == readsBeforeWrite,
            "the write's read-back is the refresh, so the next poll must not read again")
        assert(harness.service.displayedRating(for: .appleMusic) == .whole(5))
    }
}

@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 5_000)
}

@MainActor
private struct Harness {
    let suite: String
    let defaults: UserDefaults
    let directory: URL
    let store: MusicStore
    let player: RatingPlayer
    let clock: TestClock
    let service: MusicPlaybackService

    init() throws {
        suite = "tinycast-rating-test-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        directory = FileManager.default.temporaryDirectory.appending(path: suite)
        store = MusicStore(defaults: defaults, historyURL: directory.appending(path: "history.json"))
        store.load()
        player = RatingPlayer()
        clock = TestClock()
        service = MusicPlaybackService(store: store, runner: player, now: { [clock] in clock.now })
    }

    func cleanup() {
        service.stop()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class RatingPlayer: MusicPlayerControlling {
    var playback = MusicPlayback()
    var rateCount = 0
    var ratingReads = 0
    var ratedTrackIDs: [String] = []
    var ratedStars: [Int] = []
    var failRate = false
    var blockRate = false
    var rateContinuation: CheckedContinuation<Void, Never>?
    var ratings: [String: MusicRating?] = [:]
    var readCounts: [MusicPlayer: Int] = [:]
    private var caches: [MusicPlayer: MusicRatingCache] = [:]

    func authorize(_ player: MusicPlayer) async throws {}

    func state(_ player: MusicPlayer, budget: MusicOperationBudget) async throws -> MusicPlayback {
        readCounts[player, default: 0] += 1
        return playback
    }

    func albums(_ player: MusicPlayer) async throws -> [MusicAlbum] { [] }

    func transport(_ command: MusicCommand, player: MusicPlayer) async throws -> MusicPlayback { playback }

    func play(_ album: MusicAlbum, player: MusicPlayer) async throws -> MusicPlayback { playback }

    func readRating(
        trackID: String, player: MusicPlayer, budget: MusicOperationBudget
    ) async throws -> MusicRating? {
        ratingReads += 1
        if let stored = ratings[trackID] { return stored }
        return playback.trackID == trackID ? playback.rating : .unrated
    }

    func rate(
        stars: Int, trackID: String, player: MusicPlayer, budget: MusicOperationBudget
    ) async throws -> MusicRating {
        rateCount += 1
        ratedTrackIDs.append(trackID)
        ratedStars.append(stars)
        if blockRate {
            blockRate = false
            await withCheckedContinuation { rateContinuation = $0 }
        }
        if failRate {
            throw MusicAutomationFailure(
                "The player timed out. The playback result is unknown; check the player before retrying.")
        }
        let rating = MusicRating.whole(stars)
        ratings[trackID] = rating
        return rating
    }

    func ratingCache(for player: MusicPlayer) -> MusicRatingCache? { caches[player] }

    func rememberRating(_ rating: MusicRating?, trackID: String, player: MusicPlayer, at: Date) {
        caches[player] = MusicRatingCache(trackID: trackID, rating: rating, readAt: at)
    }
}
