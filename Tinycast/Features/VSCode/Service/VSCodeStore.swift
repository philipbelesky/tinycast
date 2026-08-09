import Foundation

/// The VS Code projects on offer, refreshed when the palette opens. See docs/features/vscode.md.
@MainActor
@Observable
final class VSCodeStore {
    private(set) var projects: [VSCodeProject] = []

    /// Set by `AppCore` so a refresh can republish the launcher slice.
    @ObservationIgnored var onChange: (([VSCodeProject]) -> Void)?

    /// Collapses a burst: the palette can be re-shown while a scan is still in flight.
    @ObservationIgnored private var scanning = false

    var isInstalled: Bool { VSCodeProjectScanner.applicationURL != nil }

    func refresh() async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        let found = await VSCodeProjectScanner.scan()
        guard found != projects else { return }
        projects = found
        onChange?(found)
    }

    /// Drops every row without touching the disk, for the switch that turns the feature off.
    func clear() {
        guard !projects.isEmpty else { return }
        projects = []
        onChange?([])
    }

    func project(path: String) -> VSCodeProject? { projects.first { $0.path == path } }
}
