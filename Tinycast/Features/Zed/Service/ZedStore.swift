import Foundation

/// The Zed workspaces on offer, refreshed when the palette opens. See docs/features/zed.md.
@MainActor
@Observable
final class ZedStore {
    private(set) var projects: [ZedProject] = []

    /// Set by `AppCore` so a refresh can republish the launcher slice.
    @ObservationIgnored var onChange: (([ZedProject]) -> Void)?

    /// Collapses a burst: the palette can be re-shown while a scan is still in flight.
    @ObservationIgnored private var scanning = false

    var isInstalled: Bool { ZedProjectScanner.applicationURL != nil }

    func refresh() async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        let found = await ZedProjectScanner.scan()
        guard found != projects else { return }
        projects = found
        onChange?(found)
    }

    /// Drops every row without touching Zed's database, for the switch that turns the feature off.
    func clear() {
        guard !projects.isEmpty else { return }
        projects = []
        onChange?([])
    }

    func project(entryID: String) -> ZedProject? { projects.first { $0.entryID == entryID } }
}
