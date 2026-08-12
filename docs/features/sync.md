# Sync

iCloud settings sync: the settings backup payload mirrored through `NSUbiquitousKeyValueStore`, so
every Mac signed into the same iCloud account converges on one configuration. The feature lives in
`Features/Sync/`; the payload is `SettingsBackup`, wholesale ([backup.md](backup.md)).

## Invariants

- **The flag lives on `SettingsSyncStore`, never in `AppSettings`** — the shape every
  networked feature copies ([AGENTS.md](../../AGENTS.md#non-negotiables), and the section at the foot of this file). It is not an
  `AppSettingsKey`, so no backup file and no synced envelope can ever carry it.
- **An absent or unreadable remote never clears local state.** An empty KVS answer means "seed it";
  an undecodable envelope is left in place for the next writer that can read it. Neither applies.
- **The payload is `SettingsBackup`, unchanged.** Whatever the backup excludes — `snippetsEnabled`,
  every store-owned network switch — sync excludes structurally, and `sync-test` pins it.
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

Sync ships **on** ([FORK.md](../../FORK.md) divergence 15), so the usual path asks nothing: `start()`
arms the triggers and reconciles at startup. Turning it back on after a disable still runs the probes —
no iCloud account, or an unprovisioned build, each says so — and if iCloud already holds a differing
envelope, a sheet asks which side wins before any trigger is armed. **On a first launch that sheet
cannot fire**, because nothing calls `requestEnable()`: a fresh Mac with an existing envelope takes the
remote on the `.startup` trigger. That is what sync-by-default means, and it is the one place a
direction is chosen for the user rather than by them.

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
| `Service/SettingsSyncStore.swift` | The switch, triggers and reconcile — the effectful half |
| `Settings/SyncSettingsSection.swift` | The Backup pane section and the first-contact sheet |

## Why the backup payload through key-value storage

`SettingsSyncStore` mirrors `SettingsBackup` — wholesale, unchanged — through one
`NSUbiquitousKeyValueStore` key, as a compact envelope whose `writtenAt`/`writtenBy` are display
metadata only. Its flag is `settingsSyncEnabled` on the store. `SyncPlan.decide` picks a
direction from content hashes alone; when both sides changed, the trigger breaks the tie. After an
apply, the local bookkeeping hash is **re-gathered from live state**, never copied from the remote.

**Why:** KVS is zero-infrastructure and offline-tolerant, and the payload is a few KB against its
1 MB cap. Reusing `SettingsBackup` means the coverage harness and the `snippetsEnabled` exclusion
(entries 7, 9) guard the synced payload structurally rather than by convention. The tie-break rule is
"the winner is whoever the user touched last": on the local-change trigger the user just touched a
control *here*, and clobbering it would visibly flip their toggle back; at startup or on a push the
remote envelope is the freshest action anywhere. The re-gather closes a loop: apply skips conflicting
hotkeys, so a Mac that bookmarked the remote hash as its own state would see a phantom local change
and two Macs would rewrite iCloud at each other forever. The manual import's
executable-confirmation gate has no counterpart here: that gate defends against a foreign file, while
a synced envelope is self-authored under the same iCloud account, and a dialog per background apply
would be a storm. With the consent sheet gone, nothing announces up front that another Mac's shortcuts
and custom commands apply automatically — the HUD summary after each apply is the only runtime notice
left, which makes it load-bearing rather than a courtesy. The envelope is unversioned on purpose: every
payload field is optional, so a mixed-version pair of Macs degrades to a partial apply (entry 21's
"internal formats change freely" already covers the rest).

**What would change this:** a payload approaching the 1 MB cap (snippet bodies, clipboard history),
which is CloudKit or file-sync territory, or a real need for per-field merge, which hash-based
last-writer-wins cannot express.
