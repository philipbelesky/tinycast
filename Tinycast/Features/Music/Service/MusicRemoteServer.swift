import Foundation
import Network
import Observation

/// One opt-in LAN listener; its structured connection tasks end when the listener is stopped.
@MainActor
@Observable
final class MusicRemoteServer {
    private(set) var status = "Off"
    private(set) var connectedDevices = 0
    private(set) var batteryPercent: Int?
    private(set) var listeningPort: UInt16?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var authenticated = Set<UUID>()
    var snapshot: @MainActor @Sendable () -> MusicRemoteState = {
        MusicRemoteState(player: .appleMusic, playback: .failure("Connect a player in Tinycast."), canPrevious: false)
    }
    var command: @MainActor @Sendable (String, MusicCommand) async -> MusicRemoteState = { id, _ in
        MusicRemoteState(player: .appleMusic, playback: .failure("Connect a player in Tinycast."), canPrevious: false, ack: id)
    }

    isolated deinit { task?.cancel() }

    func start(port: UInt16, token: String, loopbackOnly: Bool = false) {
        stop()
        let generation = generation
        status = "Starting…"
        task = Task { [weak self] in
            do {
                let options = NWParametersBuilder({
                    WebSocket { TCP() }.maximumMessageSize(4096).autoReplyPing(true)
                }).localPort(NWEndpoint.Port(rawValue: port)!)
                if loopbackOnly {
                    options.parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .init(rawValue: port)!)
                }
                let websocket = options.parameters.defaultProtocolStack.applicationProtocols.first as? NWProtocolWebSocket.Options
                websocket?.setClientRequestHandler(.global()) { protocols, headers in
                    let browser = headers.contains { $0.name.lowercased() == "origin" }
                    let accepted = protocols.contains("album-remote-v1") && !browser
                    return .init(status: accepted ? .accept : .reject, subprotocol: accepted ? "album-remote-v1" : nil)
                }
                let listener = try NetworkListener(using: options).newConnectionLimit(4)
                listener.onStateUpdate { [weak self] listener, state in
                    guard let self, self.generation == generation else { return }
                    switch state {
                    case .ready:
                        self.listeningPort = listener.port?.rawValue
                        self.status = "Listening on port \(listener.port?.rawValue ?? port)"
                    case .waiting: self.status = "Waiting for the network"
                    case .failed: self.status = "Cannot listen on port \(port). Check for another music companion."
                    default: break
                    }
                }
                try await listener.run { [weak self] connection in
                    defer { listener.newConnectionLimit += 1 }
                    await self?.serve(connection, token: token, generation: generation)
                }
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.status = "Cannot listen on port \(port). Check for another music companion."
            }
        }
    }

    func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
        authenticated.removeAll()
        connectedDevices = 0
        batteryPercent = nil
        listeningPort = nil
        status = "Off"
    }

    private func serve(_ connection: NetworkConnection<WebSocket>, token: String, generation: UUID) async {
        let id = UUID()
        defer {
            authenticated.remove(id)
            connectedDevices = authenticated.count
            if authenticated.isEmpty { batteryPercent = nil }
        }
        do {
            let hello = try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask { try await connection.receive().content }
                group.addTask {
                    try await Task.sleep(for: .seconds(5))
                    throw CancellationError()
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw CancellationError() }
                return first
            }
            guard self.generation == generation, !Task.isCancelled,
                case .hello(let supplied) = MusicRemoteMessage.parse(hello),
                MusicRemoteMessage.tokensMatch(supplied, token)
            else { return }
            authenticated.insert(id)
            connectedDevices = authenticated.count
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    while !Task.isCancelled {
                        guard let state = await self?.snapshot() else { return }
                        try await Self.send(state, to: connection)
                        try await Task.sleep(for: .seconds(1))
                    }
                }
                group.addTask { [weak self] in
                    while !Task.isCancelled {
                        let message = try await connection.receive()
                        guard message.metadata.opcode == .text,
                            let parsed = MusicRemoteMessage.parse(message.content)
                        else { return }
                        guard let self, await self.generation == generation else { return }
                        switch parsed {
                        case .command(let commandID, let command):
                            let reply = await self.command(commandID, command)
                            guard !Task.isCancelled else { return }
                            try await Self.send(reply, to: connection)
                        case .telemetry(let percent): await self.updateBattery(percent, generation: generation)
                        case .hello: return
                        }
                    }
                }
                defer { group.cancelAll() }
                _ = try await group.next()
            }
        } catch { return }
    }

    private func updateBattery(_ percent: Int, generation: UUID) {
        guard self.generation == generation else { return }
        batteryPercent = percent >= 0 ? percent : nil
    }

    private nonisolated static func send(_ state: MusicRemoteState, to connection: NetworkConnection<WebSocket>) async throws {
        let data = try JSONEncoder().encode(state)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await connection.send(String(bytes: data, encoding: .utf8) ?? "{}") }
            group.addTask {
                try await Task.sleep(for: .seconds(3))
                throw CancellationError()
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }
}
