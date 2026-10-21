import Foundation

/// The existing album-remote-v1 protocol never carries media-server credentials.
enum MusicRemoteMessage: Equatable, Sendable {
    case hello(String)
    case command(String, MusicCommand)
    case telemetry(Int)

    static func parse(_ data: Data) -> Self? {
        guard data.count <= 4096,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        switch object["type"] as? String {
        case "hello":
            guard let token = object["token"] as? String, token.utf8.count <= 256 else { return nil }
            return .hello(token)
        case "command":
            guard let id = object["id"] as? String, (1...100).contains(id.utf8.count),
                let raw = object["command"] as? String, let command = MusicCommand(rawValue: raw)
            else { return nil }
            return .command(id, command)
        case "telemetry":
            guard let number = object["battery_percent"] as? NSNumber,
                CFGetTypeID(number) != CFBooleanGetTypeID(),
                number.doubleValue == Double(number.intValue), (-1...100).contains(number.intValue)
            else { return nil }
            return .telemetry(number.intValue)
        default: return nil
        }
    }

    static func tokensMatch(_ supplied: String, _ expected: String) -> Bool {
        let left = Array(supplied.utf8), right = Array(expected.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

/// The state schema is kept compatible with the physical gadget's current firmware.
struct MusicRemoteState: Encodable, Sendable {
    let type = "state"
    let source: String
    let status: MusicPlayback.Status
    let album: String
    let artist: String
    let track: String
    let error: String
    let canPrevious: Bool
    let ack: String?

    enum CodingKeys: String, CodingKey {
        case type, source, status, album, artist, track, error, ack
        case canPrevious = "can_previous"
    }

    init(player: MusicPlayer, playback: MusicPlayback, canPrevious: Bool, ack: String? = nil) {
        source = player.wireSource
        status = playback.status
        album = String(playback.album.prefix(300))
        artist = String(playback.artist.prefix(300))
        track = String(playback.track.prefix(300))
        error = String(playback.error.prefix(300))
        self.canPrevious = canPrevious
        self.ack = ack
    }
}
