import Foundation

/// Linear destinations and ticket lookup, with one switch guarding both network paths.
/// See docs/features/linear.md#the-switch-and-the-two-cadences.
@MainActor
@Observable
final class LinearStore {
    /// Views change rarely and each refresh costs one request per workspace, so this is generous.
    static let refreshInterval: TimeInterval = 6 * 3600
    private static let issueSearchDebounce: Duration = .milliseconds(200)

    enum IssueSearchState: Equatable {
        case idle
        case searching
        case ready
        case failed
    }

    /// On unless turned off. Not in `AppSettings`, so no import can flip it either way.
    private(set) var isEnabled: Bool

    /// Always empty while switched off, whatever is left in the cache.
    private(set) var targets: [LinearTarget] = []
    private(set) var lastRefreshed: Date?
    /// Why the last refresh came back short, verbatim from the CLI. Nil when it went fine.
    private(set) var lastError: String?
    private(set) var issueSearchState = IssueSearchState.idle
    private(set) var issueSearchError: String?
    private(set) var issueSearchTargets: [LinearTarget] = []

    /// Built-ins are routes rather than saved work, so they are opt-out on their own.
    var includesBuiltIn: Bool {
        didSet {
            guard includesBuiltIn != oldValue else { return }
            defaults.set(includesBuiltIn, forKey: Self.builtInKey)
            Task { await refresh(force: true) }
        }
    }

    @ObservationIgnored var onChange: (([LinearTarget]) -> Void)?

    private static let consentKey = "linearViewsEnabled"
    private static let builtInKey = "linearIncludesBuiltInViews"
    private let defaults = UserDefaults.standard
    private let fileURL: URL
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var issueSearchTask: Task<Void, Never>?
    @ObservationIgnored private var activeIssueLookup: LinearIssueLookup?
    @ObservationIgnored private var issueSearchCache = LinearIssueSearchCache()

    struct Cache: Codable, Sendable {
        var fetchedAt: Date
        var views: [CachedView]

        struct CachedView: Codable, Sendable {
            var workspaceSlug: String
            var workspaceURLKey: String
            var name: String
            var path: String
            var kind: String
            var symbol: String
        }
    }

    init() {
        // Absent reads as on: the feature ships enabled, so only an explicit false turns it off.
        isEnabled =
            defaults.object(forKey: Self.consentKey) == nil
            || defaults.bool(forKey: Self.consentKey)
        includesBuiltIn = defaults.object(forKey: Self.builtInKey) == nil
            || defaults.bool(forKey: Self.builtInKey)
        fileURL = AppPaths.caches().appendingPathComponent("linear-views.json")

        // Guard 1 — a disabled feature doesn't even read back what an earlier run left on disk.
        guard isEnabled, let data = try? Data(contentsOf: fileURL),
            let cache = try? JSONDecoder().decode(Cache.self, from: data)
        else { return }
        targets = cache.views.map(Self.target(from:))
        lastRefreshed = cache.fetchedAt
    }

    var isAvailable: Bool { LinearClient.isAvailable }
    var workspaceCount: Int { LinearClient.workspaces().count }

    /// Guard 2 — the palette's trigger, which must be safe to call unconditionally and often.
    /// Switched off, or inside the interval, this reaches no network at all.
    func refreshIfStale() async {
        guard isEnabled else { return }
        let age = lastRefreshed.map { Date().timeIntervalSince($0) } ?? .infinity
        guard age >= Self.refreshInterval else { return }
        await refresh(force: true)
    }

    /// "Refresh Now", and the only path that actually fetches.
    @discardableResult
    func refresh(force: Bool) async -> Bool {
        // Guard 3 — re-checked here because consent can be withdrawn while a refresh is in flight.
        guard isEnabled, !refreshing else { return false }
        refreshing = true
        defer { refreshing = false }
        let snapshot = await LinearClient.snapshot(includingBuiltIn: includesBuiltIn)
        // Re-checked on the far side of the await: the toggle may have gone off mid-fetch, and a
        // withdrawn consent must not be handed a result it never authorised.
        guard isEnabled else { return false }
        lastError = snapshot.failures.isEmpty ? nil : snapshot.failures.joined(separator: "; ")
        let fetched = snapshot.targets
        guard !fetched.isEmpty else { return false }
        lastRefreshed = Date()
        store(fetched)
        targets = fetched
        // Published unconditionally: `AppIndex` already ignores an identical slice, and skipping it
        // here left a restored-from-disk list unpublished whenever a refresh confirmed it.
        onChange?(fetched)
        return true
    }

    /// The toggle's only entry point; withdrawing also drops the list and deletes the cache.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.consentKey)
        guard !enabled else {
            onChange?(targets)
            Task { await refresh(force: true) }
            return
        }
        targets = []
        lastRefreshed = nil
        lastError = nil
        clearIssueSearch()
        issueSearchCache.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
        onChange?([])
    }

    /// Debounces a title, number or full-identifier lookup and forgets superseded visible results.
    func updateIssueSearch(_ rawQuery: String) {
        guard isEnabled, let lookup = LinearIssueLookup.parse(rawQuery) else {
            clearIssueSearch()
            return
        }
        if activeIssueLookup == lookup, issueSearchState != .failed { return }
        issueSearchTask?.cancel()
        activeIssueLookup = lookup
        issueSearchError = nil
        if let cached = issueSearchCache.targets(for: lookup, now: Date()) {
            issueSearchTargets = cached
            issueSearchState = .ready
            issueSearchTask = nil
            return
        }
        issueSearchTargets = []
        issueSearchState = .searching
        issueSearchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.issueSearchDebounce)
            guard !Task.isCancelled, let self, self.isEnabled,
                self.activeIssueLookup == lookup
            else { return }
            let snapshot = await LinearClient.searchIssues(lookup)
            guard !Task.isCancelled, self.isEnabled, self.activeIssueLookup == lookup else { return }
            self.issueSearchTask = nil
            self.issueSearchTargets = snapshot.targets
            self.issueSearchError =
                snapshot.failures.isEmpty
                ? nil : snapshot.failures.joined(separator: "; ")
            self.issueSearchState = snapshot.successfulWorkspaceCount == 0 ? .failed : .ready
            if snapshot.failures.isEmpty {
                self.issueSearchCache.store(snapshot.targets, for: lookup, fetchedAt: Date())
            }
        }
    }

    /// Cancels the visible ticket lookup while retaining the short in-memory repeat cache.
    func clearIssueSearch() {
        guard
            activeIssueLookup != nil || issueSearchTask != nil || !issueSearchTargets.isEmpty
                || issueSearchError != nil || issueSearchState != .idle
        else { return }
        issueSearchTask?.cancel()
        issueSearchTask = nil
        activeIssueLookup = nil
        issueSearchTargets = []
        issueSearchError = nil
        issueSearchState = .idle
    }

    func issueTargets(for rawQuery: String) -> [LinearTarget] {
        guard isEnabled, activeIssueLookup == LinearIssueLookup.parse(rawQuery),
            issueSearchState == .ready
        else { return [] }
        return issueSearchTargets
    }

    func isIssueTarget(id: String) -> Bool {
        issueSearchTargets.contains { $0.id == id && $0.kind == .issue }
    }

    func target(id: String) -> LinearTarget? {
        targets.first { $0.id == id } ?? issueSearchTargets.first { $0.id == id }
    }

    private func store(_ targets: [LinearTarget]) {
        let cache = Cache(
            fetchedAt: Date(),
            views: targets.map {
                Cache.CachedView(
                    workspaceSlug: $0.workspaceSlug, workspaceURLKey: $0.workspaceURLKey,
                    name: $0.name, path: $0.path, kind: $0.kind.rawValue, symbol: $0.symbol)
            })
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func target(from cached: Cache.CachedView) -> LinearTarget {
        LinearTarget(
            workspaceSlug: cached.workspaceSlug, workspaceURLKey: cached.workspaceURLKey,
            name: cached.name, path: cached.path,
            kind: LinearTarget.Kind(rawValue: cached.kind) ?? .saved, symbol: cached.symbol)
    }
}
