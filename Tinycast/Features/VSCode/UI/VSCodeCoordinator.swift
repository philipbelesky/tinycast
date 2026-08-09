import AppKit

/// Opens a VS Code project. See docs/features/vscode.md.
@MainActor
final class VSCodeCoordinator {
    private let store: VSCodeStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let paletteCoordinator: PaletteCoordinator

    init(
        store: VSCodeStore, settings: AppSettings, appIndex: AppIndex,
        paletteCoordinator: PaletteCoordinator
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.paletteCoordinator = paletteCoordinator
    }

    /// Republishes the launcher slice from what the store holds, honouring both switches.
    func applyVSCodePresence() {
        let visible = settings.vsCodeEnabled && settings.vsCodeShowInLauncher
        appIndex.setVSCodeProjects(visible ? store.projects : [])
    }

    func refresh() async {
        guard settings.vsCodeEnabled else {
            store.clear()
            return
        }
        await store.refresh()
    }

    func open(path: String) {
        guard settings.vsCodeEnabled, let project = store.project(path: path) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task { await VSCodeProjectScanner.open(project) }
    }
}
