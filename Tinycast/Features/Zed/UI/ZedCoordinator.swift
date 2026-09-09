import AppKit

/// Opens a Zed workspace. See docs/features/zed.md.
@MainActor
final class ZedCoordinator {
    private let store: ZedStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let paletteCoordinator: PaletteCoordinator

    init(
        store: ZedStore, settings: AppSettings, appIndex: AppIndex,
        paletteCoordinator: PaletteCoordinator
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.paletteCoordinator = paletteCoordinator
    }

    /// Republishes the launcher slice from what the store holds, honouring both switches.
    func applyZedPresence() {
        let visible = settings.zedEnabled && settings.zedShowInLauncher
        appIndex.setZedProjects(visible ? store.projects : [])
    }

    func refresh() async {
        guard settings.zedEnabled else {
            store.clear()
            return
        }
        await store.refresh()
    }

    func open(entryID: String) {
        guard settings.zedEnabled, let project = store.project(entryID: entryID) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task { await ZedProjectScanner.open(project) }
    }
}
