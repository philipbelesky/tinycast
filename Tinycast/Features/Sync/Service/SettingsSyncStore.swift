import Foundation

/// Mirrors the settings backup through iCloud key-value storage. See docs/features/sync.md.
@MainActor
@Observable
final class SettingsSyncStore {
    static let provider = "Apple iCloud"
    private static let payloadKey = "settingsSyncEnvelope"
    private static let consentKey = "settingsSyncEnabled"
    private static let localHashKey = "settingsSyncLocalHash"
    private static let remoteHashKey = "settingsSyncRemoteHash"
    private static let lastAtKey = "settingsSyncLastAt"
    private static let lastByKey = "settingsSyncLastBy"
    private static let debounce: Duration = .seconds(2)

    /// Consent. Deliberately not in `AppSettings`, so no import or synced payload can grant it.
    private(set) var isEnabled: Bool
    private(set) var lastSyncedAt: Date?
    private(set) var lastSyncedBy: String?

    enum EnableOutcome {
        case notSignedIn
        case unavailable
        case enabledFresh
        case remoteFound(SyncEnvelope)
    }

    private unowned let core: AppCore
    private let defaults = UserDefaults.standard
    private let kvs = NSUbiquitousKeyValueStore.default
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var kvsToken: NotificationToken?
    @ObservationIgnored private var defaultsToken: NotificationToken?
    @ObservationIgnored private var isApplyingRemote = false
    @ObservationIgnored private var warnedOversize = false
    @ObservationIgnored private var warnedUnreadable = false

    init(core: AppCore) {
        self.core = core
        // Absent reads as false, which is the only safe default for a feature that leaves the Mac.
        isEnabled = defaults.bool(forKey: Self.consentKey)
        if let at = defaults.object(forKey: Self.lastAtKey) as? Double {
            lastSyncedAt = Date(timeIntervalSince1970: at)
        }
        lastSyncedBy = defaults.string(forKey: Self.lastByKey)
    }

    /// No consent, no observers, so `AppCore.start()` can call this unconditionally.
    func start() {
        guard isEnabled else { return }
        startPipelines()
        Task { self.reconcile(trigger: .startup) }
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        kvsToken = nil
        defaultsToken = nil
    }

    /// The toggle's on-path. Returns without granting consent when a differing remote needs a choice.
    func requestEnable() -> EnableOutcome {
        guard FileManager.default.ubiquityIdentityToken != nil else { return .notSignedIn }
        // The probe: an unauthorized entitlement (an unprovisioned build) fails here, loudly.
        guard kvs.synchronize() else { return .unavailable }
        if case .envelope(let envelope, let remoteHash) = readRemote(),
            let localHash = try? SyncEnvelope.contentHash(of: SettingsBackup.gather(from: core)),
            remoteHash != localHash
        {
            return .remoteFound(envelope)
        }
        finishEnable(trigger: .localChange)
        return .enabledFresh
    }

    /// Finishes `.remoteFound`: the interactive choice is exactly a first-contact trigger.
    func resolveEnable(applyingRemote: Bool) {
        finishEnable(trigger: applyingRemote ? .startup : .localChange)
    }

    /// The toggle's off-path; also removes the iCloud copy, which a still-enabled Mac re-seeds.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if enabled {
            _ = requestEnable()
            return
        }
        isEnabled = false
        defaults.set(false, forKey: Self.consentKey)
        stop()
        kvs.removeObject(forKey: Self.payloadKey)
        kvs.synchronize()
        clearBookkeeping()
    }

    private func finishEnable(trigger: SyncTrigger) {
        isEnabled = true
        defaults.set(true, forKey: Self.consentKey)
        startPipelines()
        reconcile(trigger: trigger)
    }

    // MARK: - Triggers

    private func startPipelines() {
        // Observers land before `synchronize()`, per the documented KVS order.
        kvsToken = NotificationToken(
            NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: kvs, queue: .main
            ) { [weak self] note in
                let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
                let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
                Task { @MainActor in self?.handleExternalChange(reason: reason, keys: keys) }
            }, center: .default)
        // Catches the two payload inputs observation can't see: showInMenuBar and hotkey records.
        defaultsToken = NotificationToken(
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.noteLocalChange() }
            }, center: .default)
        kvs.synchronize()
        armObservation()
    }

    /// The gather itself is the tracked read, so every observable payload input registers.
    private func armObservation() {
        guard isEnabled else { return }
        withObservationTracking {
            _ = SettingsBackup.gather(from: core)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isEnabled else { return }
                self.armObservation()
                self.noteLocalChange()
            }
        }
    }

    private func noteLocalChange() {
        guard isEnabled, !isApplyingRemote else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.reconcile(trigger: .localChange)
        }
    }

    private func handleExternalChange(reason: Int?, keys: [String]?) {
        guard isEnabled else { return }
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange, NSUbiquitousKeyValueStoreInitialSyncChange:
            guard keys?.contains(Self.payloadKey) ?? true else { return }
            reconcile(trigger: .remoteNotification)
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            core.showMessage("iCloud storage for settings sync is full.", tone: .danger)
        case NSUbiquitousKeyValueStoreAccountChange:
            // The new account's data is not ours to keep or delete: pause, leave the key alone.
            isEnabled = false
            defaults.set(false, forKey: Self.consentKey)
            stop()
            clearBookkeeping()
            core.showMessage("iCloud account changed — settings sync turned off.", tone: .danger)
        default:
            break
        }
    }

    // MARK: - Reconcile

    private func reconcile(trigger: SyncTrigger) {
        guard isEnabled else { return }
        let gathered = SettingsBackup.gather(from: core)
        guard let localHash = try? SyncEnvelope.contentHash(of: gathered) else { return }

        let remoteHash: String?
        switch readRemote() {
        case .absent:
            remoteHash = nil
        case .undecodable:
            // Never overwrite what we cannot read; the next writer that can wins.
            if !warnedUnreadable {
                warnedUnreadable = true
                core.showMessage("iCloud sync data couldn't be read; sync is paused.", tone: .danger)
            }
            return
        case .envelope(_, let hash):
            remoteHash = hash
        }

        let decision = SyncPlan.decide(
            trigger: trigger,
            localHash: localHash,
            remoteHash: remoteHash,
            syncedLocalHash: defaults.string(forKey: Self.localHashKey),
            syncedRemoteHash: defaults.string(forKey: Self.remoteHashKey))
        switch decision {
        case .noop:
            // Both sides already agree; seeding makes the next decide precise after first contact.
            if remoteHash == localHash, defaults.string(forKey: Self.localHashKey) != localHash {
                setBookkeeping(local: localHash, remote: localHash, at: nil, by: nil)
            }
        case .writeLocal:
            writeLocal(gathered, hash: localHash)
        case .applyRemote:
            if case .envelope(let envelope, let hash) = readRemote() {
                applyRemote(envelope, remoteHash: hash)
            }
        }
    }

    private func writeLocal(_ backup: SettingsBackup, hash: String) {
        let envelope = SyncEnvelope(writtenAt: Date(), writtenBy: Self.deviceName, backup: backup)
        guard let data = try? envelope.encoded() else { return }
        guard SyncPlan.fitsQuota(byteCount: data.count) else {
            if !warnedOversize {
                warnedOversize = true
                core.showMessage("Settings are too large to sync to iCloud.", tone: .danger)
            }
            return
        }
        warnedOversize = false
        kvs.set(data, forKey: Self.payloadKey)
        kvs.synchronize()
        setBookkeeping(local: hash, remote: hash, at: Date(), by: Self.deviceName)
    }

    private func applyRemote(_ envelope: SyncEnvelope, remoteHash: String) {
        isApplyingRemote = true
        let summary = envelope.backup.apply(to: core)
        isApplyingRemote = false
        // Re-gather: apply skips conflicting hotkeys, so keeping the remote hash would ping-pong.
        let localHash = try? SyncEnvelope.contentHash(of: SettingsBackup.gather(from: core))
        setBookkeeping(
            local: localHash ?? remoteHash, remote: remoteHash,
            at: Date(), by: envelope.writtenBy)
        let applied = BackupActions.appliedText(summary) ?? "No changes."
        core.showMessage("Synced from \(envelope.writtenBy). \(applied)")
    }

    // MARK: - Remote payload

    private enum RemoteState {
        case absent
        case envelope(SyncEnvelope, hash: String)
        case undecodable
    }

    private func readRemote() -> RemoteState {
        guard let data = kvs.data(forKey: Self.payloadKey) else { return .absent }
        guard let envelope = try? SyncEnvelope(json: data),
            let hash = try? SyncEnvelope.contentHash(of: envelope.backup)
        else { return .undecodable }
        return .envelope(envelope, hash: hash)
    }

    // MARK: - Bookkeeping

    private func setBookkeeping(local: String, remote: String, at: Date?, by: String?) {
        defaults.set(local, forKey: Self.localHashKey)
        defaults.set(remote, forKey: Self.remoteHashKey)
        if let at {
            defaults.set(at.timeIntervalSince1970, forKey: Self.lastAtKey)
            lastSyncedAt = at
        }
        if let by {
            defaults.set(by, forKey: Self.lastByKey)
            lastSyncedBy = by
        }
    }

    private func clearBookkeeping() {
        defaults.removeObject(forKey: Self.localHashKey)
        defaults.removeObject(forKey: Self.remoteHashKey)
        defaults.removeObject(forKey: Self.lastAtKey)
        defaults.removeObject(forKey: Self.lastByKey)
        lastSyncedAt = nil
        lastSyncedBy = nil
    }

    private static var deviceName: String {
        Host.current().localizedName ?? "Mac"
    }
}
