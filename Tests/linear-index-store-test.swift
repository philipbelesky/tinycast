import Foundation
import Synchronization

@main
struct LinearIndexStoreTest {
    @MainActor static func main() async throws {
        let denied = LinearClient.issueReply(.init(
            output: Data(#"{"errors":[{"message":"Access revoked","extensions":{"code":"FORBIDDEN"}}]}"#.utf8),
            status: 1, signalled: false, errorText: ""), workspace: "fast")
        precondition(denied.accessDenied, "permission errors invalidate caches even with a nonzero CLI exit")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("issues.json")
        let now = Date()
        let config = Mutex(LinearClient.IssueConfiguration(id: "one", workspaces: ["fast", "slow"]))
        let requests = Mutex(0)
        let refreshRequests = Mutex(0)
        let testClock = Mutex(now)
        let slowGate = AsyncStream<Void>.makeStream()
        defer { slowGate.continuation.finish() }
        func waitUntil(_ condition: () -> Bool) async throws {
            for _ in 0..<1000 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(5))
            }
            preconditionFailure("Timed out waiting for issue search")
        }
        @Sendable func target(_ workspace: String, _ name: String = "Search cache") -> LinearTarget {
            LinearTarget(workspaceSlug: workspace, workspaceURLKey: workspace, name: name,
                         path: "issue/TEAM-1", kind: .issue, symbol: "circle",
                         issueDetails: .init(identifier: "TEAM-1", stateName: "Todo", updatedAt: now, archivedAt: nil))
        }
        var seed = LinearIssueIndex(configurationID: "one")
        seed.replace([target("fast")], workspace: "fast", accountID: "fast", now: now)
        seed.replace([target("slow")], workspace: "slow", accountID: "slow", now: now)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(seed).write(to: file)
        let store = LinearIssueIndexStore(
            fileURL: file, configuration: { config.withLock { $0 } },
            search: { _, _, reply in
                requests.withLock { $0 += 1 }
                await reply(.init(workspace: "fast", targets: [target("fast", "Search live")], accountID: "fast"))
                var iterator = slowGate.stream.makeAsyncIterator()
                _ = await iterator.next()
                await reply(.init(workspace: "slow", failure: "offline"))
            },
            recent: { workspace in
                refreshRequests.withLock { $0 += 1 }
                return .init(workspace: workspace, failure: "offline")
            },
            clock: { testClock.withLock { $0 } },
            debounce: .milliseconds(50))
        store.start()
        for _ in 0..<100 where store.cachedIssueCount != 2 { try await Task.sleep(for: .milliseconds(5)) }
        precondition(store.cachedIssueCount == 2, "disk cache loads without a refresh")
        precondition(refreshRequests.withLock { $0 } == 0, "launch does not refetch a fresh cache")
        testClock.withLock { $0 = now.addingTimeInterval(29 * 60) }
        store.refreshIfStale()
        precondition(refreshRequests.withLock { $0 } == 0, "palette opening preserves a fresh snapshot")
        testClock.withLock { $0 = now.addingTimeInterval(31 * 60) }
        store.refreshIfStale()
        try await waitUntil { store.refreshError != nil }
        precondition(store.cachedIssueCount == 2, "failed refresh retains the last good snapshot")
        store.updateSearch("search")
        precondition(store.targets(for: "search").count == 2, "local results are synchronous before debounce")
        precondition(requests.withLock { $0 } == 0)
        try await waitUntil { store.targets(for: "search").first?.name == "Search live" }
        precondition(store.targets(for: "search").first?.name == "Search live", "fast workspace publishes before slow")
        precondition(store.searchState == .searching)
        store.updateSearch("unrelated")
        precondition(store.targets(for: "unrelated").isEmpty, "previous query rows never flash for a new query")
        store.stop(removeCache: true)
        try await Task.sleep(for: .milliseconds(200))
        await store.waitForPersistence()
        precondition(!FileManager.default.fileExists(atPath: file.path), "disable wins over in-flight writes")
        precondition(store.searchTargets.isEmpty && store.cachedIssueCount == 0)
        store.start()
        try await Task.sleep(for: .milliseconds(30))
        store.updateSearch("search")
        try await waitUntil { !store.searchTargets.isEmpty }
        precondition(!store.searchTargets.isEmpty)
        config.withLock { $0 = .init(id: "two", workspaces: []) }
        store.updateSearch("search")
        precondition(store.searchTargets.isEmpty && store.cachedIssueCount == 0, "account config change clears results")
        store.stop(removeCache: true)
        await store.waitForPersistence()
        print("Linear disk restore, immediate matching, progressive replies, cancellation and account removal passed")
    }
}
