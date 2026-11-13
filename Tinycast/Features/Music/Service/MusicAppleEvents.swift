import AppKit
import Carbon

/// One operation's remaining time, so a later event cannot restart the eight-second timeout.
struct MusicEventClock: Sendable {
    var budget: MusicOperationBudget
    var now: @Sendable () -> Date
}

/// TVTunes uses its scripting event codes, independent of whichever dictionary Launch Services finds.
enum MusicAppleEvents {
    @concurrent static func authorize(_ player: MusicPlayer, processID: Int32) async throws {
        let target = NSAppleEventDescriptor(processIdentifier: processID)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc,
            code(player == .tvTunes ? "TVtn" : "core"), typeWildCard, true)
        guard status == noErr else { throw failure(number: Int(status)) }
    }
    @concurrent static func state(
        _ player: MusicPlayer, processID: Int32, budget: MusicOperationBudget,
        now: @escaping @Sendable () -> Date
    ) async throws -> MusicPlayback {
        try Task.checkCancellation()
        let clock = MusicEventClock(budget: budget, now: now)
        if player == .tvTunes { return try tvState(tvEvent("pbst", processID: processID, clock: clock)) }
        return try nativeAppleState(processID: processID, clock: clock)
    }

    @concurrent static func transport(
        _ command: MusicCommand, player: MusicPlayer, processID: Int32, budget: MusicOperationBudget,
        now: @escaping @Sendable () -> Date
    ) async throws -> MusicPlayback {
        try Task.checkCancellation()
        let clock = MusicEventClock(budget: budget, now: now)
        if player == .tvTunes {
            let verb: String
            switch command {
            case .toggle: verb = "ppse"
            case .pause: verb = "paus"
            case .nextTrack: verb = "nxtt"
            case .previousTrack: verb = "prev"
            case .nextAlbum, .previousAlbum: throw MusicAutomationFailure("Select an album first.")
            }
            return try tvState(tvEvent(verb, processID: processID, clock: clock))
        }
        let verb: String
        switch command {
        case .toggle: verb = "PlPs"
        case .pause: verb = "Paus"
        case .nextTrack: verb = "Next"
        case .previousTrack: verb = "Prev"
        case .nextAlbum, .previousAlbum: throw MusicAutomationFailure("Select an album first.")
        }
        _ = try send(eventClass: "hook", eventID: verb, processID: processID, clock: clock)
        return try nativeAppleState(processID: processID, clock: clock)
    }

    @concurrent static func albums(_ player: MusicPlayer, processID: Int32) async throws -> [MusicAlbum] {
        try Task.checkCancellation()
        if player == .tvTunes {
            let reply = try tvEvent("albs", processID: processID, clock: MusicEventClock(
                budget: MusicOperationBudget(seconds: MusicOperationBudget.state, now: Date()), now: Date.init))
            if reply.forKeyword(code("Stat")) != nil {
                throw MusicAutomationFailure(try tvState(reply).error)
            }
            return (1..<(reply.numberOfItems + 1)).compactMap { index in
                guard let item = reply.atIndex(index) else { return nil }
                let id = text(item, "AlId")
                guard !id.isEmpty else { return nil }
                return MusicAlbum(id: id, title: text(item, "Titl"), artist: text(item, "Arts"))
            }
        }
        let reply = try executeScript("""
            tell application id "com.apple.Music"
                with timeout of 8 seconds
                    tell library playlist 1
                        return {persistent ID of every track, album of every track, ¬
                            album artist of every track, artist of every track, ¬
                            compilation of every track, disc number of every track, track number of every track}
                    end tell
                end timeout
            end tell
            """)
        var groups: [String: [(disc: Int32, number: Int32, offset: Int, id: String)]] = [:]
        var metadata: [String: (String, String)] = [:]
        let count = reply.atIndex(1)?.numberOfItems ?? 0
        for index in 1..<(count + 1) {
            let title = reply.atIndex(2)?.atIndex(index)?.stringValue ?? ""
            guard !title.isEmpty else { continue }
            let albumArtist = reply.atIndex(3)?.atIndex(index)?.stringValue ?? ""
            let performer = reply.atIndex(4)?.atIndex(index)?.stringValue ?? ""
            let compilation = reply.atIndex(5)?.atIndex(index)?.booleanValue ?? false
            let artist = albumArtist.isEmpty ? (compilation ? "Various Artists" : performer) : albumArtist
            let identity = albumIdentity(title: title, artist: artist)
            let trackID = reply.atIndex(1)?.atIndex(index)?.stringValue ?? ""
            guard !trackID.isEmpty else { continue }
            metadata[identity] = (title, artist)
            groups[identity, default: []].append((
                reply.atIndex(6)?.atIndex(index)?.int32Value ?? 0,
                reply.atIndex(7)?.atIndex(index)?.int32Value ?? 0, index, trackID))
        }
        return groups.compactMap { id, tracks in
            guard let (title, artist) = metadata[id] else { return nil }
            let ordered = tracks.sorted { ($0.disc, $0.number, $0.offset) < ($1.disc, $1.number, $1.offset) }
            return MusicAlbum(id: id, title: title, artist: artist, tracks: ordered.map(\.id))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    @concurrent static func play(
        _ album: MusicAlbum, player: MusicPlayer, processID: Int32, previousQueue: String, session: String
    ) async throws -> MusicPlayback {
        try Task.checkCancellation()
        if player == .tvTunes {
            return try tvState(tvEvent("play", processID: processID, albumID: album.id, clock: MusicEventClock(
                budget: MusicOperationBudget(seconds: MusicOperationBudget.transport, now: Date()), now: Date.init)))
        }
        guard !album.tracks.isEmpty else { throw MusicAutomationFailure("That album has no library tracks.") }
        let tracks = album.tracks.map(quoted).joined(separator: ", ")
        let script = """
            set selectedTrackIDs to {\(tracks)}
            set newQueue to make new user playlist with properties {name:\(quoted("Tinycast " + session))}
            repeat with trackID in selectedTrackIDs
                set matches to tracks of library playlist 1 whose persistent ID is (contents of trackID)
                if (count matches) is 0 then error "A track left the library. Refresh albums."
                duplicate item 1 of matches to newQueue
            end repeat
            if (persistent ID of tracks of newQueue) is not selectedTrackIDs then error "Album order was not retained."
            set shuffle enabled to false
            set song repeat to off
            play track 1 of newQueue
            """
        let queueID = try appleCommand(script + "\nreturn persistent ID of newQueue", processID: processID).stringValue ?? ""
        guard !queueID.isEmpty else { throw MusicAutomationFailure("Music returned no album queue identity.") }
        let started = Date()
        let budget = MusicOperationBudget(seconds: MusicOperationBudget.albumConfirmation, now: started)
        let clock = MusicEventClock(budget: budget, now: Date.init)
        let result = try await MusicAlbumConfirmation.wait(
            for: album, queueID: queueID, deadline: budget.deadline, now: Date.init
        ) {
            try nativeAppleState(processID: processID, clock: clock)
        }
        if !previousQueue.isEmpty, previousQueue != result.queueID {
            _ = try appleCommand("""
                set oldQueues to user playlists whose persistent ID is \(quoted(previousQueue))
                if (count oldQueues) > 0 then delete item 1 of oldQueues
                """, processID: processID)
        }
        return result
    }

    @concurrent static func readRating(
        trackID: String, player: MusicPlayer, processID: Int32, budget: MusicOperationBudget,
        now: @escaping @Sendable () -> Date
    ) async throws -> MusicRating? {
        try Task.checkCancellation()
        if player == .tvTunes {
            let state = try tvState(tvEvent("pbst", processID: processID, clock: MusicEventClock(budget: budget, now: now)))
            return state.rating
        }
        let seconds = try scriptSeconds(budget, now: now)
        let reply = try executeScript("""
            tell application id "com.apple.Music"
                with timeout of \(seconds) seconds
                    set matches to tracks of library playlist 1 whose persistent ID is \(quoted(trackID))
                    if (count of matches) is 0 then return {-1, "missing"}
                    set libraryTrack to item 1 of matches
                    if rating kind of libraryTrack is computed then return {rating of libraryTrack, "computed"}
                    return {rating of libraryTrack, "user"}
                end timeout
            end tell
            """)
        return rating(from: reply)
    }

    @concurrent static func rate(
        stars: Int, trackID: String, player: MusicPlayer, processID: Int32, budget: MusicOperationBudget,
        now: @escaping @Sendable () -> Date
    ) async throws -> MusicRating {
        try Task.checkCancellation()
        if player == .tvTunes {
            return try tvRate(stars: stars, trackID: trackID, processID: processID, budget: budget, now: now)
        }
        let seconds = try scriptSeconds(budget, now: now)
        do {
            let reply = try executeScript("""
                tell application id "com.apple.Music"
                    with timeout of \(seconds) seconds
                        set matches to tracks of library playlist 1 whose persistent ID is \(quoted(trackID))
                        if (count of matches) is 0 then error "not in library" number -54
                        set libraryTrack to item 1 of matches
                        set rating of libraryTrack to \(stars * 20)
                        if rating kind of libraryTrack is computed then return {rating of libraryTrack, "computed"}
                        return {rating of libraryTrack, "user"}
                    end timeout
                end tell
                """)
            guard let rating = rating(from: reply) else { throw notInLibrary }
            return rating
        } catch let error as MusicAutomationFailure where error.number == -54 {
            throw notInLibrary
        }
    }

    private static var notInLibrary: MusicAutomationFailure {
        MusicAutomationFailure("This track is not in your library, so it cannot be rated.", number: -54)
    }

    private static func scriptSeconds(
        _ budget: MusicOperationBudget, now: @Sendable () -> Date
    ) throws -> Int {
        guard let timeout = budget.eventTimeout(at: now()) else { throw failure(number: -1712) }
        let seconds = Int(timeout.rounded(.down))
        guard seconds >= 1 else { throw failure(number: -1712) }
        return min(8, seconds)
    }

    private static func rating(from reply: NSAppleEventDescriptor) -> MusicRating? {
        let points = Int(reply.atIndex(1)?.int32Value ?? -1)
        let kind = reply.atIndex(2)?.stringValue ?? ""
        guard points >= 0, kind != "missing" else { return nil }
        return MusicRating.apple(points: points, kind: kind)
    }

    private static func tvRate(
        stars: Int, trackID: String, processID: Int32, budget: MusicOperationBudget,
        now: @Sendable () -> Date
    ) throws -> MusicRating {
        try Task.checkCancellation()
        guard let timeout = budget.eventTimeout(at: now()) else { throw failure(number: -1712) }
        let event = NSAppleEventDescriptor(eventClass: code("TVtn"), eventID: code("rate"),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: processID),
            returnID: -1, transactionID: 0)
        event.setParam(NSAppleEventDescriptor(string: trackID), forKeyword: code("----"))
        event.setParam(NSAppleEventDescriptor(int32: Int32(stars * 2)), forKeyword: code("Rtng"))
        let reply: NSAppleEventDescriptor
        do {
            let sent = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: timeout)
            let errorNumber = sent.paramDescriptor(forKeyword: code("errn"))?.int32Value ?? 0
            guard errorNumber == 0 else { throw failure(number: Int(errorNumber)) }
            guard let result = sent.paramDescriptor(forKeyword: code("----")) else {
                throw MusicAutomationFailure("TVTunes returned an empty scripting reply.")
            }
            reply = result
        } catch let error as MusicAutomationFailure { throw error } catch {
            throw failure(number: (error as NSError).code)
        }
        let state = try tvState(reply)
        if state.status == .error {
            throw MusicAutomationFailure(state.error.isEmpty ? "TVTunes could not rate that track." : state.error)
        }
        if state.trackID == trackID, let rating = state.rating { return rating }
        return MusicRating.whole(stars)
    }

    private static func appleCommand(_ command: String, processID: Int32) throws -> NSAppleEventDescriptor {
        try Task.checkCancellation()
        guard NSRunningApplication(processIdentifier: processID)?.bundleIdentifier == MusicPlayer.appleMusic.bundleID
        else { throw MusicAutomationFailure("Music closed before the command could run.") }
        return try executeScript("""
            tell application id "com.apple.Music"
                with timeout of 8 seconds
                    \(command)
                end timeout
            end tell
            """)
    }

    private static func executeScript(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw MusicAutomationFailure("Music automation could not be prepared.")
        }
        var error: NSDictionary?
        let reply = script.executeAndReturnError(&error)
        if let error { throw failure(number: error[NSAppleScript.errorNumber] as? Int ?? 0) }
        return reply
    }

    private static func tvEvent(
        _ verb: String, processID: Int32, albumID: String? = nil, clock: MusicEventClock
    ) throws -> NSAppleEventDescriptor {
        try Task.checkCancellation()
        let event = NSAppleEventDescriptor(eventClass: code("TVtn"), eventID: code(verb),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: processID),
            returnID: -1, transactionID: 0)
        if let albumID { event.setParam(NSAppleEventDescriptor(string: albumID), forKeyword: code("----")) }
        guard let timeout = clock.budget.eventTimeout(at: clock.now()) else { throw failure(number: -1712) }
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: timeout)
            let errorNumber = reply.paramDescriptor(forKeyword: code("errn"))?.int32Value ?? 0
            guard errorNumber == 0 else { throw failure(number: Int(errorNumber)) }
            guard let result = reply.paramDescriptor(forKeyword: code("----")) else {
                throw MusicAutomationFailure("TVTunes returned an empty scripting reply.")
            }
            return result
        } catch let error as MusicAutomationFailure { throw error } catch {
            throw failure(number: (error as NSError).code)
        }
    }

    private static func nativeAppleState(processID: Int32, clock: MusicEventClock) throws -> MusicPlayback {
        let playerState = try get(property("pPlS"), processID: processID, clock: clock).enumCodeValue
        if playerState == code("kPSS") { return MusicPlayback() }
        let track = try get(property("pTrk"), processID: processID, clock: clock)
        func field(_ name: String) throws -> String {
            try get(property(name, of: track), processID: processID, clock: clock).stringValue ?? ""
        }
        let album = try field("pAlb")
        let albumArtist = try field("pAlA")
        let compilation = try get(property("pAnt", of: track), processID: processID, clock: clock).booleanValue
        let artist = try albumArtist.isEmpty ? (compilation ? "Various Artists" : field("pArt")) : albumArtist
        let playlist = try get(property("pPla"), processID: processID, clock: clock)
        let queueID = try get(property("pPIS", of: playlist), processID: processID, clock: clock).stringValue ?? ""
        return MusicPlayback(status: playerState == code("kPSP") ? .playing : .paused,
            album: album, artist: artist, track: try field("pnam"),
            albumID: albumIdentity(title: album, artist: artist), trackID: try field("pPIS"), queueID: queueID)
    }

    private static func property(_ name: String, of container: NSAppleEventDescriptor? = nil) -> NSAppleEventDescriptor {
        object(want: "prop", form: "prop", selector: NSAppleEventDescriptor(typeCode: code(name)), container: container)
    }

    private static func object(
        want: String, form: String, selector: NSAppleEventDescriptor, container: NSAppleEventDescriptor? = nil
    ) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(want)), forKeyword: code("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(selector, forKeyword: code("seld"))
        record.setDescriptor(container ?? NSAppleEventDescriptor.null(), forKeyword: code("from"))
        return record.coerce(toDescriptorType: code("obj "))!
    }

    private static func get(
        _ object: NSAppleEventDescriptor, processID: Int32, clock: MusicEventClock
    ) throws -> NSAppleEventDescriptor {
        try send(eventClass: "core", eventID: "getd", processID: processID, clock: clock, parameters: ["----": object])
    }

    private static func send(
        eventClass: String, eventID: String, processID: Int32, clock: MusicEventClock,
        parameters: [String: NSAppleEventDescriptor] = [:]
    ) throws -> NSAppleEventDescriptor {
        try Task.checkCancellation()
        // A fresh 8s timeout on every event lets one slow snapshot hold the queue for a minute.
        guard let timeout = clock.budget.eventTimeout(at: clock.now()) else { throw failure(number: -1712) }
        let event = NSAppleEventDescriptor(eventClass: code(eventClass), eventID: code(eventID),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: processID), returnID: -1, transactionID: 0)
        for (name, value) in parameters { event.setParam(value, forKeyword: code(name)) }
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: timeout)
            let number = reply.paramDescriptor(forKeyword: code("errn"))?.int32Value ?? 0
            if number != 0 { throw failure(number: Int(number)) }
            return reply.paramDescriptor(forKeyword: code("----")) ?? NSAppleEventDescriptor.null()
        } catch let error as MusicAutomationFailure { throw error } catch {
            throw failure(number: (error as NSError).code)
        }
    }

    private static func tvState(_ reply: NSAppleEventDescriptor) throws -> MusicPlayback {
        guard let status = MusicPlayback.Status(rawValue: text(reply, "Stat")) else {
            throw MusicAutomationFailure("TVTunes returned an unreadable playback state.")
        }
        return MusicPlayback(status: status, album: text(reply, "Albm"), artist: text(reply, "Arts"),
            track: text(reply, "Trck"), albumID: text(reply, "AlId"), trackID: text(reply, "TrId"),
            error: text(reply, "Emsg"), rating: MusicRating.tvTunes(integer(reply, "Rtng")))
    }

    private static func integer(_ reply: NSAppleEventDescriptor, _ keyword: String) -> Int? {
        guard let value = reply.forKeyword(code(keyword)) else { return nil }
        return Int(value.int32Value)
    }

    private static func text(_ reply: NSAppleEventDescriptor, _ keyword: String) -> String {
        reply.forKeyword(code(keyword))?.stringValue ?? ""
    }

    private static func code(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func albumIdentity(title: String, artist: String) -> String {
        let data = try? JSONEncoder().encode([title, artist])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private static func failure(number: Int) -> MusicAutomationFailure {
        switch number {
        case -1743, -1744:
            MusicAutomationFailure("Allow Tinycast in System Settings → Privacy & Security → Automation, then reconnect.",
                requiresReconnect: true, number: number)
        case -1712:
            MusicAutomationFailure("The player timed out. The playback result is unknown; check the player before retrying.",
                number: number)
        case -1708:
            MusicAutomationFailure("This TVTunes build has no scripting support. Open the updated build, then reconnect.",
                requiresReconnect: true, number: number)
        default: MusicAutomationFailure("Player automation failed (\(number)). Check the player and reconnect.", number: number)
        }
    }
}
