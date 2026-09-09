import AppKit
import SQLite3

/// Reads local Zed workspaces from Zed's own SQLite database. See docs/features/zed.md.
enum ZedProjectScanner {
    static let bundleID = "dev.zed.Zed"

    private static var databaseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Zed/db/0-stable/db.sqlite", directoryHint: .notDirectory)
    }

    @MainActor
    static var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Empty whenever Zed has never recorded a local workspace or its database is unavailable.
    nonisolated static func scan() async -> [ZedProject] {
        await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            let home = NSHomeDirectory()
            return ZedProject.parse(readCandidates(), homeDirectory: home) {
                manager.fileExists(atPath: $0)
            }
        }.value
    }

    /// Opens every workspace root in one request, preserving Zed's multi-root workspace.
    @MainActor
    static func open(_ project: ZedProject) async {
        guard let application = applicationURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.open(
            project.paths.map { URL(filePath: $0) }, withApplicationAt: application,
            configuration: configuration)
    }

    /// Zed owns the schema; a failed read is equivalent to no current project list.
    private static func readCandidates() -> [ZedProject.Candidate] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
            let database
        else { return [] }
        defer { sqlite3_close(database) }

        let query = """
            SELECT paths, paths_order, unixepoch(timestamp)
            FROM workspaces
            WHERE remote_connection_id IS NULL AND paths IS NOT NULL AND trim(paths) <> ''
            ORDER BY timestamp DESC
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement
        else { return [] }
        defer { sqlite3_finalize(statement) }

        var candidates: [ZedProject.Candidate] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let paths = sqlite3_column_text(statement, 0),
                let order = sqlite3_column_text(statement, 1)
            else { continue }
            candidates.append(
                ZedProject.Candidate(
                    paths: String(cString: paths), pathsOrder: String(cString: order),
                    lastOpened: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))))
        }
        return candidates
    }
}
