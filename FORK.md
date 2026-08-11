# Fork

This checkout is a **fork of [`abue-ammar/tinycast`](https://github.com/abue-ammar/tinycast)**, which is
the `origin` remote and the mainline this file calls **upstream**. Fork work lives on branch `philip`;
`main` tracks `origin/main` untouched, so it is always a clean mirror of upstream.

This file exists for one job: **merging upstream without losing, re-litigating or half-reverting the
local changes.** Every divergence is listed below with what it touches, why it exists, and what to do
when upstream moves the same code. Anything not listed here is not intentional — treat it as drift and
take upstream's side.

Read [decisions.md](docs/decisions.md) first for the choices *upstream* made deliberately. This file only
covers where the fork **departs** from those.

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
docs/ui.md, docs/decisions.md, docs/architecture.md and docs/features/launcher.md all conflict with any
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

Every hit is either a *lifting* color (`panelTint`, `cardFill`, `glassFrost`, the onboarding gradient) or
a bug this fork has to fix. There is no hit that is fine by default.

### Not verified visually by an agent

`screencapture` and `osascript` keystrokes are both blocked by TCC from a shell here — ui.md's "Restyle
from screenshots" note says as much — so the alpha values are reasoned, not eyeballed. `panelTint`, `glassFrost`, `cardFill` and
`selection` are the four numbers to adjust if the surface reads wrong; they are all in `Theme.Colors`.

---

## 3 — `Theme.scale` and derived typography

**Touches:** `Theme.swift` (rewritten), `IconCache.swift`, `RootPaletteView.swift`, eight further view
files, `docs/ui.md`, `docs/decisions.md` (new entry 33).

One compile-time constant multiplies every length and font size in `Theme`, so the whole UI — panel
frame, row icons, keycaps, glyph point sizes, rasterized bitmaps — grows together from a one-line edit.
`Theme.Typography` consequently stopped naming semantic text styles and now derives point sizes from
`NSFont.preferredFont(forTextStyle:)` times the scale, because `Font.body` cannot be scaled and a point
size can. Full reasoning, including the two tokens that are not pixel-identical at `scale 1.0`, is in
decision 33 — which lives in `docs/decisions.md` and is **fork-local**, so it will collide with any
upstream entry that claims the same number.

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
with [decisions.md](docs/decisions.md) entry 34 for the adopt-on-transition rule.

Keywords are **user-editable**, which is the part with the widest settings surface: every scope-owning
pane carries a `ScopeKeywordSection`, so nine upstream panes gain a section they did not have, and
`AppSettings.scopeKeywords` is a dictionary key upstream has no notion of. The panes for the fork's own
features — Web Search, herdr, VS Code — also sit in the **Features** sidebar group rather than
Launcher, so `SettingsSection.tabs` conflicts with any upstream reshuffle of the sidebar.

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

## Merging upstream

```sh
git fetch origin
git checkout main && git merge --ff-only origin/main   # keep the mirror clean
git checkout philip && git rebase origin/main           # replay the divergences
```

Rebase rather than merge, so the fork stays a readable stack of the eight commits above rather than a
braid. Then, before calling it done — the standard gate from
[testing.md](docs/testing.md#definition-of-done) plus the fork-specific checks:

- [ ] `./Scripts/run-tests.sh` passes (24 harnesses; `scope-test`, `websearch-test`, `herdr-test`,
      `vscode-test` and `linear-test` are fork-local).
- [ ] Debug build compiles with no new warnings.
- [ ] `./Scripts/lint.sh` is clean.
- [ ] `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/` returns nothing.
- [ ] **The white-alpha grep above returns only lifting colors** (divergence 2).
- [ ] **New or merged views carry no magic numbers** — every length and font size comes from `Theme` (divergence 3).
- [ ] **Signing survived** — if `xcodegen` ran, re-apply divergence 1.
- [ ] **`PaletteCoordinator.onShow` still fires** — otherwise herdr, VS Code and Linear list stale
      state (divergences 5, 6, 8).
- [ ] **Linear's consent flag is still on the store, not in `AppSettings`** (divergence 8).
- [ ] The palette, a dialog and both HUDs were opened and *looked at*. No agent here can do this.

## Adding a divergence

Add a section, in the same shape: what it touches, what upstream does instead, why the fork differs, and
what to do when the two collide. A divergence that isn't written down here is indistinguishable from a
bad merge six months from now — which is the entire cost this file is paying to avoid.
