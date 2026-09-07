import AppKit
import OSLog

/// Searches cached issue metadata immediately while owning cancellable refresh and live requests.
@MainActor
@Observable
final class LinearIssueIndexStore {
    static let refreshInterval: TimeInterval = 30 * 60

    enum SearchState { case idle, searching, ready, failed }

    private(set) var searchState = SearchState.idle
    private(set) var searchError: String?
    private(set) var searchTargets: [LinearTarget] = []
    private(set) var refreshError: String?
    private(set) var lastRefreshed: Date?
    private(set) var cachedIssueCount = 0

    typealias Search = @Sendable (
        LinearIssueLookup, [String], @escaping @Sendable (LinearClient.IssueReply) async -> Void
    ) async -> Void

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let configuration: @Sendable () -> LinearClient.IssueConfiguration
    @ObservationIgnored private let search: Search
    @ObservationIgnored private let recent: @Sendable (String) async -> LinearClient.IssueReply
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var index = LinearIssueIndex(configurationID: "")
    @ObservationIgnored private var slugs: [String] = []
    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var searchGeneration = 0
    @ObservationIgnored private var lookup: LinearIssueLookup?
    @ObservationIgnored private var replies: [String: LinearClient.IssueReply] = [:]
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NotificationToken?

    init(
        fileURL: URL,
        configuration: @escaping @Sendable () -> LinearClient.IssueConfiguration = LinearClient.issueConfiguration,
        search: @escaping Search = LinearClient.searchIssues,
        recent: @escaping @Sendable (String) async -> LinearClient.IssueReply = LinearClient.recentIssues,
        clock: @escaping @Sendable () -> Date = Date.init,
        debounce: Duration = .milliseconds(200)
    ) {
        self.fileURL = fileURL
        self.configuration = configuration
        self.search = search
        self.recent = recent
        self.clock = clock
        self.debounce = debounce
    }

    func start() {
        guard !isEnabled else { return }
        isEnabled = true
        generation += 1
        let current = configuration()
        slugs = current.workspaces
        index = LinearIssueIndex(configurationID: current.id)
        let generation = generation
        let fileURL = fileURL
        let configuration = configuration
        let persistence = persistenceTask
        lifecycleTask = Task { [weak self] in
            await persistence?.value
            let loaded = await Task.detached {
                let config = configuration()
                let cached = (try? Data(contentsOf: fileURL)).flatMap {
                    try? JSONDecoder().decode(LinearIssueIndex.self, from: $0)
                }
                return (config, cached)
            }.value
            guard let self, self.isEnabled, self.generation == generation, !Task.isCancelled else { return }
            guard configuration().id == loaded.0.id else { self.reconcileConfiguration(); return }
            self.slugs = loaded.0.workspaces
            self.index = loaded.1?.configurationID == loaded.0.id
                ? loaded.1! : LinearIssueIndex(configurationID: loaded.0.id)
            self.updateCacheStatus()
            self.publish()
            self.refreshIfStale()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
                guard !Task.isCancelled, self.isEnabled else { return }
                self.refreshIfStale()
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        wakeObserver = NotificationToken(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshIfStale() }
        }, center: center)
    }

    func stop(removeCache: Bool = false) {
        isEnabled = false
        generation += 1
        lifecycleTask?.cancel()
        lifecycleTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        wakeObserver = nil
        clearSearch()
        if removeCache {
            index = LinearIssueIndex(configurationID: "")
            slugs = []
            updateCacheStatus()
            persist(remove: true)
        }
    }

    func refreshIfStale(force: Bool = false) {
        guard isEnabled, refreshTask == nil else { return }
        reconcileConfiguration()
        let now = clock()
        let stale = slugs.filter {
            force || index.workspaces[$0].map { now.timeIntervalSince($0.refreshedAt) >= Self.refreshInterval } ?? true
        }
        guard !stale.isEmpty else { return }
        let generation = generation
        let recent = recent
        refreshError = nil
        refreshTask = Task { [weak self] in
            await withTaskGroup(of: LinearClient.IssueReply.self) { group in
                for slug in stale { group.addTask { await recent(slug) } }
                for await reply in group {
                    guard !Task.isCancelled, let self, self.isEnabled, self.generation == generation else {
                        group.cancelAll()
                        return
                    }
                    self.reconcileConfiguration()
                    guard self.generation == generation else { group.cancelAll(); return }
                    self.accept(reply, snapshot: true)
                }
            }
            guard let self, self.generation == generation else { return }
            self.refreshTask = nil
        }
    }

    func updateSearch(_ rawQuery: String) {
        guard isEnabled else { clearSearch(); return }
        reconcileConfiguration()
        guard let next = LinearIssueLookup.parse(rawQuery) else { clearSearch(); return }
        guard next != lookup || searchState == .failed else { return }
        searchTask?.cancel()
        searchGeneration += 1
        let searchGeneration = searchGeneration
        lookup = next
        replies = [:]
        searchError = nil
        searchState = .searching
        publish()
        let generation = generation
        let search = search
        let slugs = slugs
        searchTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await search(next, slugs) { [weak self] reply in
                await self?.acceptSearch(reply, lookup: next, generation: generation, searchGeneration: searchGeneration)
            }
            guard !Task.isCancelled, let self, self.generation == generation,
                self.searchGeneration == searchGeneration, self.lookup == next
            else { return }
            self.searchTask = nil
            self.searchState = self.replies.values.contains { $0.failure == nil } || !self.searchTargets.isEmpty
                ? .ready : .failed
        }
    }

    func clearSearch() {
        searchGeneration += 1
        searchTask?.cancel()
        searchTask = nil
        lookup = nil
        replies = [:]
        searchTargets = []
        searchError = nil
        searchState = .idle
    }

    func targets(for rawQuery: String) -> [LinearTarget] {
        guard isEnabled, lookup == LinearIssueLookup.parse(rawQuery) else { return [] }
        return searchTargets
    }

    func waitForPersistence() async { await persistenceTask?.value }

    private func reconcileConfiguration() {
        let current = configuration()
        guard current.id != index.configurationID else { return }
        generation += 1
        clearSearch()
        refreshTask?.cancel()
        refreshTask = nil
        slugs = current.workspaces
        index = LinearIssueIndex(configurationID: current.id)
        updateCacheStatus()
        persist(remove: true)
    }

    private func acceptSearch(
        _ reply: LinearClient.IssueReply, lookup: LinearIssueLookup, generation: Int, searchGeneration: Int
    ) {
        guard isEnabled, self.generation == generation, self.searchGeneration == searchGeneration,
            self.lookup == lookup
        else { return }
        reconcileConfiguration()
        guard self.generation == generation else { return }
        accept(reply, snapshot: false)
        replies[reply.workspace] = reply
        publish()
        searchError = replies.values.compactMap(\.failure).sorted().joined(separator: "; ")
        if searchError?.isEmpty == true { searchError = nil }
    }

    private func accept(_ reply: LinearClient.IssueReply, snapshot: Bool) {
        guard slugs.contains(reply.workspace) else { return }
        if reply.accessDenied {
            index.remove(workspace: reply.workspace)
            replies.removeValue(forKey: reply.workspace)
        } else if let accountID = reply.accountID, reply.failure == nil {
            if let previous = index.workspaces[reply.workspace], previous.accountID != accountID {
                index.remove(workspace: reply.workspace)
                replies.removeValue(forKey: reply.workspace)
            }
            if snapshot {
                index.replace(reply.targets, workspace: reply.workspace, accountID: accountID, now: clock())
            } else {
                index.merge(reply.targets, workspace: reply.workspace, accountID: accountID, now: clock())
            }
        }
        if snapshot, let failure = reply.failure { refreshError = failure }
        updateCacheStatus()
        publish()
        if reply.failure == nil || reply.accessDenied { persist() }
    }

    private func publish() {
        guard let lookup else { searchTargets = []; return }
        searchTargets = LinearIssueIndex.interleave(slugs.map { slug in
            let live = replies[slug]
            if live?.failure == nil, let live { return live.targets }
            return index.matches(lookup, workspaces: [slug], now: clock())
        })
    }

    private func updateCacheStatus() {
        cachedIssueCount = index.workspaces.values.reduce(0) { $0 + $1.targets.count }
        lastRefreshed = index.workspaces.values.map(\.refreshedAt).min()
    }

    private func persist(remove: Bool = false) {
        let previous = persistenceTask
        let index = index
        let fileURL = fileURL
        persistenceTask = Task.detached(priority: .utility) {
            await previous?.value
            do {
                if remove {
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try FileManager.default.removeItem(at: fileURL)
                    }
                } else {
                    let data = try JSONEncoder().encode(index)
                    try FileManager.default.createDirectory(
                        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: fileURL, options: .atomic)
                }
            } catch {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "Tinycast", category: "Linear")
                    .error("Linear issue cache write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
