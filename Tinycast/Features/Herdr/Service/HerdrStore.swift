import Foundation

/// The current herdr targets, refreshed when the palette opens. See docs/features/herdr.md.
@MainActor
@Observable
final class HerdrStore {
    private(set) var targets: [HerdrTarget] = []
    /// False until a refresh has actually reached herdr; the Settings pane is the only place it shows.
    private(set) var isReachable = false

    /// Set by `AppCore` so a refresh can republish the launcher slice.
    @ObservationIgnored var onChange: (([HerdrTarget]) -> Void)?

    /// Collapses a burst: the palette can be re-shown while a refresh is still in flight.
    @ObservationIgnored private var refreshing = false

    var isAvailable: Bool { HerdrClient.isAvailable }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let fetched = await HerdrClient.snapshot()
        isReachable = !fetched.isEmpty || HerdrClient.isAvailable
        guard fetched != targets else { return }
        targets = fetched
        onChange?(fetched)
    }

    /// Drops every row without touching herdr, for the switch that turns the feature off.
    func clear() {
        guard !targets.isEmpty else { return }
        targets = []
        onChange?([])
    }

    func target(id: String) -> HerdrTarget? { targets.first { $0.id == id } }
}
