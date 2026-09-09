import Foundation

/// A local Zed workspace, preserving every ordered root Zed reopens together.
struct ZedProject: Identifiable, Hashable, Sendable {
    /// One workspace record from Zed's database, with its local paths and last-open time.
    struct Candidate: Sendable {
        let paths: String
        let pathsOrder: String
        let lastOpened: Date
    }

    /// The entry id is the ordered roots so one workspace cannot collide with another.
    var id: String { entryID }
    let paths: [String]
    let name: String
    let lastOpened: Date
    let displayPaths: [String]

    static let entryIDPrefix = "zed:"
    private static let entryIDSeparator = "\u{1E}"

    var entryID: String { Self.entryIDPrefix + paths.joined(separator: Self.entryIDSeparator) }

    /// Newest first, dropping incomplete workspaces because Zed cannot reopen their original shape.
    static func parse(
        _ candidates: [Candidate], homeDirectory: String, exists: (String) -> Bool
    ) -> [ZedProject] {
        var newest: [String: ZedProject] = [:]
        for candidate in candidates {
            guard let project = project(from: candidate, homeDirectory: homeDirectory),
                project.paths.allSatisfy(exists)
            else { continue }
            if let seen = newest[project.entryID], seen.lastOpened >= project.lastOpened { continue }
            newest[project.entryID] = project
        }
        return newest.values.sorted { left, right in
            left.lastOpened == right.lastOpened
                ? left.entryID < right.entryID : left.lastOpened > right.lastOpened
        }
    }

    private static func project(from candidate: Candidate, homeDirectory: String) -> ZedProject? {
        let rawPaths = candidate.paths.split(separator: "\n", omittingEmptySubsequences: true).map(
            String.init)
        guard !rawPaths.isEmpty else { return nil }
        let orderedPaths = ordered(rawPaths, by: candidate.pathsOrder)
        guard orderedPaths.allSatisfy({ $0.hasPrefix("/") && $0 != "/" }) else { return nil }
        let paths = orderedPaths.map { path in
            URL(filePath: path).standardizedFileURL.path
        }
        let names = paths.map { ($0 as NSString).lastPathComponent }
        let name = names.count == 1 ? names[0] : "\(names[0]) + \(names.count - 1)"
        return ZedProject(
            paths: paths, name: name, lastOpened: candidate.lastOpened,
            displayPaths: paths.map {
                abbreviating(($0 as NSString).deletingLastPathComponent, homeDirectory: homeDirectory)
            })
    }

    /// Zed stores paths newline-separated and their workspace order as comma-separated indexes.
    private static func ordered(_ paths: [String], by rawOrder: String) -> [String] {
        let indexes = rawOrder.split(separator: ",").compactMap { Int($0) }
        guard Set(indexes).count == paths.count, Set(indexes) == Set(paths.indices) else { return paths }
        return indexes.map { paths[$0] }
    }

    /// `NSString.abbreviatingWithTildeInPath` reads the running user's home, so this takes one.
    private static func abbreviating(_ path: String, homeDirectory: String) -> String {
        guard path == homeDirectory || path.hasPrefix(homeDirectory + "/") else { return path }
        return "~" + path.dropFirst(homeDirectory.count)
    }
}
