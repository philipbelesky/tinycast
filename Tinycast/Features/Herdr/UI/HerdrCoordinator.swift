import AppKit

/// Focuses a herdr target, then raises the app hosting it. See docs/features/herdr.md.
@MainActor
final class HerdrCoordinator {
    private let store: HerdrStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let paletteCoordinator: PaletteCoordinator
    /// Detection costs a process-table scan, so it is resolved once and reused.
    private var detectedHost: String?

    init(
        store: HerdrStore, settings: AppSettings, appIndex: AppIndex,
        paletteCoordinator: PaletteCoordinator
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.paletteCoordinator = paletteCoordinator
    }

    /// Republishes the launcher slice from what the store holds, honouring both switches.
    func applyHerdrPresence() {
        let visible = settings.herdrEnabled && settings.herdrShowInLauncher
        appIndex.setHerdrTargets(visible ? store.targets : [])
    }

    func refresh() async {
        guard settings.herdrEnabled else {
            store.clear()
            return
        }
        await store.refresh()
    }

    /// herdr's focus first, then the app: the reverse order raises a window that then jumps.
    func focus(targetID: String) {
        guard settings.herdrEnabled, let target = store.target(id: targetID) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task {
            guard await HerdrClient.focus(target) else { return }
            await revealHost()
        }
    }

    /// The override wins outright — detection is a convenience, not an authority.
    private func revealHost() async {
        var bundleID = settings.herdrTerminalBundleID?.nilIfBlank
        if bundleID == nil {
            if detectedHost == nil { detectedHost = await HerdrClient.hostBundleID() }
            bundleID = detectedHost
        }
        // No host is the normal outcome for a session attached over ssh: focus still moved.
        guard let bundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return }
        AppLauncher.launch(url)
    }
}

extension String {
    fileprivate var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
