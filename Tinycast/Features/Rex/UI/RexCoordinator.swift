import AppKit

/// Selects a Rex tab in the local Rex app, then raises it. See docs/features/rex.md.
@MainActor
final class RexCoordinator {
    private let store: RexStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let paletteCoordinator: PaletteCoordinator

    init(
        store: RexStore, settings: AppSettings, appIndex: AppIndex,
        paletteCoordinator: PaletteCoordinator
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.paletteCoordinator = paletteCoordinator
    }

    /// Republishes the launcher slice from what the store holds, honouring both switches.
    func applyRexPresence() {
        let visible = settings.rexEnabled && settings.rexShowInLauncher
        appIndex.setRexTargets(visible ? store.targets : [])
    }

    func refresh() async {
        guard settings.rexEnabled else {
            store.clear()
            return
        }
        await store.refresh()
    }

    /// The tab first, then the app: the reverse order raises a window that then jumps.
    func focus(targetID: String) {
        guard settings.rexEnabled, let target = store.target(id: targetID) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task {
            guard await store.select(target), let host = store.host else { return }
            RexClient.reveal(host)
        }
    }
}
