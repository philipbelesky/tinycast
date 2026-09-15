import Foundation

/// The `textflow` CLI's side of a capture: the argument lists sent, the JSON replies read.
/// See docs/features/task-capture.md#textflow.
enum TextFlowCommand {
    struct AddResult: Equatable, Sendable {
        /// `@id`, which `status` addresses — never the text, which may not be unique.
        let reference: String
        let address: String
    }

    static func addArguments(_ task: CapturedTask, calendar: Calendar) -> [String] {
        var arguments = ["add", task.title]
        if let project = task.project { arguments += ["--in", project] }
        if let note = task.note { arguments += ["--note", note] }
        for tag in task.tags { arguments += ["--tags", tag] }
        if let deferDate = task.deferDate { arguments += ["--defer", deferDate.canonical(calendar: calendar)] }
        if let due = task.due { arguments += ["--due", due.canonical(calendar: calendar)] }
        if task.flagged { arguments.append("--flag") }
        if let assignee = task.assignee { arguments += ["--assignee", assignee] }
        return arguments + ["--json", "--assign-id"]
    }

    static func statusArguments(reference: String, status: TaskStatus) -> [String] {
        ["status", reference, status.rawValue, "--json"]
    }

    static func parseAddResult(_ data: Data) -> AddResult? {
        guard let reply = try? JSONDecoder().decode(WriteReply.self, from: data),
            let item = reply.item, let reference = item.reference, let address = item.address
        else { return nil }
        return AddResult(reference: reference, address: address)
    }

    static func errorMessage(_ data: Data) -> String? {
        (try? JSONDecoder().decode(ErrorReply.self, from: data))?.error?.message
    }

    /// Every unfinished project, walked folder by folder, the innermost folder as its detail.
    static func parseProjects(_ data: Data) -> [TaskCaptureProject] {
        guard let reply = try? JSONDecoder().decode(ProjectsReply.self, from: data) else { return [] }
        var projects: [TaskCaptureProject] = []
        func walk(_ folder: Folder) {
            for project in folder.projects where project.status == "active" || project.status == "onhold" {
                projects.append(
                    TaskCaptureProject(
                        name: project.text, path: project.address, folder: project.folder.last))
            }
            folder.subfolders.forEach(walk)
        }
        walk(reply.root)
        return projects
    }

    static func parseTags(_ data: Data) -> [String] {
        guard let reply = try? JSONDecoder().decode(TagsReply.self, from: data) else { return [] }
        var paths: [String] = []
        func walk(_ node: TagNode) {
            paths.append(node.path)
            node.children.forEach(walk)
        }
        reply.tags.forEach(walk)
        return paths
    }

    private struct WriteReply: Decodable {
        struct Item: Decodable {
            let reference: String?
            let address: String?
        }
        let item: Item?
    }

    private struct ErrorReply: Decodable {
        struct Failure: Decodable {
            let message: String
        }
        let error: Failure?
    }

    private struct ProjectsReply: Decodable {
        let root: Folder
    }

    private struct Folder: Decodable {
        struct Project: Decodable {
            let address: String
            let text: String
            let status: String
            let folder: [String]
        }
        let projects: [Project]
        let subfolders: [Folder]
    }

    private struct TagsReply: Decodable {
        let tags: [TagNode]
    }

    private struct TagNode: Decodable {
        let path: String
        let children: [TagNode]
    }
}
