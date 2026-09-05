# Fork

This checkout is a **fork of [`abue-ammar/tinycast`](https://github.com/abue-ammar/tinycast)**, which is
the `upstream` remote and the mainline this file calls **upstream**; `origin` is the fork itself,
`philipbelesky/tinycast`. Fork work lives on branch `philip`, which is the only branch either remote
carries — the stale local `main` mirror was deleted, so compare against `upstream/main` after
`git fetch upstream`.

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
| 1 | [Apple Development signing, Developer ID export](#1--apple-development-signing-developer-id-export) | Low, but silently reverted by `xcodegen` | No — machine-specific |
| 2 | ~~Forced light appearance~~ — [retired](#2--forced-light-appearance-retired) | None — the fork now takes upstream's | n/a |
| 3 | [`Theme.scale`](#3--themescale-and-derived-typography) | **High** — rewrites `Theme.swift` wholesale | Plausibly yes |
| 4 | [Scope keywords + web search](#4--scope-keywords-and-web-search) | Medium — hooks into `AppIndex`, `RootPaletteView`, `AppEntry.Kind` | Yes, as a feature |
| 5 | [herdr opener](#5--herdr-opener) | Medium — the same `AppEntry.Kind` surface as 4 | Unlikely — niche third-party tool |
| 6 | [VS Code project opener](#6--vs-code-project-opener) | Medium — the same `AppEntry.Kind` surface as 4 | Yes, as a feature |
| 7 | [Replace-on-import for quicklinks](#7--replace-on-import-for-quicklinks) | Low — one button, one method | Yes, small |
| 8 | [Linear opener and ticket lookup](#8--linear-opener-and-ticket-lookup) | Medium — the same `AppEntry.Kind` surface as 4 | Unlikely — niche, and networked |
| 9 | [Header-clearing edge dissolve](#9--header-clearing-edge-dissolve) | **High** — rewrites the top half of a file upstream calls off-limits | Yes — it fixes a real artifact |
| 10 | [iCloud settings sync](#10--icloud-settings-sync) | Medium — `project.yml` ids/entitlements, `AppCore`, a `SettingsBackup` split | No — needs provisioning upstream refuses |
| 11 | [SwiftUI previews](#11--swiftui-previews) | Low — 22 files, every edit an append at EOF | Yes, wholesale |
| 12 | [Re-homed decision reasoning](#12--re-homed-decision-reasoning) | Medium — fork prose inside sections upstream edits | No — upstream deleted the source |
| 13 | [No binary-size budget](#13--no-binary-size-budget) | Low — one deleted line in each of two docs | No — upstream ships to strangers |
| 14 | [Xcode only, no LSP scaffolding](#14--xcode-only-no-lsp-scaffolding) | Medium — five upstream files deleted | No — upstream supports both editors |
| 15 | [Networked features default on](#15--networked-features-default-on) | **High** — deletes all four consent sheets upstream considers structural | No — it inverts a stated invariant |
| 16 | [Second chords for the palette and the clipboard history](#16--second-chords-for-the-palette-and-the-clipboard-history) | Medium — two new `HotKeyAction` cases, so every exhaustive switch over them | Yes, small — but it only pays off with sync |
| 17 | [Word-order-independent matching](#17--word-order-independent-matching) | Medium — reshapes `FuzzyMatch.Query` and `match`, which upstream is actively editing | Yes, as a feature |
| 18 | [Event-tap watchdogs rebuild, not retry](#18--event-tap-watchdogs-rebuild-not-retry) | Low — one branch inside two `healthCheck()` bodies | Yes — it fixes a tap that stays dead |

Keep each divergence as **its own commit**, never squashed together. Rebasing `philip` onto a new
`origin/main` then replays them one at a time, and a divergence that upstream has since made redundant
can be dropped whole rather than untangled.

---

## 1 — Apple Development signing, Developer ID export

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

**Every config still builds with `Apple Development`; Developer ID is applied at export instead.**
Naming `Developer ID Application` as a build setting does not work and Xcode says so outright —
*"automatically signed for development, but a conflicting code signing identity Developer ID
Application has been manually specified"*. Automatic signing only ever selects a **development**
identity during a build; Developer ID is a *distribution* method, reached by archiving and then
exporting. `build-dmg.sh` therefore archives, then runs `-exportArchive` with `method: developer-id`
and `signingStyle: automatic` — precisely what Xcode's **Distribute App ▸ Developer ID** does.

The reason to bother is the device list. A development profile carries `ProvisionedDevices`, so a build
signed that way runs only on the Macs named in it and dies at launch anywhere else as *"damaged or
incomplete"*. The export instead embeds a **`Mac Team Direct Provisioning Profile`**, which reports
`ProvisionsAllDevices = true` and does not expire until **2044** — no device list, and no annual
re-signing treadmill. The `com.apple.developer.ubiquity-kvstore-identifier` entitlement survives the
re-sign intact, so settings sync is unaffected; iCloud is a `DEVELOPER_ID` capability, as Xcode's own
`DVTPortalCachedPortalCapabilities.json` records with
`distributionTypes: [AD_HOC, DEVELOPER_ID, DEVELOPMENT, STORE]`.

`-allowProvisioningUpdates` does the rest: on the first export it **creates the Developer ID Application
certificate and the Direct profile** without anyone visiting the developer portal. Note that the
resulting certificate lives in a Xcode-managed vault keychain and is **invisible to
`security find-identity -p codesigning`** — which is why the script no longer preflights for it, and
why `TINYCAST_SIGN_IDENTITY` is gone. A check that greps for the identity reports a missing certificate
while the export signs with it perfectly happily.

The build is **not notarised**, deliberately. Notarisation would demand Hardened Runtime, which this
app does not enable and which needs auditing against the JavaScriptCore JIT the extension runtime
depends on. It buys nothing on the transport that is actually used: iCloud Drive sets no
`com.apple.quarantine`, and Gatekeeper only demands notarisation of a *quarantined* Developer ID app.
A DMG that reaches a Mac by browser or AirDrop **will** be blocked until it is notarised or the
attribute is cleared by hand — that is the accepted cost, not an oversight.

That is the durable fix, at the price of a permanent three-line conflict with upstream in a file that
rarely changes. A git-ignored `.xcconfig` included from `project.yml` would avoid even that, at the cost
of a file upstream doesn't know about.

`Scripts/build-dmg.sh` followed: it used to hardcode `CODE_SIGN_STYLE=Manual`, the self-signed identity
and `--timestamp=none`, which meant it aborted on line 10 of a fork checkout because that identity was
never created here. It now leaves signing to `project.yml` and the export options, and
preflights only that `project.yml` still names a team to sign for. The same
script gained a fork-local drop step — the finished DMG is copied to `TINYCAST_DMG_DROP`, defaulting to
`~/Library/Mobile Documents/com~apple~CloudDocs/Resources` — which is skipped when the directory is
absent, so it is inert upstream and on CI.

It then installs the app over `/Applications/Tinycast.app`, quitting a running copy and relaunching it
around the swap. For a fork with one install base the build *is* the release, and a build that has not
reached this Mac has not finished. Unlike the drop step this one is unconditional and would replace an
installed app wherever it runs; nothing in CI invokes this script, and the exact-name match confines it
to the stable channel, so `Tinycast Dev` and `Tinycast Beta` are unaffected. If upstream ever wires
`build-dmg.sh` into a workflow, this step needs a guard before that merge lands.

**On merge:** take upstream's `project.pbxproj` whole — hand-resolving it is never worth it — keep the
fork's three lines in `project.yml`, then run `xcodegen generate` and commit the result. If you ever
want upstream's self-signed identity back, create it first ([docs/signing.md](docs/signing.md)); the
build fails outright when `CODE_SIGN_IDENTITY` names an identity the keychain doesn't hold.

---

## 2 — Forced light appearance (retired)

**Retired 2026-08-26, merging upstream v0.10.1.** This divergence forced `.aqua` app-wide and inverted
the whole alpha ramp to black-on-white, because upstream was locked to `.darkAqua` and its decision 4
called light "not a switch, it is a second design".

**Upstream then built that second design.** `Features/Settings/AppAppearance.swift` is a
System / Light / Dark setting, `Theme.Colors` resolves per appearance through `ramp(dark:light:)` and
`adaptive(dark:light:)`, and `IconCache` carries the surface across its off-main rasterization. The
fork took all of it and dropped everything this divergence held: the `.aqua` assignment in
`AppCore.start()`, the `panelTint` rename, the flipped alphas, the light-pinned preview canvases and
the doc prose that called light the invariant. `AppSettings.appearance` defaults to `.system`, which is
upstream's default — pin it to `.light` in `AppSettings.init` if this fork wants its old look back, and
that is now a one-line preference rather than a divergence.

What the retirement leaves behind, and where it went: the fork's category tiles are divergence 4, the
`* scale` factors baked into `IconCache`'s rasterized art are divergence 3, and the previews are
divergence 11. None of those depended on the appearance being fixed.

Kept as a numbered slot rather than renumbered away, so every "divergence N" reference written before
today still points at what it meant.

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

The same applies to upstream's new *typography*, and it is easier to miss: a `Font.body` token merged
into `Theme.Typography` renders at 100% while everything around it renders at `scale`, so upstream's
additions have to be re-spelled through `scaled(_:_:_:)`. Where a value is genuinely chrome and should
not scale, say so on the line — `dropGuideDash`, `dropGuideWidth` and `hairline` are the three that
carry that exemption. **Views under `Features/*/Settings/` and the standalone `Windows/` surfaces are
outside this**: they are system-sized AppKit chrome, and both the fork's own panes and upstream's use
bare `.font(.caption)` there. The rule binds on palette surfaces.

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
[ui.md](docs/ui.md#category-tiles). White is the legible ink on a saturated tile in either
appearance, which is why it is an `adaptive` pair rather than a `ramp`. The rows a scope reveals wear the whole tile too: `AppEntry.categoryIconSource`
gives the launcher list the scope's glyph as well as its tint, while `iconSource` keeps the per-entry
answer everywhere an entry stands for itself, with `AppIconView`'s `source:` parameter carrying the
choice. Applications and System Settings are the one exception: `categoryIconSource` falls back to
`iconSource` for those two kinds, so a launcher row still draws the app's own icon rather than the
red grid tile — a red square tells every app apart from every other app equally, which is exactly
the information an icon exists to carry. Owner's call, reverting part of the tile-everything change.

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

`h payments` lists the tabs of the running [herdr](docs/features/herdr.md) session; ↵ focuses
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

## 8 — Linear opener and ticket lookup

**Touches:** a new `Features/Linear/` (two pure models with a harness, a client, a switchable store, a
coordinator, a settings pane), plus the same hook set as divergences 5 and 6 —
`AppEntry.Kind.linearView`, an `AppIndex` slice, a `LauncherCoordinator` branch, `ScopeCatalog`'s `l`,
`PaletteCoordinator.onShow`, `AppCore` wiring, `SettingsTab` and the settings/backup registries.

`l payments` lists every workspace's Linear sidebar — saved views, projects, initiatives; ↵ opens
one. A number, full identifier or title inside that scope also searches issues across every logged-in
workspace, with exact number searches including archived issues and title searches excluding them. It is
the **second networked feature** in the app and the first the fork added, so it copies
`CurrencyRateStore` rather than inventing a second shape: flag on the store, three guards,
re-checked across the await, cache deleted when it is turned off. **Divergence 15 later deleted this
feature's consent sheet too and defaulted it on**, leaving the guards and the flag's location intact.

Two things not to lose. The flag must stay out of `AppSettings` — `settings-backup-test` will
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

**Touches:** a new `Features/Sync/` (two pure models with a harness, a switchable store, a Backup-pane
section), the fork's bundle ids and `TinycastFork.entitlements` in `project.yml`, `AppCore` wiring,
and a split of `SettingsBackup.swift` that moved `gather`/`apply` to
`Backup/Service/SettingsBackupApplying.swift` so the payload struct is harness-compilable.

The backup payload mirrored through `NSUbiquitousKeyValueStore`, last writer wins — the whole design
is at the foot of [sync.md](docs/features/sync.md), the invariants at its head. The flag follows
the `CurrencyRateStore` shape and carries the same warning as divergence 8: `settings-backup-test`
cannot catch it moving into `AppSettings`; only the invariant forbids it. **Divergence 15 later
deleted this feature's consent sheet and defaulted it on**, which is where the first-contact
consequence is written down.

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
message that reads like a broken download and is nothing of the sort. That is why Release now signs with
**Developer ID** instead (divergence 1): a Developer ID profile names no devices, and iCloud is a
`DEVELOPER_ID` capability, so the entitlement and the sync it powers both survive.

An earlier version of this file claimed Developer ID "cannot carry an iCloud entitlement at all, so it
costs the feature". **That was wrong**, and it steered the design for as long as it stood. The claim
came from documentation and forum lore that were true when iCloud KVS was Mac App Store only; Xcode's
cached portal capabilities contradict it outright. `build-dmg.sh` used to print the covered UDIDs after each build so the
constraint could not be rediscovered from a failing DMG; the Developer ID export embeds a profile that
names no devices, so that block was dead and has been deleted with the claim that motivated it.

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
[palette.md](docs/features/palette.md), **35** (why the suggest feed is its own switch) into
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

**Touches:** one deleted line in `docs/standards.md` ("Release binary under **5 MB**") and one in
`docs/testing.md` ("Release binary under **5 MB**, and under 2% growth for an ordinary change"). The
number moves — it was 4 MB through v0.9.x — so match on the sentence, not the figure.

Upstream holds the Release binary under a fixed ceiling. The fork drops the constraint outright rather than
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

## 15 — Networked features default on

**Touches:** the `isEnabled` initialiser in `CurrencyRateStore`, `SearchSuggestionStore`,
`SettingsSyncStore` and `LinearStore`, `quicklinksEnabled` in `AppSettings`, and the four settings
views that lose a consent sheet — `MiscellaneousSettingsView`, `WebSearchSettingsView`,
`SyncSettingsSection`, `LinearSettingsView`. Plus the non-negotiable in `AGENTS.md`, `SECURITY.md`'s
network clause, and the feature docs that stated the old shape.

Upstream ships every networked feature **off** behind a sheet naming the provider, the cadence and
what leaves the machine, and `AGENTS.md` said in terms that "only my machines" was not an argument
against that. **This fork now defaults currency rates, iCloud settings sync, search suggestions,
quicklinks and the Linear integration to on, and deletes all four consent sheets** — an explicit owner's
decision about the owner's own data on the owner's own Macs, which is the one argument the old rule
refused and the only one available here. It is written down rather than assumed so the next departure
has to be argued too.

Absent still reads through `defaults.object(forKey:) == nil || defaults.bool(forKey:)`, the idiom
`AppSettings` already used for `quicklinksShowInLauncher`, so an explicit `false` survives and only a
never-set key reads as on.

**What deliberately survived.** The flags stay on their stores and out of `AppSettings`, so no backup
or synced envelope can move them in either direction — the reason that rule exists never depended on
the sheet. Each store still re-checks `isEnabled` on both sides of every `await`, which is not
consent bookkeeping but the thing that stops a reply landing after the switch is off, and each still
fetches on a private `.ephemeral`, `urlCache = nil` session. `snippetsEnabled` stays out of backups.
**Snippets is the one gate left**, because enabling it grants keyword expansion over every keystroke
in every app — a different question from whether a feature may fetch.

Linear was the closest call and went with the rest. Tinycast never sees an API token: the `linear` CLI
holds the credentials and this app reads only workspace slugs from its config. Sidebar refreshes send
no typed text; ticket lookup does send the explicit query after the user enters the Linear scope, then
keeps the returned issue metadata in memory for five minutes and never writes it to disk. That is a
meaningful privacy cost, but on these known-owner Macs a permanent Settings disclosure is more useful
than a one-time modal. On a Mac with no CLI installed or none logged in, on is inert — requests fail
closed, nothing publishes, and the unusable scope is removed.

**Two consequences worth knowing.** Sync's first-contact sheet — which side wins when iCloud already
holds a differing envelope — can no longer fire on a first launch, because nothing calls
`requestEnable()`; a fresh Mac takes the remote on the `.startup` trigger. And the sheet was the only
place that said other Macs' shortcuts and custom commands apply automatically, so the post-apply HUD
summary is now the sole runtime notice. `SyncSettingsSection` still keeps the sheet and the
sign-in/entitlement probes for the off → on path.

**On merge:** upstream will keep the sheets and the off-by-default initialisers. Take its changes to
the stores' fetch logic — that is where the real work happens — and re-apply the four one-line
initialisers and the three sheet deletions on top. If upstream ever adds a fifth networked feature,
it arrives off, and whether it joins this list is a fresh decision rather than a default.

## 16 — Second chords for the palette and the clipboard history

**Touches:** two `HotKeyAction` cases and their `defaultsKey`s, the four exhaustive switches over it —
`HotKeyManager.setBinding`, `displayName`, `perform`, and `AppCore.hotKeyDisplayName` — plus
`candidateActions`, `VisibilityStore.allowsHotKey`, `SettingsBackup.HotkeyBackup`, both halves of
`SettingsBackupApplying`, one row each in `GeneralSettingsView` and `ClipboardSettingsView`, and the
`hotkey-test` harness line in `run-tests.sh`. It used to touch `LegacyHotKeyRecords.legacyKey` too;
upstream deleted that scheduled migration in #333 and the fork took the deletion.

Upstream gives every action exactly one global shortcut. This fork adds a second recorder to two of
them: **`HotKeyAction.togglePaletteAlternate`** under `hotkey.togglePalette.alternate`, and
**`.toggleClipboardAlternate`** under `hotkey.toggleClipboard.alternate`. Each alternate joins its
primary in `perform`, so either chord opens the launcher and either opens the clipboard history.

The reason is divergence 10. iCloud sync carries **one** settings envelope to every Mac, and the
author's Macs have different keyboards — a chord that is comfortable on one is awkward or already
taken on the other. Without a second binding the only fixes are a per-device override, which would
mean a second notion of "settings that don't sync", or rebinding by hand after every sync. Two chords
that both work is the cheaper answer, and it is additive: a Mac where only the primary is set behaves
exactly as before.

**Why a new action rather than a plural binding.** `HotKeyAction.defaultsKey` is both the UserDefaults
key and the `HotKeyCenter` registration id, and one action holds one `HotKeyBinding` — an invariant in
[hotkeys.md](docs/features/hotkeys.md#invariants). Making bindings plural would have changed the
on-disk format and rewritten `conflictOwner`, `syncDoubleTaps`, `retargetHyperBindings` and
`HotkeyBackup`, all of which assume a scalar. A second *action* needs none of that and inherits
conflict detection, Hyper re-pointing and the backup field by appearing in `candidateActions`. It also
sidesteps a UI trap: `ShortcutRecorder.isRecording` compares `recordingAction == action`, so two rows
carrying the same action value would both light up and the callout would anchor to whichever rendered
first. Each `displayName` carries a "(second shortcut)" suffix for a related reason — identical names
would make a conflict between the two rows read as a self-conflict.

**The cost, which is real.** Both chords sync and both register on every Mac, so the one a given
machine doesn't want is still claimed there, taken from whatever app would otherwise hold it. This
buys a spare chord per machine rather than a per-machine binding; the per-machine version would have
to sit outside the synced payload, which is a different and heavier feature. Pick alternates no
machine needs for something else.

**Two cases, not a pattern.** A third would be: the case-per-slot shape is cheap twice and tedious at
four, and the plural-binding rewrite above is what it turns into. Nothing else has an alternate, and
adding one is a decision rather than a default.

**On merge:** a new `HotKeyAction` case upstream adds is a mechanical conflict in the same four
switches — take upstream's cases and re-add these two beside them. If upstream ever ships its own
second binding, drop this divergence whole rather than reconciling it. Nothing here touches the Carbon
layer: `HotKeyCenter` already keys registrations by arbitrary string id and has always supported N.

## 17 — Word-order-independent matching

**Touches:** `Launcher/Model/SearchRelevance.swift` — `FuzzyMatch.Query`, `FuzzyMatch.match` and two
new private helpers — plus a `wordOrder()` section in `Tests/fuzz-test.swift` and
`docs/features/launcher.md`.

Upstream matches the query as one string in the order typed, so `pr terminal` finds nothing named
`Terminal PRs`: neither the substring pass nor the subsequence walk can go backwards. That suits app
names, which are short and which people type from the front. It suits none of the entry kinds this
fork added — quicklinks, herdr workspaces, VS Code projects, Linear destinations — whose names are phrases the
owner wrote (`Work / Terminal PRs`) and recalls by content rather than by order.

`FuzzyMatch.Query` now folds every reordering of a two- or three-word query alongside the order typed,
once per keystroke rather than once per candidate. A reordering is scored by the **subsequence walk
alone**, never by the tier ladder, and that restraint is what keeps the change additive: every literal
tier and every band still means what it meant, a reordered hit always sits below an in-order one, and
identifier fields — which already refuse the subsequence band — refuse reorderings for free. Three
words is the cap because the twenty-fourth permutation is where the factorial stops being free.

`Tests/file-search-test.swift` is what found the right rule. Scoring reorderings on the full ladder
let a file named `Report Annual` outrank `Annual Reporting Notes` for `annual report`, which is the
change nobody asked for; the harness already pinned that ordering, and it still passes untouched.

**On merge:** medium risk, and upstream is live in this file — `origin/main` has since added
`FuzzyMatch.score(_:candidate:)`, `isExact(_:candidate:)` and a folded
`SearchRelevance.score(_:fields:)` that this branch has not yet absorbed. `isExact` reads `query.text`,
which is now `query.natural.text`; that rename is the whole fixup. Take the folded-`Query` overloads
when they arrive — they are the same once-per-keystroke optimisation this divergence is built on.

---

## 18 — Event-tap watchdogs rebuild, not retry

**Touches:** `HotKeys/Service/DoubleTapMonitor.swift` and `HotKeys/Service/HyperKeyTap.swift` — one
`reviveAttempted` flag and one branch in each `healthCheck()` — plus the lifecycle section of
`docs/features/hotkeys.md`.

Upstream's one-second watchdog treats a disabled tap as always recoverable: it calls
`CGEvent.tapEnable(tap:enable:true)` and expects the tap back. That holds for the ordinary case the
call was written for, `kCGEventTapDisabledByTimeout` on a callback that ran long. It does not hold
when the window server has stopped honouring the port altogether, and then the watchdog retries
forever against a call that does nothing.

That is not hypothetical. An installed build ran for a day and a half with double-tap ⇧ silently dead:
`CGGetEventTapList` showed the listen-only tap present and `enabled=false`, with `keyDown` stripped out
of its `eventsOfInterest` mask — `0x200100a` against the `0x200140a` the source asks for — while the
modifying Hyper tap in the same process was fine, so the Accessibility grant plainly wasn't the
problem. A live `sample` caught the watchdog mid-call in `SLEventTapEnable`, so roughly 100,000 enable
attempts had already been ignored. Quitting and relaunching fixed it instantly, which is the whole
diagnosis: the port was unrecoverable and only a fresh one would do.

So a tap still disabled on the tick *after* an enable attempt is torn down, and the existing
`tapPort == nil` branch installs a replacement on the next tick. The flag resets in `tearDownTap` and
whenever the tap is observed healthy, so an ordinary timeout still costs one cheap re-enable and no
rebuild — the escalation only fires when the enable was ignored. Two seconds is the worst-case
recovery, against the previous never.

**On merge:** low risk. The branch sits inside a body upstream rarely touches, and if upstream ever
rewrites either watchdog, take its version and re-apply the escalation — the flag is four lines and
carries no state anyone else reads.

---

## 19 — Expired storage relocation removed

The one-time move from Caches to Application Support was removed on its scheduled expiry, 2026-09-05, together with its startup hook and harness. The project was regenerated and the development guidance updated. Durable stores continue to use Application Support; an older cache layout is no longer imported at launch.

**On merge:** retain the deletion if upstream still carries the expired migration; accept its equivalent cleanup when it arrives.

## 20 — Extension helper harness waits for completion

The extension helper harness waits for a rendered result with a ten-second deadline instead of assuming the chmod, process launch and render finish within 1.2 seconds. It also surfaces asynchronous spawn errors in the result. The fixed delay passed in isolation but failed under the parallel suite's load; runtime behavior is unchanged.

**On merge:** keep the bounded completion wait unless upstream supplies an equivalent fix.

## Merging upstream

```sh
git fetch upstream --tags
git checkout philip && git rebase upstream/main         # replay the divergences
```

Rebase rather than merge, so the fork stays a readable stack of the divergences above rather than a
braid.

**The 2026-08-12 absorption of upstream `a0cfc60..ef1e1b5` was a merge commit, not a rebase**, and is
the one braid in this history. That drop rewrote the palette's hover and scroll model (`HoverArming`,
`scrollFollowsSelection`, `SelectionReveal`) and deleted `docs/decisions.md`, which collided with the
high-risk divergences 2, 3, 4 and 9; replaying twenty-four commits through it meant resolving the same
collision repeatedly, with a silent half-revert the likely outcome. One resolution pass was the safer
trade. Prefer a rebase again next time — the stack is still readable through the merge — and treat
this as the precedent for when not to.

**The 2026-08-20 absorption of rewritten upstream `42eb238..793bb1f` is the second merge exception.**
Upstream force-rewrote the history that had previously ended at `ef1e1b5`, although `ef1e1b5` and its
replacement `42eb238` have identical trees. Git therefore selected the pre-fork `d9d6f` merge base and
reported most of the repository as conflicting. The merge was performed with a temporary local replace
ref grafting `ef1e1b5` onto `42eb238`, so Git used that identical tree as the logical base and exposed
only the real overlap. The replace ref was deleted after the merge commit; it is not part of repository
history. Do not reproduce this technique unless upstream has again rewritten a previously absorbed tree
and the old and new boundary commits are verified tree-identical.

Then, before calling it done — the standard gate from
[testing.md](docs/testing.md#definition-of-done) plus the fork-specific checks:

- [ ] `./Scripts/run-tests.sh` passes (`scope-test`, `websearch-test`, `herdr-test`, `vscode-test`
      and `linear-test` are fork-local).
- [ ] Debug build compiles with no new warnings.
- [ ] `./Scripts/lint.sh` is clean.
- [ ] `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/` returns nothing.
- [ ] **No bare `Color.white.opacity(…)` reached a view** — it vanishes in Light. New colours go
      through `Theme.Colors.ramp(dark:light:)` or `adaptive(dark:light:)`; the only bare whites left
      are ink over a saturated fill (the category tile, the Support capsule, the tint picker's ring).
- [ ] **New or merged views carry no magic numbers** — every length and font size comes from `Theme` (divergence 3).
- [ ] **Signing survived** — if `xcodegen` ran, re-apply divergence 1.
- [ ] **New upstream harnesses compile against the fork's types.** `ScopeTint` and `ScopeDefinition`
      are fork-local but reach into `Theme.swift`, `IconCache.swift` and `PaletteState.swift`, so any
      upstream harness compiling those needs `$L/ScopeTint.swift` (and sometimes `$L/QueryScope.swift`)
      added to its source list in `Scripts/run-tests.sh` — `palette-placement-test`, `icon-cache-test`
      and `hover-arming-test` all needed it (divergences 3, 4).
- [ ] **`PaletteCoordinator.onShow` still fires** — otherwise herdr, VS Code and Linear list stale
      state (divergences 5, 6, 8).
- [ ] **Linear's flag is still on the store, not in `AppSettings`** (divergences 8, 15).
- [ ] **The five default-on initialisers survived** — upstream's are `defaults.bool(forKey:)`, the
      fork's are `object(forKey:) == nil || bool(forKey:)`, and a merge that takes upstream's line
      silently ships the feature off again (divergence 15).
- [ ] **No consent sheet came back** for currency, suggestions, sync or Linear —
      `grep -rn 'ConsentSheet\|askingConsent' Tinycast/` returns nothing. The two dialogs that
      *should* exist still do: `SyncRemoteChoiceSheet` and snippets' confirming setter
      (divergence 15).
- [ ] **Both alternate chords survived** — `togglePaletteAlternate` and `toggleClipboardAlternate`
      still exist, `perform` still routes each to its primary's callback, and
      `SettingsBackup.HotkeyBackup` still carries both, or one Mac silently loses a shortcut
      (divergence 16).
- [ ] **Every `#Preview` still compiles**, and the ones whose view upstream changed still render
      something honest (divergence 11).
- [ ] **`nm -a <Release binary> | grep -c 11PreviewData` returns zero, and the same query against
      the Debug `.debug.dylib` does not** — the second half is the control, since a Debug build's
      `MacOS/` executable is a stub and returns zero either way (divergence 11). The Debug bundle is
      `Debug/Tinycast Dev.app/Contents/MacOS/Tinycast Dev.debug.dylib`, not `Tinycast.app`; the
      wrong path returns zero and reads as a passing control.
- [ ] The palette, a dialog and both HUDs were opened and *looked at*. No agent here can do this.

## Adding a divergence

Add a section, in the same shape: what it touches, what upstream does instead, why the fork differs, and
what to do when the two collide. A divergence that isn't written down here is indistinguishable from a
bad merge six months from now — which is the entire cost this file is paying to avoid.
