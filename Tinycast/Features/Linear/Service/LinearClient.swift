import Foundation

/// Talks to Linear through the `linear` CLI, which holds the credentials so this app never does.
/// See docs/features/linear.md.
enum LinearClient {
    /// One round trip per workspace: the url key the web app uses, plus every saved view.
    static let query = """
        { organization { urlKey name } \
        customViews(first: 250) { nodes { id name slugId icon } } }
        """

    /// A GUI app inherits none of a login shell's PATH, so the binary is looked for by hand.
    private static let candidatePaths = [
        "/opt/homebrew/bin/linear", "/usr/local/bin/linear",
        NSHomeDirectory() + "/.local/bin/linear"
    ]

    private static let credentialsPath = NSHomeDirectory() + "/.config/linear/credentials.toml"

    /// Resolved once per launch: the path is stable, and the shell fallback costs a login shell.
    private static let executablePath: String? = {
        let manager = FileManager.default
        if let known = candidatePaths.first(where: manager.isExecutableFile(atPath:)) { return known }
        guard let resolved = run("/bin/zsh", ["-lc", "command -v linear"]),
            let path = String(data: resolved, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            manager.isExecutableFile(atPath: path)
        else { return nil }
        return path
    }()

    static var isAvailable: Bool { executablePath != nil }

    /// The workspaces the CLI is logged in to, read from its own config rather than by running it.
    /// The file names only slugs — tokens live in the keyring — so nothing secret is read here.
    nonisolated static func workspaces() -> [String] {
        guard let toml = try? String(contentsOfFile: credentialsPath, encoding: .utf8) else {
            return []
        }
        return LinearCredentials.parse(toml).workspaces
    }

    /// Every view across every logged-in workspace. **Networked**: each workspace is one
    /// authenticated request to Linear's API, so this is only ever called with consent in hand.
    nonisolated static func snapshot(includingBuiltIn: Bool) async -> [LinearView] {
        await Task.detached(priority: .userInitiated) {
            guard let linear = executablePath else { return [] }
            var views: [LinearView] = []
            for slug in workspaces() {
                guard let payload = run(linear, ["--workspace", slug, "api", query]) else { continue }
                let saved = LinearView.parse(payload, workspaceSlug: slug)
                // The url key comes back with the views, so built-ins can only be named once a
                // workspace has answered at least once.
                if includingBuiltIn, let urlKey = saved.first?.workspaceURLKey {
                    views += LinearView.builtIn(for: urlKey, workspaceSlug: slug)
                }
                views += saved
            }
            return views
        }.value
    }

    /// nil on a launch failure or a non-zero exit; stdout otherwise.
    nonisolated private static func run(_ executable: String, _ arguments: [String]) -> Data? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // Load-bearing: a CLI that stopped to prompt for a login would hang the refresh.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        return data
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
