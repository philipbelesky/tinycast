# Tinycast

A native macOS menu-bar launcher — a minimal Raycast: fuzzy app launcher, global and per-app hotkeys, a
text/image clipboard history, an inline calculator, snippets, quicklinks, web search, a herdr workspace
opener, a VS Code project opener, a Linear view opener, task capture into OmniFocus and TextFlow,
iCloud settings sync, a floating note, window management and an emoji picker. It also **runs Raycast extensions** natively, in JavaScriptCore.
SwiftUI + AppKit, running as an accessory with no Dock icon (`LSUIElement`). Zero third-party
dependencies.

## What this checkout is: one person's fork

This is **Philip's personal fork of [`abue-ammar/tinycast`](https://github.com/abue-ammar/tinycast)**,
on branch `philip`; `main` stays a clean mirror of upstream. It is **not released**: no App Store, no
notarization, no other users. `./Scripts/build-dmg.sh` installs the build over `/Applications` and
drops a DMG into iCloud Drive, which is how it reaches the author's other Macs, and that is the whole
distribution story ([release.md](docs/release.md)).

The install base being known changes what is worth building. A feature that suits exactly one person's
workflow — the herdr, VS Code and Linear openers, task capture — is the point rather than scope
creep, and there is no stranger's data to migrate or old install to keep working, which is the same
reason the modern-first posture below costs nothing.

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

## Posture: modern-first, always

**Tinycast supports macOS 26 and later, with macOS 27 strongly preferred.** Swift 6+ with complete
strict concurrency is required. Prefer the latest Swift patterns and modern Apple APIs.

Prefer current APIs and language features:

- **Prefer the modern Apple API**, always. Observation over `ObservableObject`. `SMAppService` over
  login-item shims.
- **Prefer synchronous code.** Keep short UI and state operations synchronous on `@MainActor`.
  Introduce concurrency only for genuinely asynchronous operations or blocking work that must leave
  the main actor. Shared state alone does not justify `async`, a `Task`, or an actor. Preserve
  synchronous callback returns and event ordering. When concurrency is needed, prefer structured
  concurrency with clear ownership and cancellation. Strict concurrency checking enforces safety;
  it does not require making operations asynchronous.
- **Migrate, never wrap.** Adopt modern replacements directly and delete obsolete call sites. Do not
  keep wrappers that only preserve an old spelling.
- **A deprecated API is a defect**, not a warning to live with.
- **Verify API and language-feature availability** against the SDK and compiler used by the build
  and CI. Use direct availability checks where macOS 27+ APIs require them to preserve macOS 26 support.
- **No compatibility layers, legacy workarounds or obsolete patterns.** No migration scaffolding,
  support below macOS 26 or speculative fallbacks. Keep the implementation direct.

Carbon is a deliberate capability-gap dependency rather than inertia: nothing modern registers a
system-wide chord, and HIToolbox's TIS APIs remain the public input-source mechanism. Full reasoning in
[standards.md](docs/standards.md#posture).

## Where things are

| Folder                   | Holds                                                                                   |
| ------------------------ | --------------------------------------------------------------------------------------- |
| `Tinycast/App/`          | `@main`, `AppDelegate`, `AppCore` — the composition root                                |
| `Tinycast/DesignSystem/` | shared visual primitives; `Theme.swift` is the only design-token source                 |
| `Tinycast/Platform/`     | system shims: `Permissions`, `AppPaths`, `Signposts`, `NotificationToken`, …            |
| `Tinycast/Palette/`      | the palette shell: panel, window controller, `RootPaletteView`, `PaletteScreen`         |
| `Tinycast/Windows/`      | the non-palette AppKit surfaces: `Dialog/`, `HUD/`, `About/`, `AppWindowController`     |
| `Tinycast/Features/`     | one folder per feature; larger ones split `Model/` `Service/` `UI/` `Settings/`         |
| `Tinycast/Previews/`     | `#if DEBUG` fixtures and chrome for the `#Preview` blocks; ships in no Release          |
| `Tests/`                 | the standalone harnesses — one Swift file each, no XCTest target                        |
| `Scripts/`               | every executable script: test runner, data generators, packaging, linting               |

| Read it before you                                          | Doc                                                          |
| ----------------------------------------------------------- | ------------------------------------------------------------ |
| change how anything is wired or owned                       | [architecture.md](docs/architecture.md)                      |
| write Swift — naming, style, concurrency, budgets, comments | [standards.md](docs/standards.md)                            |
| claim a change is done                                      | [testing.md](docs/testing.md)                                |
| build, run or regenerate data                               | [development.md](docs/development.md)                        |
| add or restyle any view                                     | [ui.md](docs/ui.md)                                          |
| touch one feature's internals                               | [features/](docs/features/) — each opens with its invariants |
| package or ship a build                                     | [release.md](docs/release.md)                                |
| merge upstream, or wonder why this differs from mainline    | [FORK.md](FORK.md)                                           |

## Non-negotiables

Never break these without an explicit task to do so. Anything feature-specific lives in that
feature's doc, under its own `## Invariants`.

- **`AppCore` is the sole owner.** New long-lived state goes on `AppCore`, wired in `start()` — never a
  competing singleton. Views reach a feature's **coordinator** through `@Environment`, not `AppCore`.
- **A file under `Features/*/Model/` may not import AppKit or SwiftUI**, and takes every environment
  fact — clock, filesystem, home directory, rates — as an injected parameter. The harnesses compile the
  shipped sources, so this is enforced by compilation rather than convention.
- **Swift 6 language mode: data-race violations are hard errors.** `@MainActor` is the default,
  model values shared across isolation boundaries are `Sendable`, and exclusive ownership transfer
  uses `sending`. Heavy or IO-bound work goes off-main. Prefer `@concurrent` async functions when work
  must leave the caller's actor; use `Task.detached` when an independent task is needed. Do not add a
  second actor.
- **Async results can become stale across suspension.** Before applying them, validate cancellation,
  operation identity and destination where they can change. Long-lived work has an owner and teardown;
  detached or callback-backed work owned by a caller follows that caller's cancellation.
- **Dark is the baseline, and a colour's dark branch is the literal it always was.** `Theme.Colors`
  resolves per appearance through `ramp`/`adaptive`; every dark value is the `Color.white.opacity(…)`
  the forced-dark build shipped, restated rather than re-derived. Retune a light branch freely — change
  a dark one only when the task is to change Dark. `AppAppearance` drives `NSApp.appearance`, and
  `.system` maps to `nil` so AppKit follows macOS on its own.
- **Tinycast presents its own dialogs — never `NSAlert` or a system popover.** A question
  goes through `DialogController`, a report through a HUD via `HUDPresenter`.
- **A networked feature's switch is structural, even though they all now ship on.** Currency rates,
  iCloud sync, search suggestions and Linear default to enabled and ask nothing
  ([FORK.md](FORK.md) divergence 15); **snippets remains gated**, because
  enabling it grants keyword expansion over every keystroke. What holds regardless: the flag lives on
  the owning store and **never** in `AppSettings`, so no import or synced payload can flip it; the
  store re-checks it on both sides of every `await`, so switching off mid-request still stops the
  reply landing; every fetch goes out on a private `.ephemeral`, `urlCache = nil` session, never
  `URLSession.shared`, so its own cache file stays the only copy on disk; and a flag that grants a
  capability is never carried by a backup or by `settings.json` — `snippetsEnabled` is excluded from
  settings backups so an import cannot grant keystroke listening. `CurrencyRateStore` is the
  reference — copy it rather than inventing a second shape.
- **Extensions stay inside `Features/Extensions/`.** Every view, row, menu, geometry and sizing
  constant an extension needs is written and owned there — never added to `DesignSystem/`, never bolted
  onto `Theme`, and never lifted somewhere another feature can build on it. Another surface may render
  one as an opaque box — `LauncherScreen` does exactly that with `ExtensionArgumentsAccessory` — but it
  never reaches inside one. An extension renders untrusted third-party code whose shape we do not
  control, so it must never be able to force a change on a launcher surface.
  **Duplicating a view or a piece of layout maths to keep it here is the correct trade**, and the one
  place the no-duplication rule yields. What _is_ shared: `Theme`'s base tokens (spacing, radius,
  colour), `InterfaceMetrics` as the view over those same base tokens, `PopoverMenuItem` as a data
  shape, and `Platform/`. What is never shared: anything with
  "how an extension looks or moves" in it. `ExtensionActionsPanel` and `ExtensionGridGeometry` exist
  precisely because the palette's own menu and the emoji grid must stay free to change without them.
- **`AppEntry.Kind` is the only thing that says what an entry is.** One case per launcher section and
  per `VisibilityStore` category — never re-derive a category by sniffing an entry ID. Which _pane_
  lists a command is a separate fact, and `SettingsTab.ownedCommands` is the only place that states it.
- **Generated files are never hand-edited.** `EmojiData.generated.swift` and
  `Resources/EmojiKeywords/` come from `node Scripts/gen-emoji.js`, `CurrencyData.generated.swift` from `node Scripts/gen-currencies.js`,
  `CountryZoneData.generated.swift` from `node Scripts/gen-countries.js`, and
  `Resources/RaycastRuntime.generated.js` from `Scripts/raycast-runtime/build.mjs` — the runtime is
  committed so building the app never needs Node.
- **`DesignSystem/Scrolling/EdgeDissolve.swift` and `ThinScrollbar.swift` are off-limits.** Both are
  tuned by eye against the palette's floating bars, so any edit is a visual regression. Needing to touch
  one to fix a scroll bug means the real fix belongs elsewhere.

## Conventions worth knowing up front

- **A new preference also gets a `SettingsFileKey`** and its binding in `SettingsFileSchema`, so the
  opt-in `settings.json` mirror carries it; the exhaustive switch fails the build until it is bound.
  See [settings-file.md](docs/features/settings-file.md).
- **A type's suffix says what it _is_** — `Store`, `Coordinator`, `Controller`, `Manager`, `Engine`,
  `Policy` and the rest each name a specific responsibility. **Semantic correctness always wins over
  suffix consistency:** pick the suffix that describes the type honestly, add a new one when none fits,
  and never rename a well-named type just to match the table.
  Full table: [standards.md#naming](docs/standards.md#naming).
- **Comments are rare, one line, and explain the _why_** — the gotcha or invariant, never the what.
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
