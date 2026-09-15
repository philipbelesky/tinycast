import Foundation

/// A project as a destination lists it: the name typed, the path that disambiguates it.
struct TaskCaptureProject: Equatable, Sendable {
    let name: String
    /// What the destination is handed — TextFlow's address, OmniFocus's name.
    let path: String
    let folder: String?
}

/// One row the list offers for a half-typed `@` or `#`.
struct TaskCaptureCompletion: Equatable, Sendable, Identifiable {
    let kind: TaskCaptureGrammar.CompletionContext.Kind
    /// What accepting it writes into the query.
    let value: String
    let detail: String?

    var id: String { "task-completion:\(kind):\(value)" }
}

/// What one destination offers to complete against. Pure, so the ranking is pinned by the harness.
struct TaskCaptureCatalog: Equatable, Sendable {
    var projects: [TaskCaptureProject] = []
    var tags: [String] = []

    static let empty = TaskCaptureCatalog()

    var isEmpty: Bool { projects.isEmpty && tags.isEmpty }

    /// Whether a typed project names one the destination has, by name or by path.
    func knows(project: String) -> Bool {
        let needle = project.lowercased()
        return projects.contains { $0.name.lowercased() == needle || $0.path.lowercased() == needle }
    }

    /// Prefix matches lead, substring matches follow, each in catalog order; the cap keeps the
    /// list a shortlist rather than the whole tree.
    func completions(
        for context: TaskCaptureGrammar.CompletionContext, limit: Int = 8
    ) -> [TaskCaptureCompletion] {
        let needle = context.prefix.lowercased()
        let candidates: [TaskCaptureCompletion]
        switch context.kind {
        case .project:
            let collisions = Dictionary(grouping: projects, by: { $0.name.lowercased() })
            candidates = projects.map { project in
                let ambiguous = (collisions[project.name.lowercased()]?.count ?? 0) > 1
                return TaskCaptureCompletion(
                    kind: .project, value: ambiguous ? project.path : project.name,
                    detail: project.folder)
            }
        case .tag:
            candidates = tags.map { TaskCaptureCompletion(kind: .tag, value: $0, detail: nil) }
        }
        guard !needle.isEmpty else { return Array(candidates.prefix(limit)) }
        let leading = candidates.filter { Self.components($0.value).contains { $0.hasPrefix(needle) } }
        let inner = candidates.filter { !leading.contains($0) && $0.value.lowercased().contains(needle) }
        return Array((leading + inner).prefix(limit))
    }

    /// `Home : Kitchen` matches on `kit` as well as `hom`; a path is typed by any of its parts.
    private static func components(_ value: String) -> [String] {
        value.lowercased().components(separatedBy: " : ").flatMap { $0.split(separator: "/").map(String.init) }
    }
}
