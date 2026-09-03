import Foundation

/// Talks to Linear through the `linear` CLI, which holds the credentials so this app never does.
/// See docs/features/linear.md.
enum LinearClient {
    /// One round trip per workspace: the url key the web app uses, then everything in its
    /// sidebar worth opening. Projects and initiatives carry their own url; saved views do not.
    static let query = """
        { organization { urlKey name } \
        customViews(first: 250) { nodes { id name slugId icon } } \
        projects(first: 250) { nodes { id name url } } \
        initiatives(first: 250) { nodes { id name url } } }
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
        guard
            let resolved = LinearProcessRunner.runSync(
                "/bin/zsh", ["-lc", "command -v linear"]),
            resolved.status == 0,
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
        guard let linear = executablePath else {
            return Snapshot(failures: ["the linear command line tool wasn’t found"])
        }
        let slugs = workspaces()
        guard !slugs.isEmpty else {
            return Snapshot(failures: ["no workspace is logged in — run `linear auth login`"])
        }
        var snapshot = Snapshot()
        for slug in slugs {
            let result = await LinearProcessRunner.run(linear, ["--workspace", slug, "api", query])
            guard let result, result.status == 0, !result.signalled else {
                snapshot.failures.append(describe(slug, result))
                continue
            }
            let saved = LinearTarget.parse(result.output, workspaceSlug: slug)
            // The url key comes back with the views, so built-ins can only be named once a
            // workspace has answered at least once.
            guard let urlKey = saved.first?.workspaceURLKey else {
                snapshot.failures.append(
                    "\(slug): \(result.output.count) bytes, no views — "
                        + (firstError(in: result.output) ?? "no error given"))
                continue
            }
            if includingBuiltIn {
                snapshot.targets += LinearTarget.builtIn(for: urlKey, workspaceSlug: slug)
            }
            snapshot.targets += saved
        }
        return snapshot
    }

    /// Searches tickets across every logged-in workspace without persisting the query or results.
    nonisolated static func searchIssues(_ lookup: LinearIssueLookup) async -> IssueSnapshot {
        guard let linear = executablePath else {
            return IssueSnapshot(failures: ["the linear command line tool wasn’t found"])
        }
        let slugs = workspaces()
        guard !slugs.isEmpty else {
            return IssueSnapshot(failures: ["no workspace is logged in — run `linear auth login`"])
        }
        let replies = await withTaskGroup(of: IssueReply.self) { group in
            for (index, slug) in slugs.enumerated() {
                group.addTask {
                    await searchIssues(
                        lookup, workspaceSlug: slug, workspaceIndex: index, executable: linear)
                }
            }
            var replies: [IssueReply] = []
            for await reply in group { replies.append(reply) }
            return replies.sorted { $0.workspaceIndex < $1.workspaceIndex }
        }
        var snapshot = IssueSnapshot()
        snapshot.successfulWorkspaceCount = replies.count { $0.failure == nil }
        snapshot.failures = replies.compactMap(\.failure)
        snapshot.targets = mergeIssueTargets(replies.map(\.targets))
        return snapshot
    }

    /// What a refresh found, and what it could not. A networked feature that fails silently is
    /// impossible to support, so every workspace that does not answer says why.
    struct Snapshot: Sendable {
        var targets: [LinearTarget] = []
        var failures: [String] = []
    }

    struct IssueSnapshot: Sendable {
        var targets: [LinearTarget] = []
        var failures: [String] = []
        var successfulWorkspaceCount = 0
    }

    private struct IssueReply: Sendable {
        let workspaceIndex: Int
        let targets: [LinearTarget]
        let failure: String?
    }

    nonisolated private static func describe(
        _ slug: String, _ result: LinearProcessRunner.Result?
    ) -> String {
        guard let result else { return "\(slug): the linear tool could not be launched" }
        let detail = result.errorText.split(separator: "\n").first.map(String.init) ?? "no output"
        if result.signalled { return "\(slug): the linear tool was killed — \(detail)" }
        return "\(slug): linear exited \(result.status) — \(detail)"
    }

    /// Linear answers a rejected query with HTTP 200 and an `errors` array, so a refusal is in the
    /// body rather than the exit status.
    nonisolated private static func firstError(in data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let errors = root["errors"] as? [[String: Any]],
            let message = errors.first?["message"] as? String
        else { return nil }
        return message
    }

    nonisolated private static func searchIssues(
        _ lookup: LinearIssueLookup, workspaceSlug: String, workspaceIndex: Int,
        executable: String
    ) async -> IssueReply {
        guard let request = issueRequest(lookup, workspaceSlug: workspaceSlug) else {
            return IssueReply(
                workspaceIndex: workspaceIndex, targets: [],
                failure: "\(workspaceSlug): the Linear query could not be encoded")
        }
        let result = await LinearProcessRunner.run(executable, request)
        guard let result, result.status == 0, !result.signalled else {
            return IssueReply(
                workspaceIndex: workspaceIndex, targets: [],
                failure: describe(workspaceSlug, result))
        }
        if let error = firstError(in: result.output) {
            return IssueReply(
                workspaceIndex: workspaceIndex, targets: [],
                failure: "\(workspaceSlug): \(error)")
        }
        return IssueReply(
            workspaceIndex: workspaceIndex,
            targets: LinearTarget.parseIssues(result.output, workspaceSlug: workspaceSlug),
            failure: nil)
    }

    nonisolated private static func issueRequest(
        _ lookup: LinearIssueLookup, workspaceSlug: String
    ) -> [String]? {
        let query: String
        let variables: [String: Any]
        switch lookup {
        case .number(let number):
            query = numberIssueQuery
            variables = ["number": number]
        case .identifier(let teamKey, let number):
            query = identifierIssueQuery
            variables = ["teamKey": teamKey, "number": number]
        case .title(let title):
            query = titleIssueQuery
            variables = ["title": title]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: variables),
            let json = String(data: data, encoding: .utf8)
        else { return nil }
        return ["--workspace", workspaceSlug, "api", query, "--variables-json", json]
    }

    /// Interleaves workspace order so the first configured one cannot fill the list.
    nonisolated private static func mergeIssueTargets(
        _ workspaceTargets: [[LinearTarget]]
    ) -> [LinearTarget] {
        var merged: [LinearTarget] = []
        var seen: Set<String> = []
        var offset = 0
        while merged.count < issueResultLimit {
            var appended = false
            for targets in workspaceTargets where targets.indices.contains(offset) {
                let target = targets[offset]
                if seen.insert(target.id).inserted {
                    merged.append(target)
                    if merged.count == issueResultLimit { return merged }
                }
                appended = true
            }
            guard appended else { break }
            offset += 1
        }
        return merged
    }

    private static let issueResultLimit = 24

    private static let numberIssueQuery = """
        query LinearIssueNumber($number: Float!) {
          organization { urlKey }
          issues(filter: { number: { eq: $number } }, first: 12, includeArchived: true,
                 orderBy: updatedAt) {
            nodes { identifier title url updatedAt archivedAt state { name } }
          }
        }
        """

    private static let identifierIssueQuery = """
        query LinearIssueIdentifier($teamKey: String!, $number: Float!) {
          organization { urlKey }
          issues(filter: { number: { eq: $number }, team: { key: { eqIgnoreCase: $teamKey } } },
                 first: 12, includeArchived: true, orderBy: updatedAt) {
            nodes { identifier title url updatedAt archivedAt state { name } }
          }
        }
        """

    private static let titleIssueQuery = """
        query LinearIssueTitle($title: String!) {
          organization { urlKey }
          issues(filter: { title: { containsIgnoreCase: $title } }, first: 12,
                 includeArchived: false, orderBy: updatedAt) {
            nodes { identifier title url updatedAt archivedAt state { name } }
          }
        }
        """
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
