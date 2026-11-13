import AppKit

/// What the menu bar buttons draw. Busy is left out: dimming them on every poll would flicker the bar.
struct MusicMenuBarModel: Equatable, Sendable {
    var track: String
    var detail: String
    var rating: MusicRating?
    var status: MusicPlayback.Status
    var canPrevious: Bool
    var player: MusicPlayer
}

/// Transport and stars as buttons in the menu bar itself, so one click acts without opening anything.
@MainActor
final class MusicMenuBarController: NSObject {
    private unowned let coordinator: MusicCoordinator
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let stack = NSStackView()
    private var transport: [MusicCommand: NSButton] = [:]
    private var stars: [NSButton] = []
    private var displayed: MusicMenuBarModel?

    private static let transportOrder: [MusicCommand] = [
        .previousAlbum, .previousTrack, .toggle, .nextTrack, .nextAlbum
    ]
    private static let glyphPoints: CGFloat = 13
    private static let groupGap: CGFloat = 8
    private static let edgeInset: CGFloat = 6

    init(coordinator: MusicCoordinator) {
        self.coordinator = coordinator
        super.init()
        status.autosaveName = "Music"
        menu.addItem(item(String(localized: "Music Controls…"), action: #selector(showControls)))
        menu.addItem(item(String(localized: "Music Settings…"), action: #selector(showSettings)))
        guard let button = status.button else { return }
        for command in Self.transportOrder {
            let control = glyphButton(action: #selector(performTransport(_:)))
            control.tag = Self.transportOrder.firstIndex(of: command) ?? 0
            transport[command] = control
            stack.addArrangedSubview(control)
        }
        for star in 1...5 {
            let control = glyphButton(action: #selector(rate(_:)))
            control.tag = star
            control.setAccessibilityLabel(String(localized: "Rate \(star) stars"))
            stars.append(control)
            stack.addArrangedSubview(control)
        }
        if let lastTransport = transport[.nextAlbum] {
            stack.setCustomSpacing(Self.groupGap, after: lastTransport)
        }
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: Self.edgeInset)
        ])
        button.target = self
        button.action = #selector(showMenu(_:))
        button.sendAction(on: [.rightMouseUp])
        refresh()
    }

    func remove() {
        menu.cancelTracking()
        NSStatusBar.system.removeStatusItem(status)
    }

    func refresh() {
        let model = coordinator.menuBarModel()
        guard model != displayed else { return }
        displayed = model
        let playing = model.status == .playing
        configure(.previousAlbum, "backward.end.alt", String(localized: "Previous album"),
            enabled: model.canPrevious)
        configure(.previousTrack, "backward.end.fill", String(localized: "Previous track"), enabled: true)
        configure(.toggle, playing ? "pause.fill" : "play.fill",
            playing ? String(localized: "Pause") : String(localized: "Play"), enabled: true)
        configure(.nextTrack, "forward.end.fill", String(localized: "Next track"), enabled: true)
        configure(.nextAlbum, "forward.end.alt", String(localized: "Next album"), enabled: true)
        for control in stars {
            control.isHidden = model.rating == nil
            guard let rating = model.rating else { continue }
            control.image = glyph(Self.starSymbol(rating.fill(for: control.tag)))
        }
        let summary = model.detail.isEmpty ? model.track : "\(model.track) — \(model.detail)"
        for control in stars { control.toolTip = summary }
        status.button?.setAccessibilityLabel(summary)
        stack.layoutSubtreeIfNeeded()
        status.length = stack.fittingSize.width + Self.edgeInset * 2
    }

    private static func starSymbol(_ fill: MusicRating.StarFill) -> String {
        switch fill {
        case .full: "star.fill"
        case .half: "star.leadinghalf.filled"
        case .empty: "star"
        }
    }

    private func configure(_ command: MusicCommand, _ symbol: String, _ title: String, enabled: Bool) {
        guard let control = transport[command] else { return }
        control.image = glyph(symbol)
        control.toolTip = title
        control.setAccessibilityLabel(title)
        control.isEnabled = enabled
    }

    private func glyph(_ symbol: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: Self.glyphPoints, weight: .regular))
        image?.isTemplate = true
        return image
    }

    private func glyphButton(action: Selector) -> NSButton {
        let control = NSButton(title: "", target: self, action: action)
        control.isBordered = false
        control.imagePosition = .imageOnly
        control.setButtonType(.momentaryChange)
        return control
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func performTransport(_ sender: NSButton) {
        guard let model = displayed, Self.transportOrder.indices.contains(sender.tag) else { return }
        coordinator.perform(Self.transportOrder[sender.tag], player: model.player)
        refresh()
    }

    @objc private func rate(_ sender: NSButton) {
        coordinator.rate(sender.tag)
        refresh()
    }

    @objc private func showMenu(_ sender: NSStatusBarButton) {
        // Attached only for this click, so the buttons keep their own left clicks.
        status.menu = menu
        sender.performClick(nil)
        status.menu = nil
    }

    @objc private func showControls() { coordinator.show() }
    @objc private func showSettings() { coordinator.showSettings() }
}
