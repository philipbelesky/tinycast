import Foundation
import Observation

/// What each destination can complete against, and whether it is there to capture into at all.
/// Nothing here persists: a catalog is re-read from the app that owns it.
@MainActor
@Observable
final class TaskCaptureIndex {
    private(set) var textFlowExecutable: URL?
    private(set) var omniFocusInstalled = false
    private(set) var catalogs: [TaskCaptureDestination: TaskCaptureCatalog] = [:]
    /// The last read's failure, for the Settings pane; cleared by the next success.
    private(set) var failures: [TaskCaptureDestination: String] = [:]
    /// True once OmniFocus refused an Apple event: the pane sends the user to System Settings.
    private(set) var omniFocusAutomationDenied = false
    @ObservationIgnored private var refreshedAt: [TaskCaptureDestination: Date] = [:]
    @ObservationIgnored private var inFlight: [TaskCaptureDestination: Task<Void, Never>] = [:]
    /// A catalog younger than this is not re-read; the apps change far slower than the palette opens.
    private static let staleAfter: TimeInterval = 5 * 60

    func isAvailable(_ destination: TaskCaptureDestination) -> Bool {
        switch destination {
        case .omniFocus: omniFocusInstalled
        case .textFlow: textFlowExecutable != nil
        }
    }

    func catalog(for destination: TaskCaptureDestination) -> TaskCaptureCatalog {
        catalogs[destination] ?? .empty
    }

    func completions(
        for context: TaskCaptureGrammar.CompletionContext, destination: TaskCaptureDestination
    ) -> [TaskCaptureCompletion] {
        catalog(for: destination).completions(for: context)
    }

    func refreshAvailability() async {
        omniFocusInstalled = OmniFocusRunner.isInstalled
        textFlowExecutable = await TextFlowRunner.locate()
    }

    /// Re-reads one destination's projects and tags, coalescing a read already under way.
    func refreshCatalog(_ destination: TaskCaptureDestination, force: Bool = false) async {
        if let running = inFlight[destination] { return await running.value }
        if !force, let last = refreshedAt[destination], Date().timeIntervalSince(last) < Self.staleAfter {
            return
        }
        let task = Task { await read(destination) }
        inFlight[destination] = task
        await task.value
        inFlight[destination] = nil
    }

    private func read(_ destination: TaskCaptureDestination) async {
        switch destination {
        case .omniFocus:
            switch await OmniFocusRunner.readCatalog() {
            case .success(let catalog): record(catalog, for: destination)
            case .failure(.notAuthorized):
                omniFocusAutomationDenied = true
                failures[destination] = "Tinycast is not allowed to control OmniFocus"
            case .failure(.failed(let message)): failures[destination] = message
            }
        case .textFlow:
            guard let executable = textFlowExecutable else { return }
            do {
                record(try await TextFlowRunner.readCatalog(executable: executable), for: destination)
            } catch {
                switch error {
                case .notRunning: failures[destination] = "TextFlow is not running"
                case .failed(let message): failures[destination] = message
                }
            }
        }
    }

    private func record(_ catalog: TaskCaptureCatalog, for destination: TaskCaptureDestination) {
        catalogs[destination] = catalog
        failures[destination] = nil
        refreshedAt[destination] = Date()
        if destination == .omniFocus { omniFocusAutomationDenied = false }
    }
}
