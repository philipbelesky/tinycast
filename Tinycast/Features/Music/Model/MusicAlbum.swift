import Foundation

/// Apple Music carries ordered library-track ids; TVTunes owns its own album queue.
struct MusicAlbum: Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    var tracks: [String] = []
}
