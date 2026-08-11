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
        guard let resolved = run("/bin/zsh", ["-lc", "command -v linear"]), resolved.status == 0,
            let path = String(data: resolved.output, encoding: .utf8)?
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
    nonisolated static func snapshot(includingBuiltIn: Bool) async -> Snapshot {
        await Task.detached(priority: .userInitiated) {
            guard let linear = executablePath else {
                return Snapshot(failures: ["the linear command line tool wasn’t found"])
            }
            let slugs = workspaces()
            guard !slugs.isEmpty else {
                return Snapshot(failures: ["no workspace is logged in — run `linear auth login`"])
            }
            var snapshot = Snapshot()
            for slug in slugs {
                let result = run(linear, ["--workspace", slug, "api", query])
                guard let result, result.status == 0, !result.signalled else {
                    snapshot.failures.append(describe(slug, result))
                    continue
                }
                let saved = LinearView.parse(result.output, workspaceSlug: slug)
                // The url key comes back with the views, so built-ins can only be named once a
                // workspace has answered at least once.
                guard let urlKey = saved.first?.workspaceURLKey else {
                    snapshot.failures.append(
                        "\(slug): \(result.output.count) bytes, no views — "
                            + firstError(in: result.output))
                    continue
                }
                if includingBuiltIn {
                    snapshot.views += LinearView.builtIn(for: urlKey, workspaceSlug: slug)
                }
                snapshot.views += saved
            }
            return snapshot
        }.value
    }

    /// What a refresh found, and what it could not. A networked feature that fails silently is
    /// impossible to support, so every workspace that does not answer says why.
    struct Snapshot: Sendable {
        var views: [LinearView] = []
        var failures: [String] = []
    }

    private struct Result: Sendable {
        var output: Data
        var status: Int32
        var signalled: Bool
        var errorText: String
    }

    nonisolated private static func describe(_ slug: String, _ result: Result?) -> String {
        guard let result else { return "\(slug): the linear tool could not be launched" }
        let detail = result.errorText.split(separator: "\n").first.map(String.init) ?? "no output"
        if result.signalled { return "\(slug): the linear tool was killed — \(detail)" }
        return "\(slug): linear exited \(result.status) — \(detail)"
    }

    /// Linear answers a rejected query with HTTP 200 and an `errors` array, so a refusal is in the
    /// body rather than the exit status.
    nonisolated private static func firstError(in data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let errors = root["errors"] as? [[String: Any]],
            let message = errors.first?["message"] as? String
        else { return "no error given" }
        return message
    }

    /// nil only when the process could not be launched at all; the caller judges the rest.
    nonisolated private static func run(_ executable: String, _ arguments: [String]) -> Result? {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = SubprocessEnvironment.inherited
        // Load-bearing: a CLI that stopped to prompt for a login would hang the refresh.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(
            output: data, status: process.terminationStatus,
            signalled: process.terminationReason != .exit,
            errorText: String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
