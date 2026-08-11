# Linear views

`l payments` lists the views in every Linear workspace the `linear` CLI is logged in to; ↵ opens one
in the desktop app or the browser. Saved views come from Linear; the fixed pages every workspace has —
Inbox, My Issues, Projects, Initiatives, Settings — are added locally and can be switched off.

Issues are deliberately absent. This feature opens views and nothing else.

## Invariants

- **This is a networked feature, so it ships off behind a consent dialog** naming Linear, the cadence
  and what leaves the machine ([decisions.md](../decisions.md) entries 10, 11). The flag lives on
  `LinearViewStore`, **never** in `AppSettings`, so no settings import can grant it. `linearShowInLauncher`
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
- **`Model/LinearView.swift` and `Model/LinearCredentials.swift` are Foundation-only and pure**, so
  `linear-test` compiles the shipped parser, URL builder and icon map.
- **`linear api` answers HTTP 200 with an `errors` array**, so a failed query is not a thrown error.
  `LinearView.parse` returns an empty array for anything it cannot read, and the store treats an empty
  fetch as a failure to report rather than a list to publish — a bad refresh never blanks the cache.
- **A view id carries its workspace.** Two workspaces can hold a view of the same name — this machine
  has two called `Terminal` — so the id is `<urlKey>/<path>` and the row reads `philipb › Timekept`.

## Consent and cadence

`LinearViewStore` is shaped after `CurrencyRateStore` and keeps its three guards: a disabled feature
does not read its own cache at startup, does not publish rows, and does not fetch. Consent is
re-checked on the far side of the fetch too, so a toggle flipped off mid-refresh discards the result
rather than publishing something it no longer authorises.

The cadence is **at most every six hours, and only when the palette opens** — never on a keystroke and
never on a timer of its own. Each refresh is one request per workspace. The list is cached in
`AppPaths.caches()/linear-views.json` so a relaunch costs nothing, and turning the feature off deletes
that file.

## Where a view comes from

```
palette opens → PaletteCoordinator.onShow → LinearViewStore.refreshIfStale
                                                   ↓
              LinearClient.snapshot — one `linear --workspace <slug> api …` per workspace
                                                   ↓
        LinearView.parse → LinearViewStore.views (+ disk cache) → AppIndex.setLinearViews
                                                   ↓
                    ↵ → LinearCoordinator.open → NSWorkspace, app or browser
```

## Opening: two URLs for one view

A view is a path under its workspace, and only the prefix differs:

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

`Settings → Linear`: the consent switch, show-in-launcher, the destination picker, a built-in views
toggle, a Refresh Now button with the last-read time, and the [scope keyword](palette.md#choosing-your-own).

## Not here

Issues, projects and documents; creating or tracking anything; per-view hotkeys; and any use of the
API beyond listing view names. The CLI can do all of it — that is not a reason for a launcher to.
