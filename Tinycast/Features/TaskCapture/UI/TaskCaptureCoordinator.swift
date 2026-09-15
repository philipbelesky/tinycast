import AppKit

/// Turns a capture query into a task in OmniFocus or TextFlow. See docs/features/task-capture.md.
@MainActor
final class TaskCaptureCoordinator {
    private let index: TaskCaptureIndex
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore

    init(
        index: TaskCaptureIndex, settings: AppSettings, paletteCoordinator: PaletteCoordinator,
        core: AppCore
    ) {
        self.index = index
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    func isEnabled(_ destination: TaskCaptureDestination) -> Bool {
        switch destination {
        case .omniFocus: settings.taskCaptureOmniFocusEnabled
        case .textFlow: settings.taskCaptureTextFlowEnabled
        }
    }

    /// Switched on and actually present; a scope for an app that is not installed is a dead end.
    func isOffered(_ destination: TaskCaptureDestination) -> Bool {
        isEnabled(destination) && index.isAvailable(destination)
    }

    /// Parsed afresh per keystroke — the grammar is a single pass over a short string.
    func preview(query: String, destination: TaskCaptureDestination) -> TaskCapturePreview {
        TaskCapturePreview(
            task: TaskCaptureGrammar.parse(query, now: Date(), calendar: .current),
            destination: destination, catalog: index.catalogs[destination])
    }

    func completions(query: String, destination: TaskCaptureDestination) -> [TaskCaptureCompletion] {
        guard let context = TaskCaptureGrammar.completionContext(in: query) else { return [] }
        return index.completions(for: context, destination: destination)
    }

    /// Writes the completion into the field; the card, not the completion, is what ↵ then adds.
    func accept(_ completion: TaskCaptureCompletion, palette: PaletteState) {
        palette.query = TaskCaptureGrammar.accepting(completion.value, in: palette.query)
        palette.selection = 0
    }

    func primaryActionTitle(for destination: TaskCaptureDestination) -> String {
        "Add to \(destination.title)"
    }

    /// The palette hides first: the add runs against the app the user was in, not over it.
    func capture(_ preview: TaskCapturePreview) {
        guard preview.canCapture, isEnabled(preview.destination) else { return }
        paletteCoordinator.hidePalette()
        paletteCoordinator.popToRootNow()
        Task { await add(preview) }
    }

    /// The TaskPaper line the card describes, for pasting into anything that reads the format.
    func copyTaskPaper(_ preview: TaskCapturePreview) {
        guard preview.canCapture else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(TaskPaperFormatter.taskPaper(preview.sent, calendar: .current))
    }

    /// On the palette's own trigger, like herdr: cheap, local, and stale the moment an app changes.
    func refresh() async {
        await index.refreshAvailability()
        if isOffered(.textFlow) { await index.refreshCatalog(.textFlow) }
    }

    /// OmniFocus is read only once its scope is armed, so the Automation prompt lands in context.
    func scopeArmed(_ destination: TaskCaptureDestination) {
        guard destination == .omniFocus, settings.taskCaptureOmniFocusSuggestions, isOffered(.omniFocus)
        else { return }
        Task { await index.refreshCatalog(.omniFocus) }
    }

    func refreshCatalogNow(_ destination: TaskCaptureDestination) async {
        await index.refreshAvailability()
        await index.refreshCatalog(destination, force: true)
    }

    private func add(_ preview: TaskCapturePreview) async {
        let task = preview.sent
        switch preview.destination {
        case .omniFocus:
            guard let url = TaskPaperFormatter.omniFocusURL(task, calendar: .current) else { return }
            if await OmniFocusRunner.paste(url) {
                core.showMessage(Self.confirmation(task, in: "OmniFocus"))
            } else {
                await report(
                    "OmniFocus did not accept the task", message: "The paste link could not be opened.")
            }
        case .textFlow:
            await addToTextFlow(task)
        }
    }

    /// The CLI needs the app: when it is not running, launch it and keep trying while it starts.
    private func addToTextFlow(_ task: CapturedTask) async {
        let located = index.textFlowExecutable
        guard let executable = located != nil ? located : await TextFlowRunner.locate() else {
            await report(
                "TextFlow's command line was not found",
                message: "Install TextFlow to /Applications, or put `textflow` on the default path.")
            return
        }
        var launched = false
        attempts: for _ in 0..<12 {
            do {
                _ = try await TextFlowRunner.add(task, executable: executable, calendar: .current)
                core.showMessage(Self.confirmation(task, in: "TextFlow"))
                return
            } catch {
                switch error {
                case .notRunning:
                    if !launched {
                        guard await TextFlowRunner.launchApp() else { break attempts }
                        launched = true
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                case .failed(let message):
                    await report("TextFlow did not add the task", message: message)
                    return
                }
            }
        }
        await report("TextFlow is not running", message: "Open TextFlow and try again.")
    }

    private static func confirmation(_ task: CapturedTask, in app: String) -> String {
        "Added to \(app) · \(task.project ?? "Inbox")"
    }

    private func report(_ title: String, message: String) async {
        _ = await core.reportFailure(
            title: title, message: message, symbol: "checkmark.circle.trianglebadge.exclamationmark",
            recovery: nil)
    }
}
