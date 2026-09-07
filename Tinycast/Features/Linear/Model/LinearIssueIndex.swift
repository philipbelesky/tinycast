import Foundation

/// Bounded issue metadata, partitioned by authenticated workspace and searched without network IO.
struct LinearIssueIndex: Codable, Sendable {
    static let workspaceCapacity = 500
    static let maximumAge: TimeInterval = 24 * 3600

    struct Workspace: Codable, Sendable {
        var accountID: String
        var refreshedAt: Date
        var targets: [LinearTarget]
    }

    var configurationID: String
    private(set) var workspaces: [String: Workspace] = [:]

    mutating func replace(_ targets: [LinearTarget], workspace: String, accountID: String, now: Date) {
        workspaces[workspace] = Workspace(
            accountID: accountID, refreshedAt: now,
            targets: Self.unique(targets).prefix(Self.workspaceCapacity).map { $0 })
    }

    mutating func merge(_ targets: [LinearTarget], workspace: String, accountID: String, now: Date) {
        let previous = workspaces[workspace]
        let retained = previous?.accountID == accountID ? previous?.targets ?? [] : []
        replace(targets + retained, workspace: workspace, accountID: accountID, now: now)
        if previous?.accountID == accountID, let refreshedAt = previous?.refreshedAt {
            workspaces[workspace]?.refreshedAt = refreshedAt
        }
    }

    mutating func remove(workspace: String) { workspaces.removeValue(forKey: workspace) }

    func matches(_ lookup: LinearIssueLookup, workspaces slugs: [String], now: Date) -> [LinearTarget] {
        Self.interleave(slugs.map { slug in
            guard let workspace = workspaces[slug],
                now.timeIntervalSince(workspace.refreshedAt) < Self.maximumAge
            else { return [] }
            return workspace.targets.filter { Self.matches(lookup, target: $0) }.sorted {
                $0.issueDetails!.updatedAt > $1.issueDetails!.updatedAt
            }
        })
    }

    static func matches(_ lookup: LinearIssueLookup, target: LinearTarget) -> Bool {
        guard let details = target.issueDetails else { return false }
        switch lookup {
        case .number(let number):
            return details.identifier.split(separator: "-").last.flatMap { Int($0) } == number
        case .identifier(let key, let number):
            return details.identifier.caseInsensitiveCompare("\(key)-\(number)") == .orderedSame
        case .title(let title):
            return details.archivedAt == nil && target.name.localizedCaseInsensitiveContains(title)
        }
    }

    static func interleave(_ groups: [[LinearTarget]], limit: Int = 24) -> [LinearTarget] {
        var results: [LinearTarget] = []
        var seen: Set<String> = []
        for offset in 0..<(groups.map(\.count).max() ?? 0) {
            for group in groups where group.indices.contains(offset) {
                let target = group[offset]
                if seen.insert(target.id).inserted { results.append(target) }
                if results.count == limit { return results }
            }
        }
        return results
    }

    private static func unique(_ targets: [LinearTarget]) -> [LinearTarget] {
        var seen: Set<String> = []
        return targets.filter { target in
            guard let identifier = target.issueDetails?.identifier else { return false }
            return seen.insert(identifier).inserted
        }
    }
}
