# Palette

The command palette is a borderless floating `NSPanel` hosting SwiftUI; see
[architecture.md](../architecture.md) for window ownership.

## Invariants

- **`PaletteWindowController` solely owns the palette frame.** The hosting view sets
  `sizingOptions = []` so SwiftUI never drives the window size — otherwise the hosting view resizes the
  panel to fit content and the top edge drifts on the compact↔expanded swap.
- **The flat `selection` index must match the visible row order exactly**, including the inline
  calculator card at index 0 when present. Selection is the single source of truth for highlight and
  activation. `Features/PaletteRowIndex.swift` is that mapping and stays **Foundation-only and pure** —
  no SwiftUI, no AppKit — so `palette-selection-test` compiles the shipped type rather than a copy.
  Section headers are not selectable and never consume an index.
- **While a footer menu is open the search field never resigns first responder.** Input is frozen
  instead; resigning shifts the text a point or two.
- **Focus restoration is load-bearing.** Paste targets the recorded `previousApp` and requires the
  Accessibility permission (`Permissions.ensureAccessibility()`).

## Summoning

```
⌥Space (Carbon) → HotKeyCenter → HotKeyManager.perform → AppCore's onTogglePalette closure
                                                              ↓
                                          PaletteCoordinator.togglePalette()
                                                              ↓
                                          PaletteWindowController.show()
                                            · records previousApp (the paste / focus target)
                                            · resolves PasteTarget once per summon
                                            · resolves the screen anchor once per summon
                                            · positions, lays out off-screen, orders front
                                                              ↓
                                                    RootPaletteView.body
```

Everything resolved "once per summon" is resolved there deliberately, not per render. `AppCore` holds
only the closure wiring; the behaviour is `PaletteCoordinator`'s.

## Screens

`PaletteState` (mode / query / selection / `focusToken`) is the bridge between the panel and the app.
Showing the palette calls `prepare(mode:)`, which resets state and bumps `focusToken` (a UUID) so the
SwiftUI search field re-focuses.

Each `PaletteMode` maps to one type conforming to `PaletteScreen`, and the protocol is what keeps the
selection invariant honest: a screen exposes `rows` as its single source of visible order, and the
palette indexes into it. Adding a mode means adding a conformer, not a branch in `RootPaletteView`.

| Mode | Screen | Inner list |
| --- | --- | --- |
| `.launcher` | `LauncherScreen` | `LauncherList` |
| `.clipboard` | `ClipboardScreen` | `ClipboardList` + preview |
| `.calculatorHistory` | `CalculatorHistoryScreen` | `CalculatorHistoryList` |
| `.emoji` | `EmojiScreen` | `EmojiGridView` |
| `.uninstall` | `UninstallScreen` | `UninstallList` (see [uninstall.md](uninstall.md)) |
| `.quicklinks` | `QuicklinkListScreen` | `QuicklinkList` |
| `.quicklinkArguments` | `QuicklinkArgumentsScreen` | `QuicklinkArgumentsView` (see [quicklinks.md](quicklinks.md#the-argument-prompt)) |

Every mode but `.launcher` is a sub-screen that backs out to the launcher. **Tab cycles launcher ↔
clipboard and nothing else**; the rest are reached by a command or a global hotkey, and Uninstall only
from a launcher app's Actions menu, scoped to that app.

The argument screen is the one mode where the search field is not a search field: it _is_ the current
argument's input, so its placeholder names that argument and ↵ submits rather than activating a row.
Its own state lives on `AppCore.quicklinkArguments`, the way `.uninstall`'s target lives on
`UninstallSession`, and leaving the mode cancels the pending open. A bare backspace steps back an
argument before it falls through to the usual exit-to-launcher.

The flat `selection` index is the single source of truth for highlight / activation and **must always
match the visible row order**, including the inline calculator card at index 0 when present (see
[calculator.md](calculator.md)).

## Window placement

`PaletteWindowController` resolves an anchor (left edge + top edge) **once per summon** and reuses it
for every compact↔expanded resize, so only the height changes and the top edge never drifts. The
anchor is dropped on hide, so the next summon re-resolves for wherever the user is then.

Which display it anchors to depends on the **Follow the cursor across displays** setting
(`AppSettings.openOnCursorScreen`, on by default):

- **On** — the screen holding `NSEvent.mouseLocation`, i.e. the display under the pointer.
- **Off** — `NSScreen.main`.

`NSScreen.main` alone can't implement the follow-the-cursor case: it is documented as the _key window's_
screen, and an accessory app driving a non-activating panel has no key window on the display the user is
looking at, so `main` resolves to the menu-bar display regardless of where the pointer is.

The hit test is `NSMouseInRect(mouse, screen.frame, false)`, **not** `CGRect.contains`. A mouse location
is the CoreGraphics cursor position flipped about the primary display's height, so a screen's rows land
in the half-open interval `(minY, maxY]`: the topmost row is exactly `maxY`, which `contains` excludes,
while that same value is the `minY` of the display stacked above. `contains` would therefore hand a
pointer parked at the top of one display to its neighbour. `NSMouseInRect` exists for precisely this.

## The placeholder is Tinycast's, not the field's

The search field is a SwiftUI `TextField` with **no `prompt`**; `RootPaletteView` draws the
placeholder itself as a leading-aligned background `Text`.

AppKit gives an `NSTextField` a field editor one point taller than the field (measured: a 24pt editor
in a 23pt field), and a `prompt` is rendered by whichever of the cell and the editor currently owns
the text. The same placeholder glyphs therefore sit **one point higher** once the field takes the
panel's shared field editor. That editor is created lazily and then cached on the window for its
lifetime, so the step was only ever visible on the first summon after launch — and only where the eye
could track it, when the outgoing and incoming placeholders share a leading word.

Drawing it in SwiftUI pins it to the layout instead: measured ink is identical in both focus states,
against a two-backing-pixel step for the real prompt. It is a **background**, not an overlay, so the
caret still draws over it, and it carries `allowsHitTesting(false)` so clicking the placeholder still
lands the caret. `PaletteMode.placeholder` is still the one source of the strings; the field takes an
explicit `accessibilityLabel` because the prompt used to supply it.

This is the same class of bug as the freeze below — both come from the cell/field-editor swap.

## Scope keywords

A keyword typed at the start of the root search narrows what the query may match. `q github` searches
quicklinks only; `g swift actors` searches the web. (Not to be confused with launcher.md's **search
scopes**, which are the indexed *directories*.)

The whole design is one transition rule, in `Launcher/Model/QueryScope.swift` — Foundation-only, so
`scope-test` compiles the shipped grammar:

- **Adopt.** While no scope is committed, the moment the query *becomes* `<keyword><space>`, the token
  is consumed: the scope goes on `PaletteState.scope` and the field clears. Anything after the space
  (a paste) survives as the query.
- **Pop.** A bare backspace on an empty query clears the scope and puts the keyword back **without**
  its trailing space. That asymmetry is load-bearing: adoption watches for the transition *into*
  `keyword + " "`, so restoring `"q"` cannot immediately re-adopt itself. The chip's × does the same.

`ScopeCatalog` (`Launcher/Service/`) holds the registry and maps an id to a `ScopeTarget`. The grammar
stays id-only because `AppEntry.Kind` and `PaletteMode` live in AppKit-importing files, and a grammar
naming them could never be harness-compiled.

| Keyword | Scope | Target | Chip |
| --- | --- | --- | --- |
| `a` | Applications | `.application` + `.systemSettings` | yes |
| `q` | Quicklinks | `.quicklink` | yes |
| `s` | Snippets | `.snippet` | yes |
| `c` | Commands | `.command` + `.customCommand` | yes |
| `w` | Window Management | `.windowCommand` + `.systemAction` | yes |
| `g` `d` `b` `k` | Google / DuckDuckGo / Bing / Kagi | [web search](web-search.md) | yes |
| `e` | Emoji & Symbols | `PaletteMode.emoji` | no |
| `v` | Clipboard | `PaletteMode.clipboard` | no |

Three behaviours, one grammar. A **filter** scope narrows the launcher's own list, so `q ` with no
text lists every quicklink and favorites stop being pinned — the scope is the intent. A **mode** scope
switches screen instead, and deliberately shows **no chip**: that screen already carries its own header
icon and back chevron, and a second affordance for the same state would be a lie. A **web** scope owns
the whole query and replaces the list with a single search row, so a bare number under `g` is a search
rather than a sum.

A scope is not a mode. `PaletteState.scope` sits beside `query` on the same screen with the same
selection model, and `prepare(mode:)` clears it like every other field. Only the root search adopts
one: a sub-screen is already scoped by its mode, and the argument form's field is not a search field.

A disabled feature contributes no keyword, so `q` does nothing while Quicklinks is off rather than
committing to an empty list.

## Menu-open input freeze

While a footer popover menu (⌘K Actions / app menu) is open the search field reads as inert but
**never resigns first responder** — resigning makes the `NSTextField` swap between its field-editor
and cell rendering, shifting the text / placeholder a point or two, so focus stays put. Input is
frozen instead:

- `RootPaletteView` mirrors the open state into `PaletteState.menuOpen`, whose `didSet` fires
  `onMenuOpenChanged`.
- `PalettePanel.sendEvent` then swallows text-editing keystrokes while `menuOpen` (letting ⌘/⌥ chords
  and menu-nav keys through to SwiftUI `onKeyPress`).
- The caret is hidden by clearing SwiftUI's **own** live field editor's `insertionPointColor`. SwiftUI
  force-casts its field editor to a private subclass, so vending a custom one crashes — only the
  existing one can be tuned.

## Emacs navigation chords

⌃N/⌃P and ⌃F/⌃B navigate exactly as ↓/↑ and →/← do — on the emoji grid all four step the selection,
and everywhere else the horizontal pair falls through to the caret, which is what a native search field
does.

None of them reach `onKeyPress` on their own: AppKit's key-binding table hands the field editor
`moveDown:` / `moveUp:` / `moveForward:` / `moveBackward:` first, and in a one-line field the vertical
pair walks the caret to the end or the start rather than moving anything.

`PalettePanel.sendEvent` therefore rewrites each chord into its arrow and re-dispatches, ahead of every
other rule it applies. Nothing else changes: the arrow handlers in `RootPaletteView` are the only
navigation code, so the compact bar's expand-on-↓, the grid's row and column steps, menu highlight
movement and the scroll-into-view intent all follow for free. The caret keeps ⌃F/⌃B off the grid
because `moveHorizontally` leaves →/← `.ignored` there, and the field editor then moves by a character
exactly as the chord natively would. A chord carrying any modifier beyond ⌃ — ⌃⇧Q, say — is left alone.

## Focus restoration (load-bearing)

`PaletteWindowController` records `previousApp` (the frontmost app) on show. Paste then targets that
app:

- `Paster.paste` activates it and posts a synthetic ⌘V via `CGEvent`.
- `Paster.pasteInPlace` posts ⌘V straight to the app's PID _without_ activating it, so the palette can
  stay open and frontmost (used by "paste keeping window open").

Both require the Accessibility permission (`Permissions.ensureAccessibility()`).

The same show also mirrors that app into `PaletteState.pasteTarget` (a `PasteTarget`: localized
name + bundle path), so Clipboard and Emoji can name it — the footer pill reads "Paste to Notes" and
the ⌘K paste rows carry the app's icon. Resolved once per summon, never per render, and deliberately
not cleared by `prepare` (pop-to-root resets the screen, not the target).
