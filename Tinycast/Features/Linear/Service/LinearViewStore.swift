import Foundation

/// The consented Linear view list. Shaped after `CurrencyRateStore` — the same three guards, the
/// same consent-outside-`AppSettings` rule. See docs/features/linear.md#consent.
@MainActor
@Observable
final class LinearViewStore {
    static let provider = "Linear"
    static let providerURL = URL(string: "https://linear.app")!
    /// Views change rarely and each refresh costs one request per workspace, so this is generous.
    static let refreshInterval: TimeInterval = 6 * 3600

    /// Consent. Deliberately not in `AppSettings`, so no settings import can grant network access.
    private(set) var isEnabled: Bool

    /// Always empty without consent, whatever is left in the cache.
    private(set) var views: [LinearView] = []
    private(set) var lastRefreshed: Date?
    /// Set when a refresh reached the CLI but every workspace failed, so the pane can say so.
    private(set) var lastRefreshFailed = false

    /// Built-ins are routes rather than saved work, so they are opt-out on their own.
    var includesBuiltIn: Bool {
        didSet {
            guard includesBuiltIn != oldValue else { return }
            defaults.set(includesBuiltIn, forKey: Self.builtInKey)
            Task { await refresh(force: true) }
        }
    }

    @ObservationIgnored var onChange: (([LinearView]) -> Void)?

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
        // Absent reads as false, which is the only safe default for a network feature.
        isEnabled = defaults.bool(forKey: Self.consentKey)
        includesBuiltIn = defaults.object(forKey: Self.builtInKey) == nil
            || defaults.bool(forKey: Self.builtInKey)
        fileURL = AppPaths.caches().appendingPathComponent("linear-views.json")

        // Guard 1 — a disabled feature doesn't even read back what a previous consent left on disk.
        guard isEnabled, let data = try? Data(contentsOf: fileURL),
            let cache = try? JSONDecoder().decode(Cache.self, from: data)
        else { return }
        views = cache.views.map(Self.view(from:))
        lastRefreshed = cache.fetchedAt
    }

    var isAvailable: Bool { LinearClient.isAvailable }
    var workspaceCount: Int { LinearClient.workspaces().count }

    /// Guard 2 — the palette's trigger, which must be safe to call unconditionally and often.
    /// Without consent, or inside the interval, this reaches no network at all.
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
        let fetched = await LinearClient.snapshot(includingBuiltIn: includesBuiltIn)
        // Re-checked on the far side of the await: the toggle may have gone off mid-fetch, and a
        // withdrawn consent must not be handed a result it never authorised.
        guard isEnabled else { return false }
        lastRefreshFailed = fetched.isEmpty
        guard !fetched.isEmpty else { return false }
        lastRefreshed = Date()
        store(fetched)
        views = fetched
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
        views = []
        lastRefreshed = nil
        lastRefreshFailed = false
        try? FileManager.default.removeItem(at: fileURL)
        onChange?([])
    }

    func view(id: String) -> LinearView? { views.first { $0.id == id } }

    private func store(_ views: [LinearView]) {
        let cache = Cache(
            fetchedAt: Date(),
            views: views.map {
                Cache.CachedView(
                    workspaceSlug: $0.workspaceSlug, workspaceURLKey: $0.workspaceURLKey,
                    name: $0.name, path: $0.path, kind: $0.kind.rawValue, symbol: $0.symbol)
            })
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func view(from cached: Cache.CachedView) -> LinearView {
        LinearView(
            workspaceSlug: cached.workspaceSlug, workspaceURLKey: cached.workspaceURLKey,
            name: cached.name, path: cached.path,
            kind: LinearView.Kind(rawValue: cached.kind) ?? .saved, symbol: cached.symbol)
    }
}
