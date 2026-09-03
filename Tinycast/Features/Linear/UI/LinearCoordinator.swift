import AppKit

/// Opens a Linear destination or issue in the desktop app or browser. See docs/features/linear.md.
@MainActor
final class LinearCoordinator {
    private let store: LinearStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let paletteCoordinator: PaletteCoordinator

    init(
        store: LinearStore, settings: AppSettings, appIndex: AppIndex,
        paletteCoordinator: PaletteCoordinator
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.paletteCoordinator = paletteCoordinator
    }

    /// Republishes the launcher slice. Consent is the store's, so this only reads what it holds.
    func applyLinearPresence() {
        appIndex.setLinearTargets(settings.linearShowInLauncher ? store.targets : [])
    }

    func refresh() async {
        await store.refreshIfStale()
    }

    func open(id: String) {
        guard let view = store.target(id: id) else { return }
        let destination = settings.linearDestination
        guard let url = view.url(opening: destination) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task { await Self.open(url, destination: destination) }
    }

    /// The desktop app registers `linear://` at runtime, so a machine that has never launched it
    /// has no handler; the browser is where such a link belongs anyway.
    private static func open(_ url: URL, destination: LinearDestination) async {
        let workspace = NSWorkspace.shared
        if destination == .app, workspace.urlForApplication(toOpen: url) == nil {
            guard let view = URL(string: url.absoluteString.replacingOccurrences(
                of: "linear://linear.app/", with: "https://linear.app/"))
            else { return }
            workspace.open(view)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Linear answers the deep link without raising itself, so the reveal is a separate step —
        // the same split herdr's focus-then-reveal has.
        guard let app = try? await workspace.open(url, configuration: configuration) else { return }
        app.activate()
    }
}
