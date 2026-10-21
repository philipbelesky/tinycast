import Foundation

/// Playback is observed from the player; accepting a command never implies audible playback.
struct MusicPlayback: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case playing, paused, stopped, loading, error
    }

    var status: Status = .stopped
    var album = ""
    var artist = ""
    var track = ""
    var albumID = ""
    var trackID = ""
    var error = ""
    var queueID = ""

    static func failure(_ message: String) -> Self {
        Self(status: .error, error: message)
    }
}
