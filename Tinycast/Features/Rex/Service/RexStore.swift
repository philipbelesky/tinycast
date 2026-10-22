import Foundation

/// The current Rex tabs, refreshed when the palette opens. See docs/features/rex.md.
@MainActor
@Observable
final class RexStore {
    private(set) var targets: [RexTarget] = []
    /// The app that can show a tab; nil when Rex is only reachable from another Mac.
    @ObservationIgnored private(set) var host: RexSnapshot.Host?
    /// False until a lookup has run; the Settings pane is the only place it shows.
    private(set) var isAvailable = false

    /// Set by `AppCore` so a refresh can republish the launcher slice.
    @ObservationIgnored var onChange: (([RexTarget]) -> Void)?

    /// Collapses a burst: the palette can be re-shown while a refresh is still in flight.
    @ObservationIgnored private var refreshing = false
    /// Resolved once per launch: the path is stable, and the lookup costs a login shell.
    @ObservationIgnored private var executableLookup: Task<URL?, Never>?

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        guard let executable = await resolveExecutable() else { return }
        let snapshot = await RexClient.snapshot(executable: executable)
        host = snapshot.host
        guard snapshot.targets != targets else { return }
        targets = snapshot.targets
        onChange?(snapshot.targets)
    }

    /// Drops every row without touching Rex, for the switch that turns the feature off.
    func clear() {
        host = nil
        guard !targets.isEmpty else { return }
        targets = []
        onChange?([])
    }

    func target(id: String) -> RexTarget? { targets.first { $0.id == id } }

    func select(_ target: RexTarget) async -> Bool {
        guard let host, let executable = await resolveExecutable() else { return false }
        return await RexClient.select(target, host: host, executable: executable)
    }

    private func resolveExecutable() async -> URL? {
        let lookup = executableLookup ?? Task { await RexClient.locate() }
        executableLookup = lookup
        let located = await lookup.value
        isAvailable = located != nil
        return located
    }
}
