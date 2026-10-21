import Foundation
import Observation

/// One serial command boundary serves desktop controls and the authenticated gadget.
@MainActor
@Observable
final class MusicPlaybackService {
    private enum PollingRecovery {
        case reconnect
        case retry(Date)
    }

    let store: MusicStore
    let remote = MusicRemoteServer()
    let port: UInt16
    private(set) var pairingToken = ""
    private(set) var pairingError: String?
    private(set) var albums: [MusicPlayer: [MusicAlbum]] = [:]
    private var albumHistory: [MusicPlayer: MusicAlbumHistory] = [:]
    private var pendingAlbums: [MusicPlayer: String] = [:]
    private var recovery: [MusicPlayer: PollingRecovery] = [:]
    private let runner: any MusicPlayerControlling
    private let now: () -> Date
    private var polling: Task<Void, Never>?
    private var tail: Task<Void, Never>?
    private var operations: [UUID: Task<MusicPlayback, Never>] = [:]
    private var revisions: [MusicPlayer: Int] = [:]
    private var pendingCount = 0
    private var remoteResults: [String: (MusicCommand, Task<MusicRemoteState, Never>)] = [:]
    private var remoteOrder: [String] = []
    private let pairing = MusicPairingStore()

    init(
        store: MusicStore,
        runner: any MusicPlayerControlling = MusicAutomationRunner(),
        port: UInt16? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.runner = runner
        self.now = now
        self.port = port ?? (Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? 8797 : 8796)
        remote.snapshot = { [weak self] in self?.remoteState() ?? MusicRemoteState(
            player: .appleMusic, playback: .failure("Music service stopped."), canPrevious: false) }
        remote.command = { [weak self] id, command in
            guard let self else { return MusicRemoteState(player: .appleMusic,
                playback: .failure("Music service stopped."), canPrevious: false, ack: id) }
            return await self.remoteCommand(id: id, command: command)
        }
    }

    isolated deinit {
        polling?.cancel()
        for operation in operations.values { operation.cancel() }
    }

    func start() {
        store.load()
        if store.remoteEnabled { applyRemote() }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    func stop() {
        polling?.cancel()
        polling = nil
        for player in MusicPlayer.allCases { revisions[player, default: 0] += 1 }
        for operation in operations.values { operation.cancel() }
        remote.stop()
    }

    func setMonitoring(_ player: MusicPlayer, enabled: Bool) async {
        revisions[player, default: 0] += 1
        store.setMonitoring(player, enabled: enabled)
        pendingAlbums[player] = nil
        albums[player] = nil
        albumHistory[player] = nil
        recovery[player] = nil
        if enabled {
            await connect(player)
        }
    }

    func connect(_ player: MusicPlayer) async {
        recovery[player] = nil
        let revision = revisions[player, default: 0]
        store.snapshots[player] = MusicPlayback(status: .loading)
        _ = await enqueue(player) { [self] in
            try await runner.authorize(player)
            try validateConnection(player, revision: revision)
            return try await runner.state(player)
        }
    }

    func refresh() async {
        guard pendingCount == 0 else { return }
        for player in MusicPlayer.allCases where store.monitored.contains(player) {
            switch recovery[player] {
            case .reconnect?: continue
            case .retry(let retryAt)? where now() < retryAt: continue
            default: break
            }
            _ = await refresh(player)
        }
    }

    @discardableResult
    func refresh(_ player: MusicPlayer) async -> MusicPlayback {
        await enqueue(player) { [runner] in try await runner.state(player) }
    }

    func refreshAlbums(_ player: MusicPlayer) async {
        let revision = revisions[player, default: 0]
        _ = await enqueue(player) { [self] in
            let catalog = try await runner.albums(player)
            try validateConnection(player, revision: revision)
            albums[player] = catalog
            return try await runner.state(player)
        }
    }

    @discardableResult
    func perform(_ command: MusicCommand, player: MusicPlayer) async -> MusicPlayback {
        let revision = revisions[player, default: 0]
        return await enqueue(player) { [self] in
            let current = try await runner.state(player)
            try validateConnection(player, revision: revision)
            if command == .previousAlbum || command == .nextAlbum || (command == .toggle && current.status == .stopped) {
                if command == .previousAlbum && !canPrevious(player) { return current }
                if albums[player] == nil {
                    let catalog = try await runner.albums(player)
                    try validateConnection(player, revision: revision)
                    albums[player] = catalog
                }
                let catalog = albums[player] ?? []
                guard let target = albumHistory[player, default: MusicAlbumHistory()].target(
                    command, candidates: catalog.map(\.id), current: current.albumID),
                    let album = catalog.first(where: { $0.id == target })
                else { throw MusicAutomationFailure("No available album. Refresh the player's library.") }
                let result = try await runner.play(album, player: player)
                try validateConnection(player, revision: revision)
                pendingAlbums[player] = target
                return result
            }
            return try await runner.transport(command, player: player)
        }
    }

    func play(_ album: MusicAlbum, player: MusicPlayer) async {
        let revision = revisions[player, default: 0]
        _ = await enqueue(player) { [self] in
            let state = try await runner.play(album, player: player)
            try validateConnection(player, revision: revision)
            pendingAlbums[player] = album.id
            return state
        }
    }

    func canPrevious(_ player: MusicPlayer) -> Bool { albumHistory[player]?.canPrevious ?? false }

    func setRemoteEnabled(_ enabled: Bool) {
        store.setRemoteEnabled(enabled)
        if enabled { applyRemote() } else { remote.stop(); pairingToken = ""; pairingError = nil }
    }

    func rotatePairing() {
        remote.stop()
        do {
            pairingToken = try pairing.rotate()
            pairingError = nil
            if store.remoteEnabled { remote.start(port: port, token: pairingToken) }
        } catch { pairingError = "The gadget pairing token could not be saved to Keychain." }
    }

    func remoteState(ack: String? = nil, playback: MusicPlayback? = nil) -> MusicRemoteState {
        let player = store.selectedPlayer
        let state = playback ?? store.snapshots[player] ?? .failure("Connect \(player.title) in Tinycast.")
        return MusicRemoteState(player: player, playback: state, canPrevious: canPrevious(player), ack: ack)
    }

    func remoteCommand(id: String, command: MusicCommand) async -> MusicRemoteState {
        if let (previous, task) = remoteResults[id] {
            guard previous == command else { return remoteState(ack: id, playback: .failure("Command ID already used.")) }
            return await task.value
        }
        guard remoteOrder.count < 264 else { return remoteState(ack: id, playback: .failure("Too many pending commands.")) }
        let player = store.selectedPlayer
        let task = Task { [self] in
            let result = await perform(command, player: player)
            return MusicRemoteState(player: player, playback: result, canPrevious: canPrevious(player), ack: id)
        }
        remoteResults[id] = (command, task)
        remoteOrder.append(id)
        let result = await task.value
        if remoteOrder.count > 256, let oldest = remoteOrder.first {
            remoteOrder.removeFirst()
            remoteResults[oldest] = nil
        }
        return result
    }

    private func applyRemote() {
        do {
            pairingToken = try pairing.token()
            pairingError = nil
            remote.start(port: port, token: pairingToken)
        } catch {
            store.setRemoteEnabled(false)
            pairingError = "The gadget pairing token could not be read from Keychain."
        }
    }

    private func validateConnection(_ player: MusicPlayer, revision: Int) throws {
        try Task.checkCancellation()
        guard store.monitored.contains(player), revisions[player, default: 0] == revision else {
            throw CancellationError()
        }
    }

    private func enqueue(
        _ player: MusicPlayer, work: @escaping @MainActor () async throws -> MusicPlayback
    ) async -> MusicPlayback {
        guard store.monitored.contains(player) else { return .failure("Connect \(player.title) in Tinycast first.") }
        guard pendingCount < 8 else { return .failure("Music is busy. Wait for the current command to finish.") }
        let id = UUID(), revision = revisions[player, default: 0]
        let previous = tail
        pendingCount += 1
        store.isBusy = true
        let task = Task { [self] () -> MusicPlayback in
            await previous?.value
            guard !Task.isCancelled, revisions[player, default: 0] == revision, store.monitored.contains(player)
            else { return .failure("The player connection changed before this command ran.") }
            let result: MusicPlayback
            var requiresReconnect = false
            do {
                result = try await work()
            } catch is CancellationError {
                return .failure("Playback result is unknown. Check the player before retrying.")
            } catch let error as MusicAutomationFailure {
                requiresReconnect = error.requiresReconnect
                result = .failure(error.localizedDescription)
            } catch { result = .failure(error.localizedDescription) }
            guard !Task.isCancelled, revisions[player, default: 0] == revision, store.monitored.contains(player)
            else { return .failure("The player connection changed. Playback result is unknown.") }
            if result.status == .error {
                pendingAlbums[player] = nil
                recovery[player] = requiresReconnect ? .reconnect : .retry(now().addingTimeInterval(10))
            } else { recovery[player] = nil }
            if let target = pendingAlbums[player], result.albumID == target,
                result.status == .playing || result.status == .paused {
                albumHistory[player, default: MusicAlbumHistory()].confirm(target)
                pendingAlbums[player] = nil
            }
            store.observe(result, player: player, at: now())
            return result
        }
        operations[id] = task
        tail = Task { _ = await task.value }
        let result = await task.value
        operations[id] = nil
        pendingCount -= 1
        store.isBusy = pendingCount > 0
        if pendingCount == 0 { tail = nil }
        return result
    }
}
