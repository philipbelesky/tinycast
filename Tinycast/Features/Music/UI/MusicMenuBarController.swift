import AppKit

/// What the menu bar buttons draw. Busy is left out: dimming them on every poll would flicker the bar.
struct MusicMenuBarModel: Equatable, Sendable {
    var track: String
    var detail: String
    var rating: MusicRating?
    var status: MusicPlayback.Status
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
    private var hitRanges: [(range: Range<CGFloat>, segment: Segment)] = []

    private static let glyphPoints: CGFloat = 13
    private static let starPoints: CGFloat = 11
    private static let transportGap: CGFloat = 7
    private static let starGap: CGFloat = 3
    private static let groupGap: CGFloat = 10

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
        var glyphs: [(segment: Segment, symbol: String)] = [
            (.transport(.previousTrack), "backward.end.fill"),
            (.transport(.toggle), playing ? "pause.fill" : "play.fill"),
            (.transport(.nextTrack), "forward.end.fill"),
            (.transport(.nextAlbum), "forward.end.alt.fill")
        ]
        if let rating = model.rating {
            glyphs += (1...5).map { (.star($0), Self.starSymbol(rating.fill(for: $0))) }
        }
        draw(glyphs)
        let summary = model.detail.isEmpty ? model.track : "\(model.track) — \(model.detail)"
        status.button?.toolTip = summary
    }

    /// One image, hit-tested by position: subviews in a status button are cropped by the system's host.
    private func draw(_ glyphs: [(segment: Segment, symbol: String)]) {
        let images = glyphs.map { glyph in
            NSImage(systemSymbolName: glyph.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: Self.points(glyph.segment), weight: .regular))
        }
        var origins: [CGFloat] = []
        var x: CGFloat = 0
        for (index, image) in images.enumerated() {
            if index > 0 {
                x += Self.gap(before: glyphs[index].segment)
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
                image.draw(in: rect)
            }
            return true
        }
        composite.isTemplate = true
        hitRanges = glyphs.indices.map { index in
            let width = images[index]?.size.width ?? 0
            let leading = index == 0 ? 0 : (origins[index - 1] + (images[index - 1]?.size.width ?? 0) + origins[index]) / 2
            let trailing = index == glyphs.count - 1
                ? x : (origins[index] + width + origins[index + 1]) / 2
            return (leading..<trailing, glyphs[index].segment)
        }
        status.button?.image = composite
    }

    private static func points(_ segment: Segment) -> CGFloat {
        if case .star = segment { return starPoints }
        return glyphPoints
    }

    private static func gap(before segment: Segment) -> CGFloat {
        switch segment {
        case .star(1): groupGap
        case .star: starGap
        case .transport: transportGap
        }
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
        guard let model = displayed, let image = sender.image, let window = sender.window else { return }
        // The system forwards every click at the item's centre, so only the pointer says which glyph.
        let pointer = NSEvent.mouseLocation
        let pointerScreen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? window.screen
        let mirrored = (window.screen?.frame.maxX ?? 0) - (pointerScreen?.frame.maxX ?? 0)
        let offset = pointer.x + mirrored - window.frame.minX - (window.frame.width - image.size.width) / 2
        guard let segment = hitRanges.first(where: { $0.range.contains(offset) })?.segment else { return }
        switch segment {
        case .transport(let command):
            coordinator.perform(command, player: model.player)
        case .star(let stars):
            coordinator.rate(stars)
        }
        refresh()
    }

    @objc private func showControls() { coordinator.show() }
    @objc private func showSettings() { coordinator.showSettings() }
}
