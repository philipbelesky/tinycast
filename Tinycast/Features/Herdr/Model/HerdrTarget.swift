import Foundation

/// A tab in the running herdr session. See docs/features/herdr.md.
struct HerdrTarget: Identifiable, Hashable, Sendable {
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

    /// herdr's own id — `w2:tS`. Opaque: it contains the separator, so it is never split on `:`.
    let id: String
    let label: String
    /// The owning workspace's label, so a row reads `meta › mic-fix`.
    let workspaceLabel: String
    let status: AgentStatus
    let focused: Bool

    static let entryIDPrefix = "herdr:"

    var entryID: String { Self.entryIDPrefix + id }

    static func id(fromEntryID entryID: String) -> String? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return String(entryID.dropFirst(entryIDPrefix.count))
    }

    /// What the launcher row reads: a tab is only meaningful under its workspace.
    var displayName: String { workspaceLabel + " › " + label }

    /// Both payloads at once: a tab is only nameable once its workspace is known. A workspace earns
    /// no row of its own — a one-tab workspace is the same destination as that tab.
    /// Anything unparseable yields no targets — herdr being absent is not an error to report.
    static func parse(workspaces: Data, tabs: Data) -> [HerdrTarget] {
        var labels: [String: String] = [:]
        for row in rows(in: workspaces, key: "workspaces") {
            guard let id = row["workspace_id"] as? String,
                let label = (row["label"] as? String)?.nilIfBlank
            else { continue }
            labels[id] = label
        }

        var targets: [HerdrTarget] = []
        for row in rows(in: tabs, key: "tabs") {
            guard let id = row["tab_id"] as? String,
                let label = (row["label"] as? String)?.nilIfBlank,
                let workspaceID = row["workspace_id"] as? String,
                let workspaceLabel = labels[workspaceID]
            else { continue }
            targets.append(
                HerdrTarget(
                    id: id, label: label, workspaceLabel: workspaceLabel,
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
