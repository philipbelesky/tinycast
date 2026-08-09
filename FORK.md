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

Keep each divergence as **its own commit**, never squashed together. Rebasing `philip` onto a new
`origin/main` then replays them one at a time, and a divergence that upstream has since made redundant
can be dropped whole rather than untangled.

---

## 1 — Apple Development signing

**Commit:** `3ca4321 Signing fix/setup`. **Touches:** `Tinycast.xcodeproj/project.pbxproj` only.

Upstream signs with a stable **self-signed** identity, `Tinycast Self-Signed`, created by hand per
[docs/signing.md](docs/signing.md) — `CODE_SIGN_STYLE: Manual`, an empty `DEVELOPMENT_TEAM`, no Apple
account assumed. This fork signs with **automatic** signing against team `CNPCA4RAWZ` and the
`Apple Development` identity instead, because that account exists here and Xcode manages the certificate
without the one-time openssl ritual. Upstream's reason for the self-signed identity — a *stable* identity
across rebuilds, so macOS keeps the Accessibility grant — is satisfied either way.

> [!WARNING]
> **`xcodegen generate` silently reverts this.** `project.pbxproj` is generated from
> [`project.yml`](project.yml), which still carries upstream's manual/self-signed settings, and AGENTS.md
> tells every contributor to regenerate after touching project settings. The patch survives today only
> because `xcodegen` isn't installed on this machine. After any regeneration, re-apply with
> `git checkout 3ca4321 -- Tinycast.xcodeproj/project.pbxproj`, or re-set signing in Xcode's Signing &
> Capabilities tab.

The durable fix is to stop patching a generated file: set `CODE_SIGN_STYLE`, `DEVELOPMENT_TEAM` and
`CODE_SIGN_IDENTITY` in `project.yml` instead, and accept that `project.yml` then conflicts with upstream
on those three lines — a three-line conflict in a file that rarely changes beats an invisible revert.
An `.xcconfig` included from `project.yml` and git-ignored would avoid even that, at the cost of a file
upstream doesn't know about.

The same commit also renames the product reference from `Tinycast.app` to `Tinycast Dev.app`. That is a
**regeneration artifact, not a decision** — `project.yml` already sets `PRODUCT_NAME: Tinycast Dev` for
Debug. If a merge conflicts there, take either side; the built product is named by the config, not by
that reference.

**On merge:** conflicts in `project.pbxproj` are not worth resolving by hand. Take upstream's file whole,
then re-apply signing.

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

## Merging upstream

```sh
git fetch origin
git checkout main && git merge --ff-only origin/main   # keep the mirror clean
git checkout philip && git rebase origin/main           # replay the divergences
```

Rebase rather than merge, so the fork stays a readable stack of the three commits above rather than a
braid. Then, before calling it done — the standard gate from
[testing.md](docs/testing.md#definition-of-done) plus the two fork-specific checks:

- [ ] `./Scripts/run-tests.sh` passes.
- [ ] Debug build compiles with no new warnings.
- [ ] `./Scripts/lint.sh` is clean.
- [ ] `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/` returns nothing.
- [ ] **The white-alpha grep above returns only lifting colors** (divergence 2).
- [ ] **New or merged views carry no magic numbers** — every length and font size comes from `Theme` (divergence 3).
- [ ] **Signing survived** — if `xcodegen` ran, re-apply divergence 1.
- [ ] The palette, a dialog and both HUDs were opened and *looked at*. No agent here can do this.

## Adding a divergence

Add a section, in the same shape: what it touches, what upstream does instead, why the fork differs, and
what to do when the two collide. A divergence that isn't written down here is indistinguishable from a
bad merge six months from now — which is the entire cost this file is paying to avoid.
