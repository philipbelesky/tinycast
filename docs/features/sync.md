# Sync

iCloud settings sync: the settings backup payload mirrored through `NSUbiquitousKeyValueStore`, so
every Mac signed into the same iCloud account converges on one configuration. The feature lives in
`Features/Sync/`; the payload is `SettingsBackup`, wholesale ([backup.md](backup.md)).

## Invariants

- **The consent flag lives on `SettingsSyncStore`, never in `AppSettings`** — the shape every
  networked feature copies ([decisions.md](../decisions.md) entries 8, 36). It is not an
  `AppSettingsKey`, so no backup file and no synced envelope can ever carry it.
- **An absent or unreadable remote never clears local state.** An empty KVS answer means "seed it";
  an undecodable envelope is left in place for the next writer that can read it. Neither applies.
- **The payload is `SettingsBackup`, unchanged.** Whatever the backup excludes — `snippetsEnabled`,
  every store-owned consent flag — sync excludes structurally, and `sync-test` pins it.
- **Apply bookkeeping re-gathers.** The local hash after an apply comes from live state, never from
  the remote envelope: apply skips conflicting hotkeys, so equating the two leaves two Macs
  rewriting iCloud at each other forever.
- **Disabling removes the iCloud copy but cannot reach other Macs.** Any still-enabled Mac re-seeds
  the envelope on its next change; truly clearing iCloud means disabling on every Mac, last one wins.

## Flow

One KVS key, `settingsSyncEnvelope`: compact, key-sorted JSON of `SyncEnvelope` — `writtenAt` and
`writtenBy` are display metadata only, never compared, so clock skew cannot decide anything.
`SyncPlan.decide` picks a direction from four content hashes; the trigger breaks a
both-sides-changed tie — a local edit is what the user just did *here*, so it wins on that trigger,
while startup and a push apply the remote. `sync-test` holds the full decision table.

Local changes funnel from two triggers — a `withObservationTracking` loop whose tracked read is the
gather itself, and `UserDefaults.didChangeNotification` for the two inputs observation cannot see
(`showInMenuBar`, hotkey records) — into one 2 s debounce. Every remote apply reports a HUD summary,
because a background change that quietly rewrites hotkeys is hostile ([backup.md](backup.md)).

Enabling walks the consent sheet: provider, cadence, the payload list, and the explicit sentence
that other Macs' shortcuts and custom commands apply automatically — the stated replacement for the
manual import's executable-confirmation gate ([decisions.md](../decisions.md) entry 36). If iCloud
already holds a differing envelope, a second sheet stage asks which side wins before any trigger is
armed.

## Channels

The KVS entitlement identifier is `$(TeamIdentifierPrefix)$(CFBundleIdentifier)`, so each channel
syncs in its own store and the dev-channel invariant holds with zero code. The entitlement lives in
`TinycastFork.entitlements` for every config, and it needs Apple-issued provisioning — which is the
reason the fork's channels are `com.belesky.tinycast` / `.dev` rather than upstream's ids:
`com.tinycast.app` is registered to a different Apple team and could never be provisioned (FORK.md
divergence 10). On any build signed without the entitlement — upstream's self-signed CI identity —
the enable-time `synchronize()` probe fails and the pane reports that sync isn't available for this
build, never a silent stall.

## Layout

| File | Role |
| --- | --- |
| `Model/SyncEnvelope.swift` | The KVS value: canonical codec and the content hash |
| `Model/SyncPlan.swift` | The pure decision table and the quota guard |
| `Service/SettingsSyncStore.swift` | Consent, triggers and reconcile — the effectful half |
| `Settings/SyncSettingsSection.swift` | The Backup pane section and both sheet stages |
