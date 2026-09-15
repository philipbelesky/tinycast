import AppKit

/// Every TextFlow effect, all through its CLI, which speaks to the running app.
enum TextFlowRunner {
    static let bundleID = "com.belesky.textflow"
    /// The CLI ships inside the app; a `~/.local/bin` symlink is the documented convenience.
    private static let bundledHelper = "/Applications/TextFlow.app/Contents/Helpers/textflow"
    /// The CLI's own exit status for "TextFlow is not running".
    private static let notRunningStatus: Int32 = 5

    enum Failure: Error, Equatable {
        case notRunning
        case failed(String)
    }

    nonisolated static func locate() async -> URL? {
        let bundled = URL(fileURLWithPath: bundledHelper)
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        return await ExecutableLocator.locate("textflow")
    }

    /// Adds the task, then sets its status in a second call: `add` carries no status flag.
    nonisolated static func add(
        _ task: CapturedTask, executable: URL, calendar: Calendar
    ) async throws(Failure) -> TextFlowCommand.AddResult {
        let output = try await run(executable, TextFlowCommand.addArguments(task, calendar: calendar))
        guard let result = TextFlowCommand.parseAddResult(output) else {
            throw .failed(TextFlowCommand.errorMessage(output) ?? "unreadable reply")
        }
        if let status = task.status {
            _ = try await run(
                executable, TextFlowCommand.statusArguments(reference: result.reference, status: status))
        }
        return result
    }

    nonisolated static func readCatalog(executable: URL) async throws(Failure) -> TaskCaptureCatalog {
        let projects = try await run(executable, ["projects", "--json"])
        let tags = try await run(executable, ["tags", "--json"])
        return TaskCaptureCatalog(
            projects: TextFlowCommand.parseProjects(projects), tags: TextFlowCommand.parseTags(tags))
    }

    /// Launches the app the CLI needs, in the background: the user is still where they summoned.
    @MainActor static func launchApp() async -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        return (try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)) != nil
    }

    nonisolated private static func run(
        _ executable: URL, _ arguments: [String]
    ) async throws(Failure) -> Data {
        let result = await CommandLineProcess.run(
            executable.path, arguments, environment: SubprocessEnvironment.inherited)
        guard let result else { throw .failed("textflow did not run") }
        guard result.status == 0 else {
            if result.status == notRunningStatus { throw .notRunning }
            let message = TextFlowCommand.errorMessage(result.output) ?? result.errorText
            throw .failed(message.isEmpty ? "textflow exited \(result.status)" : message)
        }
        return result.output
    }
}
