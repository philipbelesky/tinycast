import Foundation

/// Where a captured task goes. Each has a scope keyword, a runner and its own field support.
enum TaskCaptureDestination: String, CaseIterable, Codable, Sendable, Identifiable {
    case omniFocus
    case textFlow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .omniFocus: "OmniFocus"
        case .textFlow: "TextFlow"
        }
    }

    var symbol: String {
        switch self {
        case .omniFocus: "checkmark.circle"
        case .textFlow: "checklist"
        }
    }

    /// Fields the destination can store; the card strikes through the rest rather than dropping them.
    var supportedFields: Set<CapturedTask.Field> {
        switch self {
        case .omniFocus: [.project, .tags, .due, .defer, .flag, .estimate, .note]
        case .textFlow: [.project, .tags, .due, .defer, .flag, .note, .status, .assignee]
        }
    }
}

/// TextFlow's task statuses that make sense at capture; `active` is the default and unspoken.
enum TaskStatus: String, Sendable, Equatable {
    case inProgress = "inprogress"
    case onHold = "onhold"

    var title: String {
        switch self {
        case .inProgress: "In progress"
        case .onHold: "On hold"
        }
    }
}

/// One parsed capture query: the prose that is the task, and every attribute pulled out of it.
struct CapturedTask: Equatable, Sendable {
    enum Field: CaseIterable, Sendable {
        case project, tags, due, `defer`, flag, estimate, note, status, assignee
    }

    var title = ""
    var project: String?
    var tags: [String] = []
    var due: TaskDate?
    var deferDate: TaskDate?
    /// A `due` phrase nothing could read — kept so the card can show it rather than lose it.
    var unresolvedDue: String?
    var unresolvedDefer: String?
    var flagged = false
    var estimateMinutes: Int?
    var note: String?
    var status: TaskStatus?
    var assignee: String?

    var isTitled: Bool { !title.isEmpty }

    /// The fields this task actually uses, in display order.
    var fields: [Field] {
        Field.allCases.filter { field in
            switch field {
            case .project: project != nil
            case .tags: !tags.isEmpty
            case .due: due != nil || unresolvedDue != nil
            case .defer: deferDate != nil || unresolvedDefer != nil
            case .flag: flagged
            case .estimate: estimateMinutes != nil
            case .note: note != nil
            case .status: status != nil
            case .assignee: assignee != nil
            }
        }
    }
}

/// What the card shows and the runners send: the task, and what the destination will drop.
struct TaskCapturePreview: Equatable, Sendable {
    let task: CapturedTask
    let destination: TaskCaptureDestination
    /// The project is not in a loaded catalog. OmniFocus would otherwise mint a project named
    /// after the URL path, so the task goes to the inbox and the card says so first.
    let projectUnknown: Bool

    init(task: CapturedTask, destination: TaskCaptureDestination, catalog: TaskCaptureCatalog? = nil) {
        self.task = task
        self.destination = destination
        if let project = task.project, let catalog {
            projectUnknown = !catalog.knows(project: project)
        } else {
            projectUnknown = false
        }
    }

    var unsupported: [CapturedTask.Field] {
        task.fields.filter { !destination.supportedFields.contains($0) }
    }

    /// The task as the sink receives it: the card's own dropped fields removed.
    var sent: CapturedTask {
        guard projectUnknown else { return task }
        var stripped = task
        stripped.project = nil
        return stripped
    }

    var canCapture: Bool { task.isTitled }
}
