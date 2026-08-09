import Foundation

/// A workspace or tab in the running herdr session. See docs/features/herdr.md.
struct HerdrTarget: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case workspace
        case tab

        var label: String {
            switch self {
            case .workspace: return "Workspace"
            case .tab: return "Tab"
            }
        }
    }

    /// What an agent in the target is doing; `unknown` also absorbs a status herdr adds later.
    enum AgentStatus: String, Sendable {
        case idle
        case working
        case done
        case blocked
        case unknown

        init(raw: String?) {
            self = raw.flatMap(AgentStatus.init(rawValue:)) ?? .unknown
        }

        /// Only a status worth reading across the palette; `idle` is the boring default.
        var isNoteworthy: Bool { self == .working || self == .done || self == .blocked }
    }

    /// herdr's own id — `w2` for a workspace, `w2:tS` for a tab. Opaque: never split it.
    let id: String
    let kind: Kind
    let label: String
    /// The owning workspace's label, so a tab row can read `meta › mic-fix`. Nil for a workspace.
    let workspaceLabel: String?
    let status: AgentStatus
    let focused: Bool

    static let entryIDPrefix = "herdr:"

    var entryID: String { Self.entryIDPrefix + id }

    static func id(fromEntryID entryID: String) -> String? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return String(entryID.dropFirst(entryIDPrefix.count))
    }

    /// What the launcher row reads: a tab is only meaningful under its workspace.
    var displayName: String {
        guard let workspaceLabel else { return label }
        return workspaceLabel + " › " + label
    }

    /// Both payloads at once: a tab is only nameable once its workspace is known.
    /// Anything unparseable yields no targets — herdr being absent is not an error to report.
    static func parse(workspaces: Data, tabs: Data) -> [HerdrTarget] {
        let workspaceRows = rows(in: workspaces, key: "workspaces")
        var labels: [String: String] = [:]
        var tabCounts: [String: Int] = [:]
        var targets: [HerdrTarget] = []

        for row in workspaceRows {
            guard let id = row["workspace_id"] as? String,
                let label = (row["label"] as? String)?.nilIfBlank
            else { continue }
            labels[id] = label
            tabCounts[id] = row["tab_count"] as? Int ?? 0
            targets.append(
                HerdrTarget(
                    id: id, kind: .workspace, label: label, workspaceLabel: nil,
                    status: AgentStatus(raw: row["agent_status"] as? String),
                    focused: row["focused"] as? Bool ?? false))
        }

        for row in rows(in: tabs, key: "tabs") {
            guard let id = row["tab_id"] as? String,
                let label = (row["label"] as? String)?.nilIfBlank,
                let workspaceID = row["workspace_id"] as? String,
                let workspaceLabel = labels[workspaceID]
            else { continue }
            // A lone tab is the same destination as its workspace row, so it earns no row of its own.
            guard tabCounts[workspaceID, default: 0] > 1 else { continue }
            targets.append(
                HerdrTarget(
                    id: id, kind: .tab, label: label, workspaceLabel: workspaceLabel,
                    status: AgentStatus(raw: row["agent_status"] as? String),
                    focused: row["focused"] as? Bool ?? false))
        }
        return targets
    }

    /// The CLI wraps every reply in `{"id":…,"result":{…}}`; a bare payload is accepted too.
    private static func rows(in data: Data, key: String) -> [[String: Any]] {
        guard !data.isEmpty,
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        let payload = root["result"] as? [String: Any] ?? root
        return payload[key] as? [[String: Any]] ?? []
    }
}

extension String {
    fileprivate var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
