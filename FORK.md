# Fork

This checkout is a **fork of [`abue-ammar/tinycast`](https://github.com/abue-ammar/tinycast)**, which is
the `origin` remote and the mainline this file calls **upstream**. Fork work lives on branch `philip`;
`main` tracks `origin/main` untouched, so it is always a clean mirror of upstream.

It is a **personal** fork, and a permanent one. It ships to the author's own Macs and nowhere else, so
nothing here is waiting to become a pull request — the "Upstreamable?" column below is a note on how
foreign each change would look to mainline, not a plan. What *is* wanted is the traffic in the other
direction: upstream keeps moving, and this fork keeps absorbing it.

That is the one job this file exists for: **merging upstream without losing, re-litigating or
half-reverting the local changes.** Every divergence is listed below with what it touches, why it
exists, and what to do when upstream moves the same code. Anything not listed here is not intentional —
treat it as drift and take upstream's side.

Upstream deleted `docs/decisions.md` in #222 without re-homing it, and this fork took that deletion
(divergence 12). The reasoning that was fork-authored now lives with its subject —
[ui.md](docs/ui.md), [palette.md](docs/features/palette.md),
[web-search.md](docs/features/web-search.md), [sync.md](docs/features/sync.md) — and the invariants
themselves are in [AGENTS.md](AGENTS.md#non-negotiables). This file covers only where the fork
**departs** from upstream.

---

## The divergences, at a glance

| # | Divergence | Upstream conflict risk | Upstreamable? |
| --- | --- | --- | --- |
| 1 | [Apple Development signing](#1--apple-development-signing) | Low, but silently reverted by `xcodegen` | No — machine-specific |
| 2 | [Forced light appearance](#2--forced-light-appearance) | **High** — contradicts upstream decision 4 | No — it inverts a stated invariant |
| 3 | [`Theme.scale`](#3--themescale-and-derived-typography) | **High** — rewrites `Theme.swift` wholesale | Plausibly yes |
| 4 | [Scope keywords + web search](#4--scope-keywords-and-web-search) | Medium — hooks into `AppIndex`, `RootPaletteView`, `AppEntry.Kind` | Yes, as a feature |
| 5 | [herdr opener](#5--herdr-opener) | Medium — the same `AppEntry.Kind` surface as 4 | Unlikely — niche third-party tool |
| 6 | [VS Code project opener](#6--vs-code-project-opener) | Medium — the same `AppEntry.Kind` surface as 4 | Yes, as a feature |
| 7 | [Replace-on-import for quicklinks](#7--replace-on-import-for-quicklinks) | Low — one button, one method | Yes, small |
| 8 | [Linear view opener](#8--linear-view-opener) | Medium — the same `AppEntry.Kind` surface as 4 | Unlikely — niche, and networked |
| 9 | [Header-clearing edge dissolve](#9--header-clearing-edge-dissolve) | **High** — rewrites the top half of a file upstream calls off-limits | Yes — it fixes a real artifact |
| 10 | [iCloud settings sync](#10--icloud-settings-sync) | Medium — `project.yml` ids/entitlements, `AppCore`, a `SettingsBackup` split | No — needs provisioning upstream refuses |
| 11 | [SwiftUI previews](#11--swiftui-previews) | Low — 22 files, every edit an append at EOF | Yes, wholesale |
| 12 | [Re-homed decision reasoning](#12--re-homed-decision-reasoning) | Medium — fork prose inside sections upstream edits | No — upstream deleted the source |
| 13 | [No binary-size budget](#13--no-binary-size-budget) | Low — one deleted line in each of two docs | No — upstream ships to strangers |
| 14 | [Xcode only, no LSP scaffolding](#14--xcode-only-no-lsp-scaffolding) | Medium — five upstream files deleted | No — upstream supports both editors |

Keep each divergence as **its own commit**, never squashed together. Rebasing `philip` onto a new
`origin/main` then replays them one at a time, and a divergence that upstream has since made redundant
can be dropped whole rather than untangled.

---

## 1 — Apple Development signing

**Touches:** `project.yml` (three lines) and the `project.pbxproj` regenerated from it. Originally
commit `3ca4321 Signing fix/setup`, which patched the generated file directly.

Upstream signs with a stable **self-signed** identity, `Tinycast Self-Signed`, created by hand per
[docs/signing.md](docs/signing.md) — `CODE_SIGN_STYLE: Manual`, an empty `DEVELOPMENT_TEAM`, no Apple
account assumed. This fork signs with **automatic** signing against team `CNPCA4RAWZ` and the
`Apple Development` identity instead, because that account exists here and Xcode manages the certificate
without the one-time openssl ritual. Upstream's reason for the self-signed identity — a *stable* identity
across rebuilds, so macOS keeps the Accessibility grant — is satisfied either way.

The original patch lived in the *generated* `project.pbxproj`, which `xcodegen generate` silently
reverted — and since `Tinycast Self-Signed` was never created in this keychain, a regenerated project
could not sign at all. **The settings now live in `project.yml`**, so regeneration carries them:

```yaml
settings.base:
  DEVELOPMENT_TEAM: CNPCA4RAWZ
  CODE_SIGN_STYLE: Automatic
  CODE_SIGN_IDENTITY: "Apple Development"
```

That is the durable fix, at the price of a permanent three-line conflict with upstream in a file that
rarely changes. A git-ignored `.xcconfig` included from `project.yml` would avoid even that, at the cost
of a file upstream doesn't know about.

`Scripts/build-dmg.sh` followed: it used to hardcode `CODE_SIGN_STYLE=Manual`, the self-signed identity
and `--timestamp=none`, which meant it aborted on line 10 of a fork checkout because that identity was
never created here. It now leaves signing to `project.yml` and only preflights that the identity
resolves, defaulting to `Apple Development` and overridable with `TINYCAST_SIGN_IDENTITY`. The same
script gained a fork-local drop step — the finished DMG is copied to `TINYCAST_DMG_DROP`, defaulting to
`~/Library/Mobile Documents/com~apple~CloudDocs/Resources` — which is skipped when the directory is
absent, so it is inert upstream and on CI.

**On merge:** take upstream's `project.pbxproj` whole — hand-resolving it is never worth it — keep the
fork's three lines in `project.yml`, then run `xcodegen generate` and commit the result. If you ever
want upstream's self-signed identity back, create it first ([docs/signing.md](docs/signing.md)); the
build fails outright when `CODE_SIGN_IDENTITY` names an identity the keychain doesn't hold.

---

## 2 — Forced light appearance

**Touches:** `AppCore.swift`, `Theme.swift` (the `Colors` block), `IconCache.swift`, nine view and window
files, and five docs.

Upstream is locked to `.darkAqua` and says so as a non-negotiable: decision 4 calls light mode "not a
switch, it is a second design", and [ui.md](docs/ui.md) builds a whole white-alpha ramp on top of that
assumption. **This fork inverts it**: `NSApp.appearance = NSAppearance(named: .aqua)`, and the ramp is
black-alpha over a bright frosted surface. The rest of this section is the second design that decision 4
said would be required — so expect to re-do it, not merely re-apply it, whenever upstream restyles.

The fork-local docs have been rewritten to describe light as the invariant, which means **AGENTS.md,
docs/ui.md, docs/architecture.md and docs/features/launcher.md all conflict with any
upstream edit to the same passages.** When they do, take upstream's *substance* and re-invert only the
appearance claim; do not take upstream's paragraph wholesale, or the docs will start lying about the
code again.

### What actually changed

| Layer | Change |
| --- | --- |
| Appearance | `AppCore.start()` sets `.aqua`, not `.darkAqua` |
| Panel surface | `panelDimming` (a `CGFloat` composed as `Color.black.opacity(…)` at four call sites) became **`panelTint`**, a `Color` — white 0.55 |
| Marking colors | `selection` `rowHover` `menuHover` `separator` `controlSurface` `border` `textSecondary` `textTertiary` `cardStroke` all flipped white-alpha → black-alpha |
| Lifting colors | `cardFill` (white 0.45) and `glassFrost` (white 0.30) stayed white — they lift a surface off the material rather than mark something on it |
| Rasterized art | `IconCache.symbolIcon` draws its tile and glyph in black alphas; it bakes bitmaps, so it cannot inherit the appearance |
| Caret & tint | `PalettePanel` insertion point → `.labelColor`; the search field's `.tint(.white)` → `.tint(.primary)` |
| Ad-hoc fills | Icon placeholders (`AppIconView`, `UninstallView`), the onboarding gradient, the volume slider track/knob, the volume HUD bar, the About icon shadow |

Deliberately **untouched**: `EdgeDissolve.swift` uses black only as a gradient *mask*, where the color is
irrelevant, and `ThinScrollbar.swift` already draws in `Color.primary`, which follows the appearance on
its own. Both are off-limits per AGENTS.md, and neither needed an exception.

### The rule that keeps this maintainable

A merged-in view that hardcodes `Color.white.opacity(…)` will be invisible on this surface. After every
upstream merge, run:

```sh
grep -rn "Color\.white\|\.white\.opacity\|NSColor\.white\|darkAqua" --include="*.swift" Tinycast/ \
  | grep -v "EmojiData.generated\|CurrencyData.generated"
```

Every hit is a *lifting* color (`panelTint`, `cardFill`, `glassFrost`, the onboarding gradient), the
white glyph reversed out of a category tile (`IconCache`, divergence 4 — the tile behind it is
saturated, so white is the legible ink there), or a bug this fork has to fix. There is no hit that is
fine by default.

### Not verified visually by an agent

`screencapture` and `osascript` keystrokes are both blocked by TCC from a shell here — ui.md's "Restyle
from screenshots" note says as much — so the alpha values are reasoned, not eyeballed. `panelTint`, `glassFrost`, `cardFill` and
`selection` are the four numbers to adjust if the surface reads wrong; they are all in `Theme.Colors`.

---

## 3 — `Theme.scale` and derived typography

**Touches:** `Theme.swift` (rewritten), `IconCache.swift`, `RootPaletteView.swift`, eight further view
files and `docs/ui.md`.

One compile-time constant multiplies every length and font size in `Theme`, so the whole UI — panel
frame, row icons, keycaps, glyph point sizes, rasterized bitmaps — grows together from a one-line edit.
`Theme.Typography` consequently stopped naming semantic text styles and now derives point sizes from
`NSFont.preferredFont(forTextStyle:)` times the scale, because `Font.body` cannot be scaled and a point
size can. Full reasoning, including the two tokens that are not pixel-identical at `scale 1.0`, is in
[ui.md](docs/ui.md#why-a-constant-and-why-derived-point-sizes), which is fork-local prose inside a
section upstream also edits.

This one is a **conflict magnet**: it rewrites most of `Theme.swift` and de-magic-numbers views across
the app, which is exactly the code upstream also churns. It is also the divergence most worth offering
upstream, since it is a pure improvement to a file upstream already treats as the single token source.
Until then, expect `Theme.swift` merges to be resolved by hand, structurally: take upstream's *new
tokens*, keep the fork's `* scale` multiplication and derived `Typography`.

The corollary the fork now depends on: **a magic number in a view is a real defect, not a style nit** — a
literal `8` no longer tracks the rest of the UI. Upstream code merged in will contain magic numbers.
Converting them to tokens is part of finishing the merge, not a follow-up.

---

## 4 — Scope keywords and web search

**Touches:** three new pure models (`Launcher/Model/QueryScope.swift`, `Launcher/Model/ScopeKeywords.swift`,
`WebSearch/Model/WebSearchEngine.swift`)
with a harness each, `Launcher/Service/ScopeCatalog.swift`, `WebSearch/Service/`, `WebSearch/Settings/`,
`Palette/ScopeChip.swift` — plus hooks in `AppIndex`, `LauncherScreen`, `LauncherList`,
`LauncherCoordinator`, `RootPaletteView`, `PaletteWindowController`, `PaletteState`, `AppCore`,
`SettingsTab`, and the settings/backup registries.

A keyword plus a space narrows the root search (`q github`) or routes the rest of the query to a search
engine (`g swift actors`). Upstream has neither; both are documented as if they were native, in
[palette.md](docs/features/palette.md#scope-keywords) and [web-search.md](docs/features/web-search.md),
the latter carrying the adopt-on-transition rule.

Keywords are **user-editable**, which is the part with the widest settings surface: every scope-owning
pane carries a `ScopeKeywordSection`, so nine upstream panes gain a section they did not have, and
`AppSettings.scopeKeywords` is a dictionary key upstream has no notion of. The panes for the fork's own
features — Web Search, herdr, VS Code — also sit in the **Features** sidebar group rather than
Launcher, so `SettingsSection.tabs` conflicts with any upstream reshuffle of the sidebar.

Web search also grew **query suggestions** (`WebSearch/Model/SearchSuggestions.swift`,
`Service/SearchSuggestionStore.swift`), which is the fork's third networked feature and the only one
anywhere that sends what the user *types*. It ships off behind its own dialog, keeps no cache and no
cookies, and its flag is not in `AppSettings`; the reasoning is at the foot of
[web-search.md](docs/features/web-search.md). The hooks
are a `.suggestion` case in both row models and a `refreshSuggestions()` call in `RootPaletteView`'s
query and scope `onChange`; `LauncherList.WebSearchPrompt` gained an `id` so the selection can move off
the search row onto a suggestion.

Every scope also **publishes a row of its own** (`AppEntry.Kind.scope`, `AppIndex.setScopes`), leading
the empty query and wearing a coloured category tile — `ScopeTint`, `Theme.Colors.tile(_:)` and the
tinted branch of `IconCache.symbolIcon(named:tint:)`, all documented in
[ui.md](docs/ui.md#category-tiles). That tile is the only white ink on this surface that divergence 2
does not treat as a bug.

This is the divergence most worth offering upstream — it is additive, it invents no new architecture,
and the grammar is pure and tested. Until then, the conflict surface is what it touches: `AppIndex`
gained a `scope:`/`kinds:` parameter on `orderedResults` **and a `scopeID` in `ResultsKey`** (drop that
and a scoped query silently serves the previous unscoped results); `LauncherScreen.Row` and
`LauncherList.Row` each gained a `webSearch` case; and `AppEntry.Kind` gained `.webSearch`, which forces
a `KindDescriptor`, a `symbolIconName` arm, a `hotKeyAction` arm, a slice in `publishEntries()`, an entry
in `LauncherList`'s kind order, a `SettingsTab` case **and** a place in `SettingsSection.tabs` —
`settings-history-test` fails if the last one is forgotten.

**On merge:** if upstream restructures `AppEntry.Kind` or the launcher's row model, re-apply the case
and let the compiler find the rest; every one of those sites is an exhaustive switch except the two
list orderings and the sidebar group.

---

## 5 — herdr opener

**Touches:** a new `Features/Herdr/` (two pure models with a harness, a client, a store, a coordinator,
a settings pane), a new `Platform/ProcessTable.swift`, plus the same hook set as divergence 4 —
`AppEntry.Kind.herdrTarget`, an `AppIndex` slice, a `LauncherCoordinator` branch, `ScopeCatalog`'s `h`,
`PaletteCoordinator.onShow`, `AppCore` wiring, `SettingsTab` and the settings/backup registries.

`h payments` lists the running [herdr](docs/features/herdr.md) session's workspaces and tabs; ↵ focuses
one and raises the terminal hosting it. Upstream has no notion of a third-party tool's live state in the
launcher, and this is the fork's least upstreamable feature: it is useful to exactly the people who run
herdr. **It is also the cleanest thing here to delete** — the whole feature is one folder plus a handful
of enum arms the compiler will point at.

Two things not to lose in a merge. `PaletteCoordinator.onShow` is a fork-local hook on an upstream type,
and dropping it doesn't break the build — it just leaves the launcher listing a stale session forever.
And **`ProcessTable` uses `sysctl(KERN_PROC_ALL)` deliberately**: `libproc` looks tidier and returns
EPERM for processes the caller doesn't own, which silently breaks host detection at root-owned `login`,
two hops short of the terminal app. That failure is invisible — focus still moves, the window just never
comes forward.

**On merge:** the same rule as divergence 4 — re-apply the `Kind` case and follow the compiler. If
upstream ever grows its own "live external source" slice, this should be rebuilt on it rather than kept.

---

## 6 — VS Code project opener

**Touches:** a new `Features/VSCode/` (one pure model with a harness, a scanner, a store, a
coordinator, a settings pane), plus the same hook set as divergences 4 and 5 —
`AppEntry.Kind.vsCodeProject`, an `AppIndex` slice, a `LauncherCoordinator` branch, `ScopeCatalog`'s
`p`, `PaletteCoordinator.onShow`, `AppCore` wiring, `SettingsTab` and the settings/backup registries.

`p payments` lists what [VS Code](docs/features/vscode.md) has opened, most recent first; ↵ opens one.
Unlike divergence 5 this is broadly useful and worth offering upstream — it is additive, pure where it
matters, and depends on nothing but a well-known path.

The thing to preserve is **why it reads `workspaceStorage` rather than `state.vscdb`**: the key every
comparable tool uses, `history.recentlyOpenedPathsList`, holds `{"entries":[]}` on a current VS Code,
so the obvious implementation silently lists nothing. A future merge that "fixes" the source to the
canonical one is a regression that looks like a cleanup. `vscode.md` says so at the source.

**On merge:** same rule as divergences 4 and 5. Note that this kind is the first synthetic entry with
`canRevealInFinder: true` and `isSymbolIcon: false`, so upstream code assuming "synthetic implies
symbol icon" will be wrong.

---

## 7 — Replace-on-import for quicklinks

**Touches:** `Quicklinks/UI/QuicklinkCoordinator.swift` (one parameter, one private method),
`Quicklinks/Settings/QuicklinksSettingsView.swift` (one button), three assertions in
`Tests/quicklink-test.swift`, and `docs/features/quicklinks.md`.

Upstream's import only ever *adds*, skipping what you already have. This fork adds a **Replace** button
that makes the file the whole library, for the case this fork actually has: quicklinks generated from
a bookmarks file, re-exported whenever the bookmarks change, where merging leaves renamed and deleted
entries behind forever.

It adds no new machinery — the wipe reuses `replaceQuicklinks`, which upstream already has for backup
restore and which unwinds every reference, and the file is prepared with
`QuicklinkArchive.merge(incoming, into: [])`. That empty-library merge is the whole trick and the
harness now pins it: a change that made `merge` behave differently against an empty library would
quietly turn a replace into a partial wipe.

**On merge:** low risk. If upstream reworks the import flow, re-apply the `replacingExisting`
parameter and keep the ordering — decode, then confirm, then delete — since that is what stops an
unreadable file from costing a library.

---

## 8 — Linear view opener

**Touches:** a new `Features/Linear/` (two pure models with a harness, a client, a consented store, a
coordinator, a settings pane), plus the same hook set as divergences 5 and 6 —
`AppEntry.Kind.linearView`, an `AppIndex` slice, a `LauncherCoordinator` branch, `ScopeCatalog`'s `l`,
`PaletteCoordinator.onShow`, `AppCore` wiring, `SettingsTab` and the settings/backup registries.

`l payments` lists every workspace's Linear sidebar — saved views, projects, initiatives; ↵ opens
one. It is
the **second networked feature** in the app and the first the fork added, so it copies
`CurrencyRateStore` rather than inventing a second consent shape: flag on the store, three guards,
re-checked across the await, cache deleted on withdrawal.

Two things not to lose. The consent flag must stay out of `AppSettings` — `settings-backup-test` will
not catch it moving, because a new key there is legal; only the invariant forbids it. And the desktop
app's link handling is a genuine trap: `Linear.app` declares no URL scheme and does not claim
`https://linear.app`, so the https URL opens it and does nothing. `linear://` works, but only because
Electron registers it at runtime — a Mac where Linear has never launched has no handler, which is what
the browser fallback in `LinearCoordinator` is for.

A third thing, learned the hard way and now shared: `Platform/SubprocessEnvironment.swift`. Xcode's
Debug-run dylib injection is inherited by every child process and breaks any tool that reads its own
executable, so both this and `HerdrClient` strip `DYLD_*` before spawning. Deleting that line
reintroduces a bug that only appears when the app is launched from Xcode.

**On merge:** same rule as divergences 5 and 6. If upstream grows its own consent helper, this should
adopt it rather than keep a parallel one.

---

## 9 — Header-clearing edge dissolve

**Touches:** the top half of `DesignSystem/Scrolling/EdgeDissolve.swift` — `topFade`/`topMinAlpha`
became `topBand`/`topOvershoot`, and the two top gradient stops moved. The bottom half is untouched.

Upstream fades the top band to a floor of **0.15 at mid-band** and only reaches full opacity 32pt
*below* the header, which leaves scrolled content 45–95% opaque at the search field's own edge and
dims rows that are fully visible. That reads as the search bar sitting on top of the list — worst in
the emoji grid, where a row is 70pt of saturated colour. Here the top band clears to **0** at the
header's bottom edge, over a 20pt overshoot: opaque at rest, gone once a sliver has scrolled under.

The asymmetry is the point. The footer is floating glass and hides what ghosts into it, so its band
keeps upstream's shape and floor; the header carries no material at all, so nothing may survive it.

This is the one upstream file [AGENTS.md](AGENTS.md#non-negotiables) marks off-limits, which is why
the amendment is recorded there as well as here.

**On merge:** take upstream's file only if it has grown a material behind the header; otherwise
re-apply this, since upstream's shape and this fork's transparent header cannot both be right.

## 10 — iCloud settings sync

**Touches:** a new `Features/Sync/` (two pure models with a harness, a consented store, a Backup-pane
section), the fork's bundle ids and `TinycastFork.entitlements` in `project.yml`, `AppCore` wiring,
and a split of `SettingsBackup.swift` that moved `gather`/`apply` to
`Backup/Service/SettingsBackupApplying.swift` so the payload struct is harness-compilable.

The backup payload mirrored through `NSUbiquitousKeyValueStore`, last writer wins — the whole design
is at the foot of [sync.md](docs/features/sync.md), the invariants at its head. The consent flag follows
the `CurrencyRateStore` shape and carries the same warning as divergence 8: `settings-backup-test`
cannot catch it moving into `AppSettings`; only the invariant forbids it.

The signing constraint is the fork-specific part, and it renamed the channels.
`com.apple.developer.ubiquity-kvstore-identifier` must be authorized by an Apple-issued provisioning
profile, which rules out upstream's `Tinycast Self-Signed` CI identity outright — and upstream's
`com.tinycast.app` is registered to a *different* Apple team, so this fork's team could never
provision the release App ID at all. **The fork therefore ships as `com.belesky.tinycast`
(Release) and `com.belesky.tinycast.dev` (Debug)**, both set in `project.yml` alongside
`TinycastFork.entitlements` — upstream's entitlements plus the KVS grant, kept as a separate file so
upstream's `Tinycast.entitlements` stays pristine. A first build on a new machine wants
`-allowProvisioningUpdates`, which registers the App IDs' iCloud capability. On any build signed
without the entitlement, KVS no-ops and the enable-time `synchronize()` probe reports sync
unavailable — a visible dialog, never a silent stall.

**The profile that authorizes the entitlement also names the Macs it covers, and that collides with the
DMG-to-iCloud story.** A development profile carries a `ProvisionedDevices` list; on a Mac outside it
the entitlement fails validation and the app dies at launch as *"may be damaged or incomplete"* — a
message that reads like a broken download and is nothing of the sort. Registering the Mac and
re-downloading the profile is the fix that keeps sync. The alternative — `Developer ID` signing, which
covers any Mac — cannot carry an iCloud entitlement at all, so it costs the feature. `build-dmg.sh`
prints the covered UDIDs after each build rather than leaving this to be rediscovered from the DMG.

The rename resets everything keyed by bundle id on an installed Mac: prefs, caches, Application
Support, TCC grants, the login item. `Scripts/migrate-channel.sh` copies the data classes across
(prefs, caches, App Support) from the `com.tinycast.app` ids; Accessibility and Launch at Login must
be re-granted by hand, and the old app removed. Upstream's `.github/workflows/release.yml` still
builds under upstream's ids — its builds simply report sync unavailable.

**On merge:** unlikely to be upstreamable while upstream signs self-signed. If upstream ever adopts
real signing and its own sync, prefer its transport but keep this fork's decision table and the
re-gather bookkeeping rule (entry 36), which are transport-independent.

## 11 — SwiftUI previews

**Touches:** a new `Tinycast/Previews/` (`PreviewData.swift`, `PreviewChrome.swift`), plus a trailing
`#if DEBUG` / `#Preview` block appended to 22 view files across `DesignSystem/`, `Palette/`,
`Windows/` and `Features/*/UI/`. 34 previews in total.

Upstream has no previews at all — the canvas has never been part of how this app is built, and
[ui.md](docs/ui.md) says to verify AppKit rendering with a `swiftc` harness and leave visual sign-off
to a human. That stays true: a preview asserts nothing and is on no gate. It is a faster loop for the
hand-drawn surfaces, nothing more.

The previews live **in the view's own file** rather than in `Previews/`, because the Xcode canvas only
renders what is in the open editor — a preview a folder away is one you never look at. The cost is 22
upstream files carrying a fork-local tail, which is why every one of them is a pure append after the
last `}`: git resolves an append cleanly unless upstream appends there too, and upstream has nothing
there to append. `Previews/` itself holds only the shared fixtures and the three chrome modifiers, so
the per-file tail stays a handful of lines.

Everything is inside `#if DEBUG`, so a Release binary is byte-identical. That guard is the whole
reason this divergence is cheap, and it is checkable: `nm` on the Release binary must return zero
`PreviewData` / `previewOnDesktop` symbols. The rest of the design — the three modifiers, taking the
store graph from `AppCore.shared`, and the list of states a canvas must not fake — is in
[ui.md#previews](docs/ui.md#previews).

**On merge:** take upstream's version of any conflicting view file whole, then re-append the preview
tail — it depends on nothing but the view's own initialiser and `PreviewData`. If a view's parameters
changed upstream, fix the fixture rather than the view. This is the one divergence that would be
upstreamed as-is, so if upstream ever adds previews of its own, drop the fork's for that file.

## 12 — Re-homed decision reasoning

**Touches:** `docs/ui.md`, `docs/features/palette.md`, `docs/features/web-search.md` and
`docs/features/sync.md`, each of which gained a fork-authored section; and the cross-references in
`AGENTS.md`, `FORK.md` and every fork-local feature doc.

Upstream deleted `docs/decisions.md` in [#222](https://github.com/abue-ammar/tinycast/pull/222) — a
file of 37 numbered entries, dropped inside a feature PR by an outside contributor, with **no content
re-homed** and every cross-reference in upstream's own docs stripped in the same commit. This fork took
the deletion rather than keeping the file, so there is no permanent doc divergence to carry.

Four entries were fork-authored, and those could not simply be deleted with it. They moved to the doc
that owns their subject: **33** (`Theme.scale`, and why point sizes are derived) into
[ui.md](docs/ui.md#why-a-constant-and-why-derived-point-sizes), **34** (adopt-on-transition) into
[palette.md](docs/features/palette.md), **35** (the suggest feed's separate consent) into
[web-search.md](docs/features/web-search.md), and **36** (settings sync) into
[sync.md](docs/features/sync.md). References to *upstream's* entries — 7, 8, 9, 10, 11, 15, 21, 28 —
now point at the invariant itself in [AGENTS.md](AGENTS.md#non-negotiables), which is where they were
enforced all along; the entries only ever held the reasoning behind them.

The reasoning upstream discarded for its own 30-odd entries is not reconstructed here. It is in git
history at `docs/decisions.md` before this merge, and the tag `pre-upstream-merge-2026-08-12` is the
last commit that carries the file.

**On merge:** these are additive sections in files upstream also edits, so expect hunk-level conflicts
rather than whole-file ones — keep upstream's substance and re-append the fork's section. If upstream
ever restores a decisions file, move the four sections back and drop this divergence.

## 13 — No binary-size budget

**Touches:** one deleted line in `docs/standards.md` ("Release binary under **4 MB**") and one in
`docs/testing.md` ("Release binary under **4 MB**, and under 2% growth for an ordinary change").

Upstream holds the Release binary under 4 MB. The fork drops the constraint outright rather than
raising the number, because the number was never the point: upstream ships a download to strangers,
where size is a real cost paid by every install. This fork ships a DMG into iCloud Drive for one
person's own Macs ([release.md](docs/release.md)), where it is a cost paid by nobody.

The immediate cause was upstream's own file-search feature pushing the merged binary to 4.18 MB, but
raising the ceiling to 5 would only defer the same conversation. The budgets that still bind are the
ones a user can feel — resident memory under 100 MB, and launch — and those stay in
[standards.md](docs/standards.md#performance-and-memory) untouched. The Release build itself is still
part of the gate; only the size assertion is gone.

**On merge:** upstream will keep restating the budget in both files. Take upstream's edit to the
surrounding list and re-delete the one line, unless the fork has meanwhile grown a distribution story
where size matters again.

## 14 — Xcode only, no LSP scaffolding

**Touches:** deletes `Scripts/sync-lsp.sh` and all four `.vscode/` files; strips the `--index` mode
from `Scripts/run-tests.sh`; rewrites the Editor and Formatting sections of `docs/development.md` and
the header of `Scripts/format.sh`, both of which justified themselves by ⌘S in VS Code agreeing with
the script; drops `buildServer.json` and `.compile` from `.gitignore`.

Upstream supports editing in VS Code as well as Xcode. That needs a `buildServer.json`, because
SourceKit-LSP can derive compile flags from a `Package.swift` and this project has none — so upstream
carries `xcode-build-server` as a `brew` prerequisite, `sync-lsp.sh` to write the flag database from
an `xcodebuild` log, a `--index` mode in the test runner to add the harnesses to it, and a `.vscode/`
task that re-runs the sync on every build.

**This fork is edited in Xcode, which indexes the project directly and needs none of it.** The whole
chain came out rather than being left to rot: an editor setup nobody runs is the "compatibility layer
nobody dares delete" that [AGENTS.md](AGENTS.md#posture-latest-only-always) is written against, and it
had already rotted here — `xcode-build-server` was not installed, so `sync-lsp.sh` was exiting at its
`command -v` guard and no `buildServer.json` had ever been written.

The one real loss is symbols in `Tests/`: `xcodebuild` never compiles the harnesses, so no editor
indexes them and an open harness reports every shipped type as *cannot find in scope*. That was the
`--index` mode's whole purpose. `development.md` now says so plainly and points at the suite instead,
which is the thing that actually proves a harness compiles.

**On merge:** upstream will keep editing all six files. Take its changes to `run-tests.sh`'s harness
list — that part matters — and re-delete the `--index` plumbing around it; delete the rest again. If
you ever want VS Code back, `git show` any of these paths before this commit brings the whole setup
back intact.

## Merging upstream

```sh
git fetch origin
git checkout main && git merge --ff-only origin/main   # keep the mirror clean
git checkout philip && git rebase origin/main           # replay the divergences
```

Rebase rather than merge, so the fork stays a readable stack of the fourteen commits above rather than a
braid.

**The 2026-08-12 absorption of upstream `a0cfc60..ef1e1b5` was a merge commit, not a rebase**, and is
the one braid in this history. That drop rewrote the palette's hover and scroll model (`HoverArming`,
`scrollFollowsSelection`, `SelectionReveal`) and deleted `docs/decisions.md`, which collided with the
high-risk divergences 2, 3, 4 and 9; replaying twenty-four commits through it meant resolving the same
collision repeatedly, with a silent half-revert the likely outcome. One resolution pass was the safer
trade. Prefer a rebase again next time — the stack is still readable through the merge — and treat
this as the precedent for when not to.

Then, before calling it done — the standard gate from
[testing.md](docs/testing.md#definition-of-done) plus the fork-specific checks:

- [ ] `./Scripts/run-tests.sh` passes (`scope-test`, `websearch-test`, `herdr-test`, `vscode-test`
      and `linear-test` are fork-local).
- [ ] Debug build compiles with no new warnings.
- [ ] `./Scripts/lint.sh` is clean.
- [ ] `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/` returns nothing.
- [ ] **The white-alpha grep above returns only lifting colors and the category tile's glyph**
      (divergences 2, 4).
- [ ] **New or merged views carry no magic numbers** — every length and font size comes from `Theme` (divergence 3).
- [ ] **Signing survived** — if `xcodegen` ran, re-apply divergence 1.
- [ ] **New upstream harnesses compile against the fork's types.** `ScopeTint` and `ScopeDefinition`
      are fork-local but reach into `Theme.swift`, `IconCache.swift` and `PaletteState.swift`, so any
      upstream harness compiling those needs `$L/ScopeTint.swift` (and sometimes `$L/QueryScope.swift`)
      added to its source list in `Scripts/run-tests.sh` — `palette-placement-test`, `icon-cache-test`
      and `hover-arming-test` all needed it (divergences 3, 4).
- [ ] **`PaletteCoordinator.onShow` still fires** — otherwise herdr, VS Code and Linear list stale
      state (divergences 5, 6, 8).
- [ ] **Linear's consent flag is still on the store, not in `AppSettings`** (divergence 8).
- [ ] **Every `#Preview` still compiles**, and the ones whose view upstream changed still render
      something honest (divergence 11).
- [ ] **`nm -a <Release binary> | grep -c 11PreviewData` returns zero, and the same query against
      the Debug `.debug.dylib` does not** — the second half is the control, since a Debug build's
      `MacOS/` executable is a stub and returns zero either way (divergence 11).
- [ ] The palette, a dialog and both HUDs were opened and *looked at*. No agent here can do this.

## Adding a divergence

Add a section, in the same shape: what it touches, what upstream does instead, why the fork differs, and
what to do when the two collide. A divergence that isn't written down here is indistinguishable from a
bad merge six months from now — which is the entire cost this file is paying to avoid.
