import Foundation

/// The Linear view list. Shaped after `CurrencyRateStore` — the same three guards, the same
/// flag-outside-`AppSettings` rule. See docs/features/linear.md#the-switch-and-the-cadence.
@MainActor
@Observable
final class LinearStore {
    /// Views change rarely and each refresh costs one request per workspace, so this is generous.
    static let refreshInterval: TimeInterval = 6 * 3600

    /// On unless turned off. Not in `AppSettings`, so no import can flip it either way.
    private(set) var isEnabled: Bool

    /// Always empty while switched off, whatever is left in the cache.
    private(set) var targets: [LinearTarget] = []
    private(set) var lastRefreshed: Date?
    /// Why the last refresh came back short, verbatim from the CLI. Nil when it went fine.
    private(set) var lastError: String?

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
            Task { await refresh(force: true) }
            return
        }
        targets = []
        lastRefreshed = nil
        lastError = nil
        try? FileManager.default.removeItem(at: fileURL)
        onChange?([])
    }

    func target(id: String) -> LinearTarget? { targets.first { $0.id == id } }

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
