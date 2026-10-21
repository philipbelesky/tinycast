import AppKit

/// Native automation stays off the main actor and never launches a player during monitoring.
@MainActor
protocol MusicPlayerControlling {
    func authorize(_ player: MusicPlayer) async throws
    func state(_ player: MusicPlayer) async throws -> MusicPlayback
    func albums(_ player: MusicPlayer) async throws -> [MusicAlbum]
    func transport(_ command: MusicCommand, player: MusicPlayer) async throws -> MusicPlayback
    func play(_ album: MusicAlbum, player: MusicPlayer) async throws -> MusicPlayback
}

@MainActor
final class MusicAutomationRunner: MusicPlayerControlling {
    private let session = String(UUID().uuidString.prefix(8))
    private var queueID = ""

    func authorize(_ player: MusicPlayer) async throws {
        let pid = try processID(player)
        try await MusicAppleEvents.authorize(player, processID: pid)
    }

    func state(_ player: MusicPlayer) async throws -> MusicPlayback {
        let pid = try processID(player)
        return try await MusicAppleEvents.state(player, processID: pid)
    }

    func albums(_ player: MusicPlayer) async throws -> [MusicAlbum] {
        let pid = try processID(player)
        return try await MusicAppleEvents.albums(player, processID: pid)
    }

    func transport(_ command: MusicCommand, player: MusicPlayer) async throws -> MusicPlayback {
        let pid = try processID(player)
        return try await MusicAppleEvents.transport(command, player: player, processID: pid)
    }

    func play(_ album: MusicAlbum, player: MusicPlayer) async throws -> MusicPlayback {
        let pid = try processID(player)
        let result = try await MusicAppleEvents.play(
            album, player: player, processID: pid, previousQueue: queueID, session: session)
        if player == .appleMusic { queueID = result.queueID }
        return result
    }

    private func processID(_ player: MusicPlayer) throws -> Int32 {
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID)
        guard instances.count == 1, let instance = instances.first else {
            throw MusicAutomationFailure(instances.isEmpty
                ? "Open \(player.title) and load its library, then reconnect."
                : "More than one \(player.title) copy is running. Quit the extra copy, then reconnect.")
        }
        return instance.processIdentifier
    }
}

struct MusicAutomationFailure: LocalizedError, Sendable {
    let errorDescription: String?
    let requiresReconnect: Bool

    init(_ message: String, requiresReconnect: Bool = false) {
        errorDescription = message
        self.requiresReconnect = requiresReconnect
    }
}
