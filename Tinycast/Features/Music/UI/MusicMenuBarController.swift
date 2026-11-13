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
    private enum Segment: Equatable {
        case transport(MusicCommand)
        case star(Int)
    }

    private unowned let coordinator: MusicCoordinator
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var displayed: MusicMenuBarModel?
    private var hitRanges: [(range: ClosedRange<CGFloat>, segment: Segment)] = []

    private static let glyphPoints: CGFloat = 13
    private static let glyphGap: CGFloat = 5
    private static let groupGap: CGFloat = 10
    private static let disabledAlpha: CGFloat = 0.35

    init(coordinator: MusicCoordinator) {
        self.coordinator = coordinator
        super.init()
        status.autosaveName = "Music"
        menu.addItem(item(String(localized: "Music Controls…"), action: #selector(showControls)))
        menu.addItem(item(String(localized: "Music Settings…"), action: #selector(showSettings)))
        guard let button = status.button else { return }
        button.imagePosition = .imageOnly
        // Stable, because menu bar managers key an item's placement on this name.
        button.setAccessibilityLabel(String(localized: "Music"))
        (button.cell as? NSButtonCell)?.highlightsBy = []
        button.target = self
        button.action = #selector(click(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        var glyphs: [(segment: Segment, symbol: String, enabled: Bool)] = [
            (.transport(.previousAlbum), "backward.end.alt", model.canPrevious),
            (.transport(.previousTrack), "backward.end.fill", true),
            (.transport(.toggle), playing ? "pause.fill" : "play.fill", true),
            (.transport(.nextTrack), "forward.end.fill", true),
            (.transport(.nextAlbum), "forward.end.alt", true)
        ]
        if let rating = model.rating {
            glyphs += (1...5).map { (.star($0), Self.starSymbol(rating.fill(for: $0)), true) }
        }
        draw(glyphs)
        let summary = model.detail.isEmpty ? model.track : "\(model.track) — \(model.detail)"
        status.button?.toolTip = summary
    }

    /// One image, hit-tested by position: subviews in a status button are cropped by the system's host.
    private func draw(_ glyphs: [(segment: Segment, symbol: String, enabled: Bool)]) {
        let images = glyphs.map { glyph in
            NSImage(systemSymbolName: glyph.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: Self.glyphPoints, weight: .regular))
        }
        var origins: [CGFloat] = []
        var x: CGFloat = 0
        for (index, image) in images.enumerated() {
            if index > 0 {
                let startsStars = glyphs[index].segment == .star(1)
                x += startsStars ? Self.groupGap : Self.glyphGap
            }
            origins.append(x)
            x += image?.size.width ?? 0
        }
        let height = images.compactMap { $0?.size.height }.max() ?? Self.glyphPoints
        let composite = NSImage(size: CGSize(width: x, height: height), flipped: false) { _ in
            for (index, image) in images.enumerated() {
                guard let image else { continue }
                let rect = CGRect(
                    x: origins[index], y: (height - image.size.height) / 2,
                    width: image.size.width, height: image.size.height)
                image.draw(
                    in: rect, from: .zero, operation: .sourceOver,
                    fraction: glyphs[index].enabled ? 1 : Self.disabledAlpha)
            }
            return true
        }
        composite.isTemplate = true
        hitRanges = glyphs.indices.map { index in
            let width = images[index]?.size.width ?? 0
            let leading = index == 0 ? 0 : (origins[index - 1] + (images[index - 1]?.size.width ?? 0) + origins[index]) / 2
            let trailing = index == glyphs.count - 1
                ? x : (origins[index] + width + origins[index + 1]) / 2
            return (leading...trailing, glyphs[index].segment)
        }
        status.button?.image = composite
    }

    private static func starSymbol(_ fill: MusicRating.StarFill) -> String {
        switch fill {
        case .full: "star.fill"
        case .half: "star.leadinghalf.filled"
        case .empty: "star"
        }
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func click(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            // Attached only for this click, so a plain click stays free to press a glyph.
            status.menu = menu
            sender.performClick(nil)
            status.menu = nil
            return
        }
        guard let model = displayed, let image = sender.image else { return }
        let point = sender.convert(event.locationInWindow, from: nil)
        let offset = point.x - (sender.bounds.width - image.size.width) / 2
        guard let segment = hitRanges.first(where: { $0.range.contains(offset) })?.segment else { return }
        switch segment {
        case .transport(let command):
            guard command != .previousAlbum || model.canPrevious else { return }
            coordinator.perform(command, player: model.player)
        case .star(let stars):
            coordinator.rate(stars)
        }
        refresh()
    }

    @objc private func showControls() { coordinator.show() }
    @objc private func showSettings() { coordinator.showSettings() }
}
