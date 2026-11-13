import AppKit
import SwiftUI

/// Music's window and action surface outlive the palette without owning playback themselves.
@MainActor
@Observable
final class MusicCoordinator {
    let service: MusicPlaybackService
    private let window: AppWindowController
    private unowned let core: AppCore
    @ObservationIgnored private var menuBarController: MusicMenuBarController?
    @ObservationIgnored private var presence = MusicMenuBarPresence()
    @ObservationIgnored private var graceTask: Task<Void, Never>?
    @ObservationIgnored private var isTrackingPlayback = false

    init(service: MusicPlaybackService, core: AppCore) {
        self.service = service
        self.core = core
        window = AppWindowController(title: "Music", contentSize: Theme.Size.musicWindow,
            resizable: true, autosaveName: "MusicWindow", activation: core.activationPolicy)
    }

    func show() {
        if window.focus() { return }
        let hosting = NSHostingController(rootView: MusicView().environment(self))
        hosting.sizingOptions = []
        hosting.sceneBridgingOptions = [.toolbars, .title]
        window.show(chrome: SettingsWindowChrome()) { hosting }
    }

    func closeWindowIfKey() -> Bool {
        guard window.isKeyWindow else { return false }
        window.close()
        return true
    }

    func focusExisting() -> Bool { window.focus() }

    func showSettings() { core.settingsCoordinator.showSettings(tab: .music) }

    func start() {
        applyCommandVisibility()
        applyMenuBarItem()
        trackPlayback()
    }

    func setMonitoring(_ player: MusicPlayer, enabled: Bool) {
        Task {
            await service.setMonitoring(player, enabled: enabled)
            applyCommandVisibility()
            applyMenuBarItem()
        }
    }

    func setShowsInMenuBar(_ shown: Bool) {
        service.store.showsInMenuBar = shown
        applyMenuBarItem()
    }

    func applyCommandVisibility() {
        core.appIndex.setCommandsVisible(Set(CommandID.rateTrackCommands), !service.store.monitored.isEmpty)
    }

    func menuBarModel() -> MusicMenuBarModel {
        let store = service.store
        let players = MusicCommandTarget.playersWithTracks(
            monitored: store.monitored, snapshots: store.snapshots)
        let player = MusicCommandTarget.player(
            monitored: store.monitored, snapshots: store.snapshots, preferred: store.selectedPlayer)
            ?? players.first ?? store.selectedPlayer
        let state = store.snapshots[player] ?? MusicPlayback()
        let detail = [state.artist, state.album].filter { !$0.isEmpty }.joined(separator: " — ")
        return MusicMenuBarModel(
            track: state.track.isEmpty ? String(localized: "Nothing playing") : state.track,
            detail: detail,
            rating: service.displayedRating(for: player),
            status: state.status,
            canPrevious: service.canPrevious(player),
            player: player)
    }

    func applyMenuBarItem(now: Date = Date()) {
        let eligible = MusicMenuBarPresence.isEligible(
            monitored: service.store.monitored, snapshots: service.store.snapshots)
        let show = presence.shows(
            preference: service.store.showsInMenuBar, eligible: eligible, now: now)
        if show == (menuBarController != nil) {
            menuBarController?.refresh()
        } else {
            menuBarController?.remove()
            menuBarController = show ? MusicMenuBarController(coordinator: self) : nil
        }
        scheduleGrace(now: now)
    }

    private func scheduleGrace(now: Date) {
        graceTask?.cancel()
        guard let since = presence.hiddenSince, menuBarController != nil else { return }
        let remaining = MusicMenuBarPresence.grace - now.timeIntervalSince(since)
        guard remaining > 0 else { return }
        graceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.applyMenuBarItem()
        }
    }

    private func trackPlayback() {
        guard !isTrackingPlayback else { return }
        isTrackingPlayback = true
        observePlayback()
    }

    private func observePlayback() {
        withObservationTracking {
            _ = service.store.snapshots
            _ = service.store.monitored
            _ = service.store.showsInMenuBar
            _ = service.store.isBusy
            _ = service.store.selectedPlayer
            _ = service.displayedRating(for: .appleMusic)
            _ = service.displayedRating(for: .tvTunes)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyCommandVisibility()
                self.applyMenuBarItem()
                self.observePlayback()
            }
        }
    }

    func reconnect(_ player: MusicPlayer) { Task { await service.connect(player) } }
    func refresh() { Task { await service.refresh() } }

    func perform(_ command: MusicCommand, player: MusicPlayer) {
        Task { await service.perform(command, player: player) }
    }

    func rate(_ stars: Int) {
        guard let player = MusicCommandTarget.player(
            monitored: service.store.monitored, snapshots: service.store.snapshots,
            preferred: service.store.selectedPlayer
        ) else {
            core.showMessage(String(localized: "Nothing is playing."), tone: .neutral)
            return
        }
        Task {
            switch await service.rate(stars, player: player) {
            case .applied(let playback):
                let glyphs = MusicRating.whole(stars).hudGlyphs
                core.showMessage(String(localized: "\(glyphs)  \(playback.track)"))
            case .unchanged:
                break
            case .refused(let message):
                core.showMessage(message, tone: .neutral)
            case .failed(let message):
                core.showMessage(message, tone: .danger)
            }
        }
    }

    func selectPlayer(_ player: MusicPlayer) { service.store.selectedPlayer = player }
    func setHistoryEnabled(_ enabled: Bool) { service.store.setHistoryEnabled(enabled) }
    func setRemoteEnabled(_ enabled: Bool) { service.setRemoteEnabled(enabled) }

    func clearHistory() async {
        guard await core.confirm(title: "Clear listening history?",
            message: "This removes the listening history saved on this Mac.", symbol: "music.note",
            confirmTitle: "Clear History") else { return }
        service.store.clearHistory()
    }

    func rotatePairing() async {
        guard await core.confirm(title: "Reset gadget pairing?",
            message: "Connected gadgets will disconnect and need the new pairing token.",
            symbol: "antenna.radiowaves.left.and.right", confirmTitle: "Reset Pairing") else { return }
        service.rotatePairing()
    }
}
