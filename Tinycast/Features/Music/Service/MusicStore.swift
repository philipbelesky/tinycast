import Foundation
import Observation

/// Music grants are local to this Mac and excluded from settings sync and backups.
@MainActor
@Observable
final class MusicStore {
    private(set) var monitored: Set<MusicPlayer> = []
    private(set) var remoteEnabled = false
    private(set) var historyEnabled = false
    var selectedPlayer: MusicPlayer {
        didSet { defaults.set(selectedPlayer.rawValue, forKey: "music.selectedPlayer") }
    }
    private(set) var listeningHistory = MusicListeningHistory()
    var snapshots: [MusicPlayer: MusicPlayback] = [:]
    var isBusy = false
    var persistenceError: String?
    private let defaults: UserDefaults
    private let historyURL: URL
    private var historyReadFailed = false

    init(
        defaults: UserDefaults = .standard,
        historyURL: URL = AppPaths.applicationSupport().appending(path: "music-history.json")
    ) {
        self.defaults = defaults
        self.historyURL = historyURL
        selectedPlayer = defaults.string(forKey: "music.selectedPlayer").flatMap(MusicPlayer.init) ?? .appleMusic
    }

    func load() {
        monitored = Set((defaults.stringArray(forKey: "music.monitored") ?? []).compactMap(MusicPlayer.init))
        remoteEnabled = defaults.bool(forKey: "music.remoteEnabled")
        historyEnabled = defaults.bool(forKey: "music.historyEnabled")
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return }
        do {
            let size = try historyURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 8_000_000 else { throw CocoaError(.fileReadTooLarge) }
            listeningHistory = try JSONDecoder().decode(MusicListeningHistory.self, from: Data(contentsOf: historyURL))
        } catch {
            historyReadFailed = true
            persistenceError = "Listening history could not be read. Its saved file has been left intact."
        }
    }

    func setMonitoring(_ player: MusicPlayer, enabled: Bool) {
        if enabled { monitored.insert(player) } else { monitored.remove(player); snapshots[player] = nil }
        defaults.set(monitored.map(\.rawValue).sorted(), forKey: "music.monitored")
    }

    func setRemoteEnabled(_ enabled: Bool) {
        remoteEnabled = enabled
        defaults.set(enabled, forKey: "music.remoteEnabled")
    }

    func setHistoryEnabled(_ enabled: Bool) {
        historyEnabled = enabled
        defaults.set(enabled, forKey: "music.historyEnabled")
    }

    func observe(_ state: MusicPlayback, player: MusicPlayer, at now: Date) {
        snapshots[player] = state
        guard historyEnabled, listeningHistory.observe(state, player: player, at: now) else { return }
        saveHistory()
    }

    func clearHistory() {
        historyReadFailed = false
        listeningHistory.clear()
        saveHistory()
    }

    private func saveHistory() {
        guard !historyReadFailed else { return }
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(listeningHistory).write(to: historyURL, options: .atomic)
            persistenceError = nil
        } catch { persistenceError = "Listening history could not be saved. Check available disk space and folder access." }
    }
}
