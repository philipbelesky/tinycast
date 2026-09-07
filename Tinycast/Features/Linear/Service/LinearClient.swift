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

    struct IssueConfiguration: Equatable, Sendable {
        var id: String
        var workspaces: [String]
    }

    nonisolated static func issueConfiguration() -> IssueConfiguration {
        let slugs = workspaces()
        let attributes = try? FileManager.default.attributesOfItem(atPath: credentialsPath)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return IssueConfiguration(id: "\(modified):" + slugs.joined(separator: ","), workspaces: slugs)
    }

    /// Publishes each workspace independently, so a slow response cannot hold up another's rows.
    nonisolated static func searchIssues(
        _ lookup: LinearIssueLookup, workspaces: [String],
        onReply: @escaping @Sendable (IssueReply) async -> Void
    ) async {
        guard let linear = executablePath else { return }
        await withTaskGroup(of: IssueReply.self) { group in
            for slug in workspaces {
                group.addTask {
                    await searchIssues(lookup, workspaceSlug: slug, executable: linear)
                }
            }
            for await reply in group {
                guard !Task.isCancelled else { group.cancelAll(); return }
                await onReply(reply)
            }
        }
    }

    /// A bounded full snapshot reconciles deletions and lost access without a second sync protocol.
    nonisolated static func recentIssues(workspace: String) async -> IssueReply {
        guard let linear = executablePath else {
            return IssueReply(workspace: workspace, failure: "the linear command line tool wasn’t found")
        }
        var targets: [LinearTarget] = []
        var cursor: String?
        var accountID: String?
        repeat {
            guard !Task.isCancelled else { return IssueReply(workspace: workspace, failure: "cancelled") }
            var variables: [String: Any] = ["first": min(100, LinearIssueIndex.workspaceCapacity - targets.count)]
            if let cursor { variables["after"] = cursor }
            guard let encoded = try? JSONSerialization.data(withJSONObject: variables),
                let json = String(data: encoded, encoding: .utf8)
            else { return IssueReply(workspace: workspace, failure: "could not encode issue page") }
            let result = await LinearProcessRunner.run(
                linear, ["--workspace", workspace, "api", recentIssueQuery, "--variables-json", json])
            let reply = issueReply(result, workspace: workspace)
            guard reply.failure == nil else { return reply }
            guard accountID == nil || accountID == reply.accountID else {
                return IssueReply(workspace: workspace, failure: "account changed during refresh", accessDenied: true)
            }
            accountID = reply.accountID
            targets += reply.targets
            guard let result,
                let root = try? JSONSerialization.jsonObject(with: result.output) as? [String: Any],
                let data = root["data"] as? [String: Any],
                let issues = data["issues"] as? [String: Any],
                let page = issues["pageInfo"] as? [String: Any],
                let hasNext = page["hasNextPage"] as? Bool
            else { return IssueReply(workspace: workspace, failure: "invalid issue pagination") }
            if !hasNext { break }
            guard let next = page["endCursor"] as? String, next != cursor, !reply.targets.isEmpty else {
                return IssueReply(workspace: workspace, failure: "issue pagination did not advance")
            }
            cursor = next
        } while targets.count < LinearIssueIndex.workspaceCapacity
        return IssueReply(workspace: workspace, targets: targets, accountID: accountID)
    }

    /// What a refresh found, and what it could not. A networked feature that fails silently is
    /// impossible to support, so every workspace that does not answer says why.
    struct Snapshot: Sendable {
        var targets: [LinearTarget] = []
        var failures: [String] = []
    }

    struct IssueReply: Sendable {
        var workspace: String
        var targets: [LinearTarget] = []
        var accountID: String?
        var failure: String?
        var accessDenied = false
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
        _ lookup: LinearIssueLookup, workspaceSlug: String, executable: String
    ) async -> IssueReply {
        guard let request = issueRequest(lookup, workspaceSlug: workspaceSlug) else {
            return IssueReply(workspace: workspaceSlug, failure: "the Linear query could not be encoded")
        }
        return issueReply(await LinearProcessRunner.run(executable, request), workspace: workspaceSlug)
    }

    nonisolated static func issueReply(
        _ result: LinearProcessRunner.Result?, workspace: String
    ) -> IssueReply {
        guard let result else {
            return IssueReply(workspace: workspace, failure: describe(workspace, nil))
        }
        if let error = firstError(in: result.output) {
            let denied = ["AUTHENTICATION_ERROR", "FORBIDDEN", "UNAUTHENTICATED"].contains {
                String(bytes: result.output, encoding: .utf8)?.contains($0) == true
            }
            return IssueReply(workspace: workspace, failure: error, accessDenied: denied)
        }
        guard result.status == 0, !result.signalled else {
            return IssueReply(workspace: workspace, failure: describe(workspace, result))
        }
        guard let root = try? JSONSerialization.jsonObject(with: result.output) as? [String: Any],
            let data = root["data"] as? [String: Any],
            let organization = data["organization"] as? [String: Any],
            let organizationID = organization["id"] as? String,
            let viewer = data["viewer"] as? [String: Any], let viewerID = viewer["id"] as? String,
            let issues = data["issues"] as? [String: Any], issues["nodes"] is [[String: Any]]
        else { return IssueReply(workspace: workspace, failure: "invalid issue response") }
        return IssueReply(
            workspace: workspace, targets: LinearTarget.parseIssues(result.output, workspaceSlug: workspace),
            accountID: organizationID + ":" + viewerID)
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

    private static let recentIssueQuery = """
        query RecentLinearIssues($first: Int!, $after: String) {
          organization { id urlKey }
          viewer { id }
          issues(first: $first, after: $after, includeArchived: false, orderBy: updatedAt) {
            nodes { identifier title url updatedAt archivedAt state { name } }
            pageInfo { hasNextPage endCursor }
          }
        }
        """

    private static let numberIssueQuery = """
        query LinearIssueNumber($number: Float!) {
          organization { id urlKey }
          viewer { id }
          issues(filter: { number: { eq: $number } }, first: 12, includeArchived: true,
                 orderBy: updatedAt) {
            nodes { identifier title url updatedAt archivedAt state { name } }
          }
        }
        """

    private static let identifierIssueQuery = """
        query LinearIssueIdentifier($teamKey: String!, $number: Float!) {
          organization { id urlKey }
          viewer { id }
          issues(filter: { number: { eq: $number }, team: { key: { eqIgnoreCase: $teamKey } } },
                 first: 12, includeArchived: true, orderBy: updatedAt) {
            nodes { identifier title url updatedAt archivedAt state { name } }
          }
        }
        """

    private static let titleIssueQuery = """
        query LinearIssueTitle($title: String!) {
          organization { id urlKey }
          viewer { id }
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
