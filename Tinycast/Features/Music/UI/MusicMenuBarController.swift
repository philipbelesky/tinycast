import AppKit
import SwiftUI

/// One menu bar glyph. The panel is a menu, not stars drawn in the bar.
@MainActor
final class MusicMenuBarController: NSObject, NSMenuDelegate {
    private unowned let coordinator: MusicCoordinator
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let panelItem = NSMenuItem()
    private let hosting: NSHostingView<MusicMenuBarHost>
    private var displayed: MusicMenuBarModel?
    private var pump: Timer?

    init(coordinator: MusicCoordinator) {
        self.coordinator = coordinator
        hosting = NSHostingView(rootView: MusicMenuBarHost(
            model: .empty, metrics: .standard, rate: { _ in }, perform: { _ in }))
        super.init()
        status.autosaveName = "Music"
        menu.delegate = self
        menu.autoenablesItems = false
        panelItem.view = hosting
        menu.addItem(panelItem)
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Music Controls…"), action: #selector(showControls)))
        menu.addItem(item(String(localized: "Music Settings…"), action: #selector(showSettings)))
        guard let button = status.button else { return }
        let image = NSImage(
            systemSymbolName: "music.note", accessibilityDescription: String(localized: "Music"))
        image?.isTemplate = true
        button.image = image
        status.menu = menu
        refreshPanel()
    }

    func remove() {
        pump?.invalidate()
        menu.cancelTracking()
        NSStatusBar.system.removeStatusItem(status)
    }

    func refreshPanel() {
        let model = coordinator.menuBarModel()
        guard model != displayed else { return }
        displayed = model
        let metrics = coordinator.interfaceMetrics
        hosting.rootView = MusicMenuBarHost(
            model: model, metrics: metrics,
            rate: { [weak coordinator] stars in coordinator?.rateFromMenu(stars) },
            perform: { [weak coordinator] command in
                coordinator?.performFromMenu(command, player: model.player)
            })
        hosting.frame.size.width = metrics.size.menuWidth
        let fitted = hosting.fittingSize
        hosting.frame.size = CGSize(width: metrics.size.menuWidth, height: max(fitted.height, 1))
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshPanel()
        // Polled in the common run-loop modes so the panel stays current while the menu tracks.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPanel() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pump = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        pump?.invalidate()
        pump = nil
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showControls() { coordinator.show() }
    @objc private func showSettings() { coordinator.showSettings() }
}

/// Injects Interface Size. `NSHostingView`'s root type cannot carry the environment modifier itself.
private struct MusicMenuBarHost: View {
    var model: MusicMenuBarModel
    var metrics: InterfaceMetrics
    var rate: (Int) -> Void
    var perform: (MusicCommand) -> Void

    var body: some View {
        MusicMenuBarPanel(model: model, rate: rate, perform: perform)
            .environment(\.metrics, metrics)
    }
}

extension MusicMenuBarModel {
    static let empty = MusicMenuBarModel(
        playerName: nil, track: String(localized: "Nothing playing"), detail: "", rating: nil,
        status: .stopped, canPrevious: false, isBusy: false, player: .appleMusic)
}
