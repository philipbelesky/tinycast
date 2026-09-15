import Foundation

/// A captured task as the TaskPaper OmniFocus reads, and the `omnifocus:///paste` URL that
/// carries it. See docs/features/task-capture.md#omnifocus.
enum TaskPaperFormatter {
    static func taskPaper(_ task: CapturedTask, calendar: Calendar) -> String {
        var line = "- " + task.title
        if let due = task.due { line += " @due(\(due.canonical(calendar: calendar)))" }
        if let deferDate = task.deferDate { line += " @defer(\(deferDate.canonical(calendar: calendar)))" }
        if task.flagged { line += " @flagged" }
        if !task.tags.isEmpty { line += " @tags(\(task.tags.joined(separator: ", ")))" }
        if let minutes = task.estimateMinutes { line += " @estimate(\(minutes)m)" }
        guard let note = task.note else { return line }
        // A note is the lines indented beneath the task, so a multi-line note stays one note.
        return line + "\n" + note.split(separator: "\n").map { "\t" + $0 }.joined(separator: "\n")
    }

    /// Nil for an untitled task: OmniFocus would paste an empty item and say nothing.
    static func omniFocusURL(_ task: CapturedTask, calendar: Calendar) -> URL? {
        guard task.isTitled else { return nil }
        let target = task.project.map { "/task/" + $0 } ?? "inbox"
        var components = URLComponents()
        components.scheme = "omnifocus"
        components.host = ""
        components.path = "/paste"
        components.percentEncodedQuery =
            "target=" + encode(target) + "&content=" + encode(taskPaper(task, calendar: calendar))
        return components.url
    }

    /// Everything but unreserved characters and `/`, which the target path keeps as a separator.
    private static func encode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
