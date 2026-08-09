import Foundation

/// A folder or multi-root workspace VS Code has opened. See docs/features/vscode.md.
struct VSCodeProject: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case folder
        case workspace

        var label: String {
            switch self {
            case .folder: return "Project"
            case .workspace: return "Workspace"
            }
        }
    }

    /// One `workspaceStorage` directory: what it records, and when it was last written to.
    struct Candidate: Sendable {
        let payload: Data
        let modified: Date
    }

    /// The POSIX path, which is also what makes two windows on one folder the same project.
    var id: String { path }
    let kind: Kind
    let name: String
    let path: String
    let lastOpened: Date

    static let entryIDPrefix = "vscode:"
    static let workspaceSuffix = ".code-workspace"

    var entryID: String { Self.entryIDPrefix + path }

    static func path(fromEntryID entryID: String) -> String? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return String(entryID.dropFirst(entryIDPrefix.count))
    }

    /// The containing directory, `~`-abbreviated — the name alone can't tell two `src` folders apart.
    let displayPath: String

    /// Newest first, deduplicated by path. `exists` is injected because a project that has been
    /// deleted or unmounted is the common case, and the model may not touch the filesystem.
    static func parse(
        _ candidates: [Candidate], homeDirectory: String, exists: (String) -> Bool
    ) -> [VSCodeProject] {
        var newest: [String: VSCodeProject] = [:]
        for candidate in candidates {
            guard let project = project(from: candidate, homeDirectory: homeDirectory),
                exists(project.path)
            else { continue }
            if let seen = newest[project.path], seen.lastOpened >= project.lastOpened { continue }
            newest[project.path] = project
        }
        return newest.values.sorted { left, right in
            left.lastOpened == right.lastOpened
                ? left.path < right.path : left.lastOpened > right.lastOpened
        }
    }

    private static func project(from candidate: Candidate, homeDirectory: String) -> VSCodeProject? {
        guard !candidate.payload.isEmpty,
            let record = try? JSONSerialization.jsonObject(with: candidate.payload)
                as? [String: Any]
        else { return nil }

        let kind: Kind = record["workspace"] is String ? .workspace : .folder
        let key = kind == .workspace ? "workspace" : "folder"
        // A remote or virtual URI has no local path to hand to VS Code, so it is not a project here.
        guard let uri = record[key] as? String, let url = URL(string: uri), url.isFileURL
        else { return nil }

        let path = url.standardizedFileURL.path
        guard !path.isEmpty, path != "/" else { return nil }
        var name = (path as NSString).lastPathComponent
        if kind == .workspace, name.hasSuffix(workspaceSuffix) {
            name = String(name.dropLast(workspaceSuffix.count))
        }
        return VSCodeProject(
            kind: kind, name: name, path: path, lastOpened: candidate.modified,
            displayPath: abbreviating((path as NSString).deletingLastPathComponent,
                homeDirectory: homeDirectory))
    }

    /// `NSString.abbreviatingWithTildeInPath` reads the *running* user's home, so this takes one.
    private static func abbreviating(_ path: String, homeDirectory: String) -> String {
        guard path == homeDirectory || path.hasPrefix(homeDirectory + "/") else { return path }
        return "~" + path.dropFirst(homeDirectory.count)
    }
}
