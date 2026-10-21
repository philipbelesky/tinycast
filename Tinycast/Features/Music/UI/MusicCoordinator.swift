import AppKit
import SwiftUI

/// Music's window and action surface outlive the palette without owning playback themselves.
@MainActor
@Observable
final class MusicCoordinator {
    let service: MusicPlaybackService
    private let window: AppWindowController
    private unowned let core: AppCore

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

    func setMonitoring(_ player: MusicPlayer, enabled: Bool) {
        Task { await service.setMonitoring(player, enabled: enabled) }
    }

    func reconnect(_ player: MusicPlayer) { Task { await service.connect(player) } }
    func refresh() { Task { await service.refresh() } }

    func perform(_ command: MusicCommand, player: MusicPlayer) {
        Task { await service.perform(command, player: player) }
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
