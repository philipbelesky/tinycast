import Foundation

/// The player identity partitions album navigation and listening history.
enum MusicPlayer: String, CaseIterable, Codable, Identifiable, Sendable {
    case appleMusic, tvTunes

    var id: Self { self }
    var title: String { self == .appleMusic ? "Apple Music" : "TVTunes" }
    var wireSource: String { self == .appleMusic ? "APPLE MUSIC" : "TVTUNES" }
    var bundleID: String { self == .appleMusic ? "com.apple.Music" : "edu.self.tvtunes" }
}

/// All music controls use the same verbs on the desktop and gadget.
enum MusicCommand: String, Sendable, CaseIterable {
    case toggle, pause
    case previousAlbum = "previous_album"
    case nextAlbum = "next_album"
    case previousTrack = "previous_track"
    case nextTrack = "next_track"
}
