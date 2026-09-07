import Foundation

@main
struct LinearIndexTest {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func target(_ identifier: String, title: String = "Search editor", archived: Bool = false,
                    workspace: String = "one") -> LinearTarget {
            LinearTarget(
                workspaceSlug: workspace, workspaceURLKey: workspace, name: title,
                path: "issue/" + identifier, kind: .issue, symbol: "circle",
                issueDetails: .init(identifier: identifier, stateName: "Todo", updatedAt: now,
                                    archivedAt: archived ? now : nil))
        }
        var index = LinearIssueIndex(configurationID: "config")
        index.replace([target("PHI-1"), target("PHI-2", archived: true)],
                      workspace: "one", accountID: "account", now: now)
        precondition(index.matches(.title("EDITOR"), workspaces: ["one"], now: now).count == 1)
        precondition(index.matches(.number(2), workspaces: ["one"], now: now).count == 1)
        index.merge([target("PHI-1", title: "Renamed")], workspace: "one", accountID: "account", now: now)
        precondition(index.matches(.title("Search"), workspaces: ["one"], now: now).isEmpty)
        precondition(index.matches(.title("Renamed"), workspaces: ["one"], now: now).count == 1)
        let restored = try JSONDecoder().decode(LinearIssueIndex.self, from: JSONEncoder().encode(index))
        precondition(restored.matches(.number(1), workspaces: ["one"], now: now).count == 1)
        index.replace([], workspace: "one", accountID: "account", now: now)
        precondition(index.matches(.number(1), workspaces: ["one"], now: now).isEmpty)
        index.replace([target("PHI-1")], workspace: "one", accountID: "account", now: now)
        index.merge([target("PHI-3")], workspace: "one", accountID: "other-account", now: now)
        precondition(index.matches(.number(1), workspaces: ["one"], now: now).isEmpty)
        precondition(index.matches(.number(3), workspaces: ["one"], now: now.addingTimeInterval(86400)).isEmpty)
        index.replace((1...600).map { target("PHI-\($0)") }, workspace: "one", accountID: "account", now: now)
        precondition(index.workspaces["one"]?.targets.count == 500)
        index.replace([target("PC-1", workspace: "two")], workspace: "two", accountID: "two", now: now)
        let results = index.matches(.title("Search"), workspaces: ["one", "two"], now: now)
        precondition(results.count == 24 && results[1].workspaceSlug == "two")
        index.remove(workspace: "one")
        precondition(index.matches(.number(1), workspaces: ["one"], now: now).isEmpty)
        print("Linear index matching, replacement, account isolation, expiry and bounds passed")
    }
}
