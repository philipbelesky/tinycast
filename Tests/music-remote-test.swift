import Foundation

@main
@MainActor
struct MusicRemoteTest {
    static func main() async throws {
        let server = MusicRemoteServer()
        let token = "fixture-token-used-only-by-music-tests"
        var commands = 0
        server.command = { id, _ in
            commands += 1
            return MusicRemoteState(player: .tvTunes, playback: MusicPlayback(status: .paused,
                album: "Fixture album", track: "Fixture track"), canPrevious: false, ack: id)
        }
        server.snapshot = { MusicRemoteState(player: .tvTunes, playback: MusicPlayback(status: .paused,
            album: "Fixture album", track: "Fixture track"), canPrevious: false) }
        server.start(port: 0, token: token, loopbackOnly: true)
        defer { server.stop() }
        for _ in 0..<100 where server.listeningPort == nil { try await Task.sleep(for: .milliseconds(20)) }
        guard let port = server.listeningPort else { fatalError("Music listener failed: \(server.status)") }
        let url = URL(string: "ws://127.0.0.1:\(port)/device")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let wrong = session.webSocketTask(with: url, protocols: ["album-remote-v1"])
        wrong.resume()
        try await wrong.send(.string(#"{"type":"hello","token":"wrong"}"#))
        await expectClosed(wrong)
        assert(server.connectedDevices == 0 && commands == 0)

        let noProtocol = session.webSocketTask(with: url)
        noProtocol.resume()
        await expectClosed(noProtocol)

        let noHello = session.webSocketTask(with: url, protocols: ["album-remote-v1"])
        noHello.resume()
        await expectClosed(noHello)

        for index in 0..<6 {
            let socket = session.webSocketTask(with: url, protocols: ["album-remote-v1"])
            socket.resume()
            try await socket.send(.string("{\"type\":\"hello\",\"token\":\"\(token)\"}"))
            let initial = try await receive(socket)
            assert(initial["source"] as? String == "TVTUNES")
            assert(initial["ack"] == nil)
            try await socket.send(.string(#"{"type":"telemetry","battery_percent":73}"#))
            try await socket.send(.string("{\"type\":\"command\",\"id\":\"press-\(index)\",\"command\":\"toggle\"}"))
            var acknowledged = false
            for _ in 0..<4 {
                let reply = try await receive(socket)
                if reply["ack"] as? String == "press-\(index)" { acknowledged = true; break }
            }
            assert(acknowledged)
            assert(server.batteryPercent == 73)
            socket.cancel(with: .normalClosure, reason: nil)
            for _ in 0..<50 where server.connectedDevices > 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        assert(commands == 6)
        let malformed = session.webSocketTask(with: url, protocols: ["album-remote-v1"])
        malformed.resume()
        try await malformed.send(.string("{\"type\":\"hello\",\"token\":\"\(token)\"}"))
        _ = try await receive(malformed)
        try await malformed.send(.string(#"{"type":"command","id":"bad","command":"erase"}"#))
        await expectClosed(malformed)
        assert(commands == 6)

        let oversized = session.webSocketTask(with: url, protocols: ["album-remote-v1"])
        oversized.resume()
        try await oversized.send(.string("{\"type\":\"hello\",\"token\":\"\(token)\"}"))
        _ = try await receive(oversized)
        try await oversized.send(.string(String(repeating: "x", count: 4097)))
        await expectClosed(oversized)
        server.stop()
        assert(server.listeningPort == nil && server.connectedDevices == 0)
        print("Music WebSocket authentication, acknowledgements, telemetry and six reconnects passed")
    }

    private static func receive(_ socket: URLSessionWebSocketTask) async throws -> [String: Any] {
        let message = try await socket.receive()
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let binary): data = binary
        @unknown default: throw CancellationError()
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private static func expectClosed(_ socket: URLSessionWebSocketTask) async {
        do {
            _ = try await socket.receive()
            fatalError("Unauthorised or malformed client received playback data")
        } catch { socket.cancel(with: .goingAway, reason: nil) }
    }
}
