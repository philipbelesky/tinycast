# Tinycast

A native macOS menu-bar launcher — a minimal Raycast: fuzzy app launcher, global and per-app hotkeys, a
text/image clipboard history, an inline calculator, snippets, quicklinks, web search, a herdr workspace
opener, a VS Code project opener, a Linear view opener, iCloud settings sync, window management and an
emoji picker. SwiftUI + AppKit, running as an accessory with no Dock
icon (`LSUIElement`). Zero third-party dependencies.

## What this checkout is: one person's fork

This is **Philip's personal fork of [`abue-ammar/tinycast`](https://github.com/abue-ammar/tinycast)**,
on branch `philip`; `main` stays a clean mirror of upstream. It is **not released**: no App Store, no
notarization, no other users. `./Scripts/build-dmg.sh` drops a DMG into iCloud Drive, which is how it
reaches the author's other Macs, and that is the whole distribution story
([release.md](docs/release.md)).

The install base being known changes what is worth building. A feature that suits exactly one person's
workflow — the herdr, VS Code and Linear openers — is the point rather than scope creep, and there is
no stranger's data to migrate or old install to keep working, which is the same reason the
latest-only posture below costs nothing.

**Absorbing upstream is still a goal, so the fork stays cheap to merge.** Every upstream file touched
is a future conflict: prefer additive, localized changes, put genuinely new work in its own
`Features/` folder rather than threading it through existing ones, and never reformat or restructure
an upstream file in passing. Anything that departs from upstream belongs in [FORK.md](FORK.md), one
commit per divergence.

**What this does *not* license.** "Only my machines" is not an argument for a skipped harness, an
undocumented change or a quiet departure from upstream. It *was* the argument for defaulting the
networked features on ([FORK.md](FORK.md) divergence 15) — the owner's call about the owner's own data,
made once and written down, which is the opposite of a precedent for making the next one silently. The
bar below is what keeps a fork this size mergeable at all.

## Posture: latest-only, always

**Tinycast targets one macOS — the current stable release — and nothing else.** macOS 26+, the Xcode 26
toolchain, Swift 6 language mode. There is no compatibility floor to defend, no shim layer and no
deprecation debt, and that is the single largest reason the codebase stays as small as it does.

Write code as if the platform released yesterday:

- **Prefer the modern Apple API**, always. Observation over `ObservableObject`. Swift Concurrency over
  `DispatchQueue` or completion handlers. `SMAppService` over login-item shims. Structured concurrency
  over detached bookkeeping.
- **Migrate, never wrap.** When an API gains a modern replacement, adopt it and delete the old call
  site. A wrapper that preserves an old spelling is the thing this project has spent the most effort
  removing.
- **A deprecated API is a defect**, not a warning to live with.
- **No compatibility layers, no legacy workarounds, no older architectural patterns.** Delete rather
  than deprecate; raising the minimum macOS *deletes* the code that supported the old one.
- **Never introduce backwards compatibility unless explicitly asked for it.** No version flags, no
  migration scaffolding, no "just in case" fallbacks. The two migrations that exist are scheduled for
  deletion; nothing new may depend on them.

Carbon is the one deliberate exception, and it is a capability gap rather than inertia: nothing modern
registers a system-wide chord. Full reasoning in [standards.md](docs/standards.md#posture).

## Where things are

| Folder | Holds |
| --- | --- |
| `Tinycast/App/` | `@main`, `AppDelegate`, `AppCore` — the composition root |
| `Tinycast/DesignSystem/` | shared visual primitives; `Theme.swift` is the only design-token source |
| `Tinycast/Platform/` | system shims: `Permissions`, `AppPaths`, `Signposts`, `NotificationToken`, … |
| `Tinycast/Palette/` | the palette shell: panel, window controller, `RootPaletteView`, `PaletteScreen` |
| `Tinycast/Windows/` | the non-palette AppKit surfaces: `Dialog/`, `HUD/`, `About/`, `AppWindowController` |
| `Tinycast/Features/` | one folder per feature; larger ones split `Model/` `Service/` `UI/` `Settings/` |
| `Tinycast/Previews/` | `#if DEBUG` fixtures and chrome for the `#Preview` blocks; ships in no Release |
| `Tests/` | the standalone harnesses — one Swift file each, no XCTest target |
| `Scripts/` | every executable script: test runner, data generators, packaging, linting |

| Read it before you | Doc |
| --- | --- |
| change how anything is wired or owned | [architecture.md](docs/architecture.md) |
| write Swift — naming, style, concurrency, budgets, comments | [standards.md](docs/standards.md) |
| claim a change is done | [testing.md](docs/testing.md) |
| build, run or regenerate data | [development.md](docs/development.md) |
| add or restyle any view | [ui.md](docs/ui.md) |
| touch one feature's internals | [features/](docs/features/) — each opens with its invariants |
| package or ship a build | [release.md](docs/release.md) |
| merge upstream, or wonder why this differs from mainline | [FORK.md](FORK.md) |

## Non-negotiables

Never break these without an explicit task to do so. Anything feature-specific lives in that
feature's doc, under its own `## Invariants`.

- **`AppCore` is the sole owner.** New long-lived state goes on `AppCore`, wired in `start()` — never a
  competing singleton. Views reach a feature's **coordinator** through `@Environment`, not `AppCore`.
- **A file under `Features/*/Model/` may not import AppKit or SwiftUI**, and takes every environment
  fact — clock, filesystem, home directory, rates — as an injected parameter. The harnesses compile the
  shipped sources, so this is enforced by compilation rather than convention.
- **Swift 6 language mode: data-race violations are hard errors.** `@MainActor` is the default,
  cross-actor model types are `Sendable`, and heavy or IO-bound work goes off-main as `nonisolated`
  functions driven by `Task.detached`. Do not add a second actor.
- **The app is locked to `.aqua` globally.** The Liquid Glass material is tuned for a bright frosted
  surface; dark mode is not a switch, it is a second design. ([FORK.md](FORK.md) divergence 2)
- **Tinycast presents its own dialogs — never `NSAlert`, `NSSlider` or a system popover.** A question
  goes through `DialogController`, a report through a HUD via `HUDPresenter`.
- **A networked feature's switch is structural, even though they all now ship on.** Currency rates,
  iCloud sync, search suggestions and Linear default to enabled and ask nothing
  ([FORK.md](FORK.md) divergence 15); **snippets is the last gated feature**, and only because
  enabling it grants keyword expansion over every keystroke. What holds regardless: the flag lives on
  the owning store and **never** in `AppSettings`, so no import or synced payload can flip it; the
  store re-checks it on both sides of every `await`, so switching off mid-request still stops the
  reply landing; every fetch goes out on a private `.ephemeral`, `urlCache = nil` session; and
  `snippetsEnabled` stays out of settings backups. `CurrencyRateStore` is the reference — copy it
  rather than inventing a second shape.
- **`AppEntry.Kind` is the only thing that says what an entry is.** One case per launcher section, per
  `VisibilityStore` category and per Settings pane — never re-derive a category by sniffing an entry ID.
- **Generated files are never hand-edited.** `EmojiData.generated.swift` comes from
  `node Scripts/gen-emoji.js`, `CurrencyData.generated.swift` from `node Scripts/gen-currencies.js`.
- **`DesignSystem/Scrolling/EdgeDissolve.swift` and `ThinScrollbar.swift` are off-limits.** Both are
  tuned by eye against the palette's floating bars, so any edit is a visual regression. Needing to touch
  one to fix a scroll bug means the real fix belongs elsewhere.

## Conventions worth knowing up front

- **A type's suffix says what it *is*** — `Store`, `Coordinator`, `Controller`, `Manager`, `Engine`,
  `Policy` and the rest each name a specific responsibility. **Semantic correctness always wins over
  suffix consistency:** pick the suffix that describes the type honestly, add a new one when none fits,
  and never rename a well-named type just to match the table.
  Full table: [standards.md#naming](docs/standards.md#naming).
- **Comments are rare, one line, and explain the *why*** — the gotcha or invariant, never the what.
  **Never two in a row, never extended into a block**: if one line can't carry it, name a function,
  constant or type instead. Cap 100 characters, delete rather than update, and never comment a change
  you just made. Nothing lints this; get it right the first time.
  Full rules: [standards.md#comments](docs/standards.md#comments).
- **Debug builds are their own channel** — `Tinycast Dev.app` / `com.belesky.tinycast.dev` — so a local run
  never shares prefs, caches, TCC grants or the login item with an installed copy. Anything newly
  persisted must stay keyed by `Bundle.main.bundleIdentifier`.
- **XcodeGen owns the project.** `Tinycast.xcodeproj` is committed but generated from `project.yml`;
  after editing it, run `xcodegen generate` and commit both. Read the pbxproj diff before committing —
  a run against a half-checked-out tree silently drops sources. No SwiftPM, and never `Bundle.module`.

## Before you finish

Each item is explained in [testing.md](docs/testing.md#definition-of-done).

- `./Scripts/run-tests.sh` passes.
- A **clean** Debug build — fresh `-derivedDataPath` — compiles with **no new warnings**. An
  incremental one only re-warns about files it recompiled, and will not notice a stale `project.pbxproj`.
- `./Scripts/lint.sh` is clean.
- `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/` returns nothing.
- Any doc your change made wrong is fixed in the same commit.
