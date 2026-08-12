# Linear views

`l payments` lists what is in the sidebar of every Linear workspace the `linear` CLI is logged in to;
↵ opens one in the desktop app or the browser. Four kinds of target: **saved views**, **projects** and
**initiatives**, all from Linear, plus the fixed pages every workspace has — Inbox, My Issues,
Projects, Initiatives, Settings — which are added locally and can be switched off.

Issues are deliberately absent. This feature opens destinations, not records.

## Invariants

- **This is a networked feature, so it ships off behind a consent dialog** naming Linear, the cadence
  and what leaves the machine ([AGENTS.md](../../AGENTS.md#non-negotiables) — consent is structural). The flag lives on
  `LinearStore`, **never** in `AppSettings`, so no settings import can grant it. `linearShowInLauncher`
  and `linearDestination` are ordinary settings and are backed up; neither can turn the network on.
- **Tinycast never sees a Linear token.** Every request goes through the `linear` CLI, which holds the
  credentials in the system keyring. The only file read directly is `~/.config/linear/credentials.toml`,
  and only for its `workspaces` list — `LinearCredentials.parse` reads exactly two keys by name, so a
  migrated plaintext token in that file is never touched, which `linear-test` pins.
- **A spawned tool gets `SubprocessEnvironment.inherited`, never the raw environment.** Xcode
  injects debugging dylibs into a Debug run and children inherit them, which breaks any tool that
  reads its own executable — `linear` is Deno-compiled and exits 1 with "Did not find magic
  bytes". The symptom is vicious: the feature works from a terminal and from a released build,
  and fails only while debugging. See [development.md](../development.md#spawning-a-tool).
- **`Model/LinearTarget.swift` and `Model/LinearCredentials.swift` are Foundation-only and pure**, so
  `linear-test` compiles the shipped parser, URL builder and icon map.
- **`linear api` answers HTTP 200 with an `errors` array**, so a failed query is not a thrown error.
  `LinearTarget.parse` returns an empty array for anything it cannot read, and the store treats an empty
  fetch as a failure to report rather than a list to publish — a bad refresh never blanks the cache.
- **A target id carries its workspace.** Two workspaces can hold a view of the same name — this
  machine has two called `Terminal` — so the id is `<urlKey>/<path>` and the row reads
  `philipb › Timekept`.
- **A project's path comes from Linear's own `url`, never from its id.** The url carries a name slug
  (`project/tvtunes-d4539ca85332`) that no client could reconstruct. A url that does not sit under
  this workspace is dropped rather than opened, so a redirect can never be followed blindly. Saved
  views are the opposite case: `CustomView` exposes no `url`, so their path *is* built, from `slugId`.

## Consent and cadence

`LinearStore` is shaped after `CurrencyRateStore` and keeps its three guards: a disabled feature
does not read its own cache at startup, does not publish rows, and does not fetch. Consent is
re-checked on the far side of the fetch too, so a toggle flipped off mid-refresh discards the result
rather than publishing something it no longer authorises.

The cadence is **at most every six hours, and only when the palette opens** — never on a keystroke and
never on a timer of its own. Each refresh is one request per workspace. The list is cached in
`AppPaths.caches()/linear-views.json` so a relaunch costs nothing, and turning the feature off deletes
that file.

## Where a view comes from

```
palette opens → PaletteCoordinator.onShow → LinearStore.refreshIfStale
                                                   ↓
              LinearClient.snapshot — one `linear --workspace <slug> api …` per workspace
                                                   ↓
        LinearTarget.parse → LinearStore.views (+ disk cache) → AppIndex.setLinearTargets
                                                   ↓
                    ↵ → LinearCoordinator.open → NSWorkspace, app or browser
```

## Opening: two URLs for one target

A target is a path under its workspace, and only the prefix differs:

```
browser   https://linear.app/philipb/view/c3f94e04a1e5
desktop   linear://linear.app/philipb/view/c3f94e04a1e5
```

**The desktop app declares no URL scheme.** `Linear.app`'s Info.plist has no `CFBundleURLTypes`, and
it is not a registered handler for `https://linear.app` either — opening the https URL with it
succeeds and does nothing. It registers `linear://` at *runtime*, the way Electron apps do, so
LaunchServices only knows the scheme once Linear has been launched at least once on that Mac. That is
why `LinearCoordinator` checks for a handler and falls back to the browser when there is none, and why
the pane says to choose Browser until Linear has run.

Linear answers the deep link without raising itself, so the reveal is a separate `activate()` — the
same focus-then-reveal split [herdr](herdr.md) needs.

## Settings

`Settings → Linear`: the consent switch, show-in-launcher, the destination picker, a built-in pages
toggle, a Refresh Now button with the last-read count and time, and the
[scope keyword](palette.md#choosing-your-own).

## Not here

Issues, documents and teams; creating or tracking anything; per-target hotkeys; and any use of the
API beyond listing names. The CLI can do all of it — that is not a reason for a launcher to.
