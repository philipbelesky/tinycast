import Foundation

/// Album navigation advances only after the selected album is observed in playback.
struct MusicAlbumHistory: Sendable {
    private(set) var albums: [String] = []
    private(set) var cursor = -1
    var canPrevious: Bool { cursor > 0 }

    func target(_ command: MusicCommand, candidates: [String], current: String?) -> String? {
        if command == .previousAlbum {
            return canPrevious ? albums[cursor - 1] : nil
        }
        if cursor + 1 < albums.count { return albums[cursor + 1] }
        let choices = candidates.filter { $0 != current }
        return (choices.isEmpty ? candidates : choices).randomElement()
    }

    mutating func confirm(_ albumID: String) {
        if canPrevious, albums[cursor - 1] == albumID {
            cursor -= 1
        } else if cursor + 1 < albums.count, albums[cursor + 1] == albumID {
            cursor += 1
        } else {
            albums = Array(albums.prefix(cursor + 1))
            albums.append(albumID)
            albums = Array(albums.suffix(100))
            cursor = albums.count - 1
        }
    }
}
