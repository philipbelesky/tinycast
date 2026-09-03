# Palette

The command palette is a borderless floating `NSPanel` hosting SwiftUI; see
[architecture.md](../architecture.md) for window ownership.

## Invariants

- **`PaletteWindowController` solely owns the palette frame.** The hosting view sets
  `sizingOptions = []` so SwiftUI never drives the window size — otherwise the hosting view resizes the
  panel to fit content and the top edge drifts on the compact↔expanded swap. A user drag is the one
  frame change that starts elsewhere, and `windowDidMove` folds it back into the anchor so the
  controller stays the authority.
- **The flat `selection` index must match the visible row order exactly**, including the inline
  calculator card at index 0 when present. Selection is the single source of truth for highlight and
  activation. `Features/PaletteRowIndex.swift` is that mapping and stays **Foundation-only and pure** —
  no SwiftUI, no AppKit — so `palette-selection-test` compiles the shipped type rather than a copy.
  Section headers are not selectable and never consume an index.
- **While a footer menu is open the search field never resigns first responder.** Input is frozen
  instead; resigning shifts the text a point or two.
- **Focus restoration is load-bearing.** Paste targets the recorded `previousApp` and requires the
  Accessibility permission (`Permissions.ensureAccessibility()`).
- **Input-source switching is a palette session.** The source active at summon time is captured before
  the panel becomes key, the configured source is applied through `PalettePanel.fieldEditorContext`, and
  the captured source is restored on hide and on termination — but only when the palette is still on the
  source it applied, so a switch made since, by the user or another app, stands. Never applied globally:
  the panel does not activate, so a global switch would land on whichever app is still frontmost.

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
                                            · captures the input source to restore, once per summon
                                            · positions, lays out off-screen, orders front
                                                              ↓
                                                    RootPaletteView.body
                                            · focuses the search field
                                                              ↓
                                            PalettePanel.makeFirstResponder
                                            · applies the configured source to the field editor
```

Everything resolved "once per summon" is resolved there deliberately, not per render. `AppCore` holds
only the closure wiring; the behaviour is `PaletteCoordinator`'s.

## Screens

`PaletteState` (mode / query / selection / `focusToken`) is the bridge between the panel and the app.
Showing the palette calls `prepare(mode:)`, which resets state and bumps `focusToken` (a UUID) so the
SwiftUI search field re-focuses.

Hiding schedules Pop to Root Search, and `PaletteWindowController.popToRoot` is its only path: the
palette returns to the launcher *and* chat starts a new conversation, at once or after
`popToRootTimeout`, unless a re-summon inside that window consumes the pending reset first. An
unfinished chat is a thing being done, exactly like a typed query, so the screen and the conversation
are reset together rather than the screen alone. A reply still streaming is the one exception — it was
asked for, and resetting would throw the answer away. Nothing is lost either way: a conversation is
written to Chat History as soon as it has a message.

Each `PaletteMode` maps to one type conforming to `PaletteScreen`, and the protocol is what keeps the
selection invariant honest: a screen exposes `rows` as its single source of visible order, and the
palette indexes into it. Adding a mode means adding a conformer, not a branch in `RootPaletteView`.

| Mode | Screen | Inner list |
| --- | --- | --- |
| `.launcher` | `LauncherScreen` | `LauncherList` |
| `.clipboard` | `ClipboardScreen` | `ClipboardList` + preview |
| `.calculatorHistory` | `CalculatorHistoryScreen` | `CalculatorHistoryList` |
| `.emoji` | `EmojiScreen` | `EmojiGridView` |
| `.fileSearch` | `FileSearchScreen` | `FileSearchList` (see [file-search.md](file-search.md)) |
| `.schedule` | `ScheduleScreen` | `ScheduleList` (see [calendar.md](calendar.md)) |
| `.uninstall` | `UninstallScreen` | `UninstallList` (see [uninstall.md](uninstall.md)) |
| `.quicklinks` | `QuicklinkListScreen` | `QuicklinkList` |
| `.snippets` | `SnippetsScreen` | `SnippetsList` + preview (see [snippets.md](snippets.md#search-snippets)) |
| `.quicklinkArguments` | `QuicklinkArgumentsScreen` | `QuicklinkArgumentsView` (see [quicklinks.md](quicklinks.md#the-argument-prompt)) |
| `.customCommandArguments` | `CustomCommandArgumentsScreen` | `CustomCommandArgumentsView` (see [custom-commands.md](custom-commands.md#arguments)) |
| `.extensionCommand` | `ExtensionCommandScreen` | `ExtensionCommandView` (see [extensions.md](extensions.md)) |

Every mode but `.launcher` is a sub-screen that backs out to the launcher. **Tab rings the three
surfaces a reader opens directly — launcher → AI chat → clipboard → launcher** — unless the selected
row declares arguments, in which case it walks those fields first (see below); every other mode exits
to the launcher rather than joining the ring, and is reached by a command or a global hotkey, with
Uninstall only from a launcher app's Actions menu, scoped to that app. Chat is skipped whole when
`aiEnabled` is off, which leaves the launcher ↔ clipboard flip the ring replaced. **Escape clears a
non-empty query before it leaves the screen**, so one press clears and the next leaves: chat backs
out to the launcher, an extension screen exits itself, and anywhere else the palette hides.

The launcher advertises the first hop in the header — `AI Chat` beside a `⇥` cap, the footer's own
pairing of a label with its key. It is drawn only when Tab really would open chat, a condition read
back out of `PaletteTabAction` rather than restated, so a hint can never promise a destination the
key does not go to: an argument field to walk takes Tab first, and the hint steps aside for it.

`PaletteTabAction` decides where Tab goes *and* what happens to the typed text. The clipboard hands
the query over, since one search narrows either list. **From the launcher, Tab `.ask`s** — chat opens
fresh with the typed text already sent, so one key turns a search into a question. Leaving chat is
still a `.freshScreen`: that field holds a half-written message rather than a query, and a draft
dropped into a filter matches nothing. `.ask` is its own case rather than a `carryQuery(.ai)` because
the text is submitted, not seeded, and the hint reads the case back out (`== .ask`) instead of
restating the rule.

The two argument screens — `.quicklinkArguments` and `.customCommandArguments`, together
`PaletteMode.isArgumentForm` — are the modes where the search field is not a search field: it _is_ the
current argument's input, so its placeholder names that argument and ↵ submits rather than activating
a row. Neither has rows, which is why `isArgumentForm` is what keeps the ↵ pill drawn. Their state
lives on `AppCore.quicklinkArguments` and `AppCore.customCommandArguments`, the way `.uninstall`'s
target lives on `UninstallSession`, and leaving the mode cancels the pending open or run. A bare
backspace steps back an argument before it falls through to the usual exit-to-launcher; Escape erases
the half-typed answer first, and a second press hides the palette, ending the pending work with it.

### Inline command arguments

An extension command can declare arguments, and they are typed **in the header, beside the search
field** — not on a screen of their own. That costs the header its one simple rule, so it holds two
invariants:

- The search field sits at **one structural position, always**. It is never moved inside an `if`:
  flipping the branch tears down its field editor, which drops first responder mid-navigation. Only
  its *width* changes — it shrinks to the width of the typed text so the argument chips sit right
  after it, as they do in Raycast.
- Argument focus is its own `@FocusState`, `argumentFocused`, keyed by argument name. Moving the
  selection hands focus back to the search field first, because the row that owned those fields is
  about to stop being selected. ↵ on a blank required argument focuses it instead of launching.

The typed values live on `PaletteState.commandArguments`, keyed by
`PaletteState.argumentKey(entryID, name)`, and are cleared with the rest of the screen.

The flat `selection` index is the single source of truth for highlight / activation and **must always
match the visible row order**, including the card at index 0 when present — the calculator's (see
[calculator.md](calculator.md)) or the meeting join card (see [calendar.md](calendar.md)), never both.

## Window placement

`PaletteWindowController` resolves an anchor (left edge + top edge) **once per summon** and reuses it
for every compact↔expanded resize, so only the height changes and the top edge never drifts. The
anchor is dropped on hide, so the next summon re-resolves for wherever the user is then.

All of the arithmetic lives in `PalettePlacement`, which is CoreGraphics-only and takes every screen
fact as a parameter, so `palette-placement-test` drives the shipped rules rather than a copy of them.

### Drag to reposition

**Drag to reposition** (`AppSettings.paletteDraggable`, off by default) is the only thing that moves a
panel already on screen. `WindowDragHandle` claims mouse-down on the top strip and on the header's
margins and inter-item gaps (`RootPaletteView.headerGutter`) — everywhere in the header no control
occupies. The search field is a handle too, but only past its visible text:
`TextTrailingDragHandle` measures the query in `Theme.Typography.searchFieldNSFont` and claims the
hit-test only beyond it, so clicking or dragging the text still edits and selects, matching Spotlight.

AppKit moves the frame without going through the controller, so `windowDidMove` writes the new top-left
back into the anchor — otherwise the next compact↔expanded resize would snap the panel back to the
position it was summoned at. That write is idempotent, since `positionPanel` places the frame at exactly
the anchor and its own `setFrame` round-trips the same values.

**The handle tracks the gesture itself rather than calling `performDrag(with:)`.** That method hands the
drag to the window server and returns immediately, so it can say when a drag *starts* but never when it
ends — the mouse-up arrives long after it has returned. `DragView.mouseDown` instead runs
`trackEvents(matching:timeout:mode:)` over `.leftMouseDragged` / `.leftMouseUp`, moving the window by
the `NSEvent.mouseLocation` delta, which puts the whole gesture inside one call. It brackets that with
`PaletteCoordinator.beginPaletteDrag()` / `endPaletteDrag()`, and the controller holds a `DragSession`
for exactly that span. **Only a move inside a session is a user drag**; without that flag every
programmatic resize would be recorded as one.

### The drop guides

While a drag is in flight, `PaletteDropGuideController` puts a click-through borderless panel over the
display the panel is on, one level under `.floating` so it never covers the panel being dragged. It
draws three dotted lines through the default placement — both panel edges full height, the top edge full
width — which turn `Theme.Colors.dropGuideArmed` once the anchor is within `Theme.Size.paletteSnapDistance`
of home. Releasing while armed snaps the panel there.

The guides wait for the first `windowDidMove` of a session rather than appearing on mouse-down, so a
bare click on a handle never flashes them. Crossing to another display re-points them at that display's
default placement, which is what a snap would then land on.

### Remembering where it was left

A drop that isn't a snap writes the anchor to `AppSettings.palettePosition`, and the next summon reopens
there — across relaunches, since it is a persisted setting. **A remembered position outranks the display
setting below**; `PalettePlacement.restored` drops it only when no display still shows
`Theme.Size.paletteMinimumVisible` of the compact bar, which is what a disconnected screen or a
resolution change leaves behind. Snapping onto the guides clears the stored position, so the guides
double as the way back to default behaviour.

The position is deliberately **not** in a settings backup — it is machine-local geometry, the same
reason the Settings window autosaves its frame instead ([backup.md](backup.md)).

Which display an *unremembered* palette anchors to depends on the **Follow the cursor across displays**
setting (`AppSettings.openOnCursorScreen`, on by default):

- **On** — `NSScreen.underCursor`: the screen holding `NSEvent.mouseLocation`, i.e. the display under
  the pointer.
- **Off** — `NSScreen.primary`: the screen at the global origin, i.e. the one with the menu bar.

**Neither case may use `NSScreen.main`**, which is documented as the screen of the window with keyboard
focus — the frontmost app's, wherever the user last clicked. It therefore follows the user across
displays, which is the wrong answer for both settings and made the off case do exactly what turning it
off was meant to stop ([#270](https://github.com/abue-ammar/tinycast/issues/270)). The menu-bar display
is the one whose `frame.origin` is `.zero`, which is what `primary` looks for.

The cursor hit test is `NSMouseInRect(mouse, screen.frame, false)`, **not** `CGRect.contains`. A mouse
location is the CoreGraphics cursor position flipped about the primary display's height, so a screen's
rows land in the half-open interval `(minY, maxY]`: the topmost row is exactly `maxY`, which `contains`
excludes, while that same value is the `minY` of the display stacked above. `contains` would therefore
hand a pointer parked at the top of one display to its neighbour. `NSMouseInRect` exists for this.

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

Every keyword below is the **shipped default**; each is editable in that feature's own Settings
pane, and the table is what a fresh install reads.

| Keyword | Scope | Target | Chip |
| --- | --- | --- | --- |
| `a` | Applications | `.application` + `.systemSettings` | yes |
| `q` | Quicklinks | `.quicklink` | yes |
| `s` | Snippets | `.snippet` | yes |
| `c` | Commands | `.command` + `.customCommand` | yes |
| `w` | Window Management | `.windowCommand` + `.systemAction` | yes |
| `h` | herdr | `.herdrTarget` | yes |
| `p` | VS Code | `.vsCodeProject` | yes |
| `l` | Linear | `.linearTarget` | yes |
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

### Why adoption is a transition

`QueryScope.adopting` fires only when the query *becomes* `keyword + " "`. Popping a scope puts the
keyword back **without** its trailing space.

**Why:** the obvious design — reinterpret the whole string on every keystroke — cannot express "I
popped this scope and want the letters back". Restoring `"q "` would re-adopt on the same render, and
restoring nothing would eat text the user typed. Watching for the transition makes the committed state
and the literal text two different things, which is what lets backspace undo exactly one step.

**What would change this:** multi-token scoping (`q g foo`), which would need a real parser and a
different undo story.

### Scopes are rows too

A keyword is only half the affordance: nobody discovers `p` by guessing. Every scope also publishes a
launcher row of kind `.scope`, and **activating one is exactly typing its keyword and a space** —
`PaletteState.scope` is armed, the query clears, the chip appears. A mode scope switches screen
instead, the same as adopting one by typing. The keyword rides along as a match alias, so typing `l`
finds the Linear row as readily as typing the word does.

Each row carries its keyword as a keycap, in the same slot a bound hotkey's keycaps occupy — read
from the catalog at render rather than baked onto the entry, so a keyword edited in Settings is never
shown stale. Its icon is a coloured category tile rather than the ordinary inked one, one hue per
scope — and the rows that scope reveals wear the same tile, glyph and colour both, so a herdr tab and
the herdr row that leads to it read as one category. See [ui.md](../ui.md#category-tiles).

A scope is only offered when something is actually behind it: `AppCore` drops any filter scope whose
kinds have no published entries. That is what stops a feature which is off — or, like Linear without
its CLI, on but unable to publish anything — from advertising a scope that opens an empty list. Mode scopes are screens
and always qualify.

Those rows are published **first**, so they lead the launcher's empty query ahead of applications:
opening the palette on nothing now shows what the search can be narrowed *to*, which is the one list
that explains the rest. Favorites still pin above them.

Search engines are deliberately left out of that slice. Each already publishes a `.webSearch` row
which arms the same scope, and two rows for one destination would misrepresent the list.

The registry follows the feature switches and the user's keywords, so `AppCore` re-reads it whenever
the palette opens rather than tracking a dozen settings — the same trigger herdr, VS Code and Linear
already use. `Settings → General → Search Scopes` hides the category, or any single scope, through
`VisibilityStore` like every other launcher category.

### Choosing your own

`ScopeKeywords` (`Launcher/Model/`, Foundation-only, covered by `scope-test`) layers
`AppSettings.scopeKeywords` — scope id → keyword — over the shipped table. Only overrides are stored,
so a keyword edited back to its default is removed rather than pinned, and a later build can still
move the default under it.

`normalized` is **total**: the field accepts anything, and what the grammar ends up seeing is trimmed,
lowercased, cut at the first inner space and capped at `maximumLength` (4). Cutting at the space is
not cosmetic — a keyword containing one could never be adopted, since adoption reads the token *before*
the committing space. An empty result is legitimate: it is how a feature is left with no keyword at
all, which is why clearing the field is offered rather than refused.

Two scopes may not share a keyword. `ScopeKeywordField` refuses the edit and names the scope already
holding it, so a collision normally cannot be written. `ScopeKeywords.resolve` is the backstop for the
ones that arrive anyway — an edited backup, a stale write — and strips the keyword from the **later**
scope in declaration order rather than dropping either, so a token is never ambiguous about what it
adopts.

Conflicts are checked against **every** scope, not just the enabled ones: a keyword held by a
switched-off feature is still taken, or turning that feature back on would silently steal it.

`ScopeCatalog.allDefinitions` is what Settings edits against; `registry` is that same list filtered to
what is currently enabled. Both are computed per call, so an edit reaches the palette immediately.
## IME composition

A hand-drawn placeholder has one cost the real prompt does not. An IME composes into the field
editor's own storage, so the bound `query` stays empty for the whole romanisation and the placeholder
would sit under the in-flight pinyin. `PalettePanel` publishes the editor's `hasMarkedText()` as
`PaletteState.isComposing`, and the placeholder is gated on `query.isEmpty && !isComposing`.

The observation follows first responder, since SwiftUI hands the window's one field editor to
whichever field holds focus, and it watches `NSTextView.didChangeSelectionNotification`. Measured,
that is the **only** notification a marked-text change posts: `NSText.didChangeNotification` fires on
the commit alone, which is the whole composition too late.

`trackComposition()` re-reads the editor rather than assuming, and `windowDidBecomeKey` calls it as
well as `makeFirstResponder`: a key transition can commit or drop marked text without posting
anything, and a re-summon inside the Pop to Root window skips `prepare(mode:)` and never moves first
responder, so neither of the other two paths would fire.

## The panel settles the pointer itself

`PalettePanel.applyCursorPolicy` sets the cursor after every mouse event: the I-beam inside the search
field's frame, the arrow everywhere else. Without it the palette's pointer sticks as an I-beam over the
whole window and flickers along the field's edge — the two AppKit mechanisms that claim a cursor here
disagree, and neither yields.

- SwiftUI's `HostingClipView` claims the **arrow** across the entire window as a *cursor rect*.
- The field editor claims the **I-beam** from its own *tracking area*.

Both fire on the same crossings, so the cursor alternates while the pointer is over the field, and the
last claim simply stays put once it leaves — nothing re-evaluates a cursor rect until the pointer
crosses one, and the arrow rect spans the window, so leaving the field crosses nothing.

Two measured details the policy depends on:

- **The field publishes its own frame.** `RootPaletteView` reports it into `PaletteState.searchFieldFrame`
  via `onGeometryChange`, and the panel does a containment test against that. Hit-testing for the field
  instead does not work: SwiftUI rebuilds it as it re-renders, and a hit test taken mid-rebuild misses
  it and reads as *the pointer left the field*. The frame only moves on layout, so it never lies.
  It arrives top-left-down and is flipped into AppKit's bottom-left-up window space.
- **The rect is outset by 2pt.** AppKit's field editor is a point taller than the field it serves — the
  same measurement the placeholder section above rests on — so its I-beam overhangs the published
  frame. Without the slack that 1pt band is a disagreement, and it flickers.

The policy runs after `super.sendEvent`, so it has the last word, and it writes only when the cursor
actually differs. It must stay **symmetric**: an earlier version left the field alone and only forced
the arrow outside it, and AppKit's own alternation over the field came straight back.

## One menu at a time

`RootPaletteView` holds a single `OpenMenu?` rather than a flag per menu, so "at most one is open" is
structural instead of a pair of `onChange` handlers pushing each other closed. Three cases today —
the ⌘K Actions menu (`.bottomTrailing`), the app menu (`.bottomLeading`) and the clipboard type
filter (`.belowHeaderTrailing`, hung under its header button). `menuContent` resolves the open case to one
`PaletteMenuContent` — a row count, a row action and a view built on demand — so ↑/↓, plain ↵, Esc and
the click-away catcher serve every menu without knowing which is up. A screen supplies its rows as a
`PopoverMenuContent` through `actions(at:)` and the default `menuContent` wraps them; a screen whose
rows the palette's menu can't express overrides `menuContent` and hands over its own view instead —
`ExtensionCommandScreen` is the only one, and the reason the seam exists (see
[extensions.md](extensions.md)). The view is a closure because `moveMenu` resolves the open menu on
every arrow key and needs the row count alone. Every open path goes through `open(_:highlighting:)`
and states where the highlight starts: the first row, except the type filter, which opens on the
active filter.

Every row closes the menu behind it — `activateMenuItem` is the one path, and a row that reorders the
list under itself (Move Favorite Up/Down) is no exception, so no row ever runs against a rebuilt menu.

### The menu's own window

A menu is **not** an overlay inside the palette: `MenuPanelController` hosts it in a `MenuPanel`, a
borderless non-activating `NSPanel` added as a **child window** of the palette's, which is what makes
it follow a palette drag and vanish with it. Glass renders against the desktop rather than inside an
already-blurred, clipped panel, and no menu can be cropped by `RootPaletteView`'s `clipShape` however
long it grows. `MenuPanel.canBecomeKey` is `false` so the palette keeps key status and its
`onKeyPress` handlers keep driving the highlight, and `MenuPanel.sendEvent` mirrors `PalettePanel`'s
hover arming — rows light on real pointer movement, never on a scroll under a still cursor.

The panel is a second SwiftUI hierarchy, so it observes nothing of `RootPaletteView`'s `@State`:
`syncMenuPanel` pushes a rebuilt tree on every `openMenu` or `menuSelection` change, and
`paletteEnvironment` injects the same stores into both hierarchies so they cannot drift.
`WindowReader` reports the palette's `NSWindow`, which the menu's frame is placed against.

## Menu-open input freeze

While a popover menu (⌘K Actions / app menu / clipboard type filter) is open the search field reads as inert but
**never resigns first responder** — resigning makes the `NSTextField` swap between its field-editor
and cell rendering, shifting the text / placeholder a point or two, so focus stays put. Input is
frozen instead:

- `RootPaletteView` mirrors the open state into `PaletteState.menuOpen`, whose `didSet` fires
  `onMenuOpenChanged`.
- `PalettePanel.sendEvent` then swallows text-editing keystrokes while `menuOpen` (letting ⌘/⌃ chords
  and menu-nav keys through to SwiftUI `onKeyPress`), which is how ⌘. and ⌃X still reach their rows.
- The caret is hidden by clearing SwiftUI's **own** live field editor's `insertionPointColor`. SwiftUI
  force-casts its field editor to a private subclass, so vending a custom one crashes — only the
  existing one can be tuned.

## ↵ never commits the search field

Plain ↵ is claimed by `RootPaletteView`'s own `onKeyPress` whenever the search field holds focus, and
`activateSelection` runs from there — the field carries no `onSubmit`. Letting the field submit ends
editing, and AppKit tears the field editor down and selects the whole string when focus returns, so a
screen opened with a carried query (the Search Files fallback) came up with that query selected. An
IME's composition and any other focused field — the inline argument fields, an extension form — are
left alone: the handler returns `.ignored` for them, and their own `onSubmit` still commits.

## Chords `onKeyPress` never sees

Most ⌘/⌃ chords reach SwiftUI's `onKeyPress` fine. Three kinds do not, and all of them are handled in
`PalettePanel.sendEvent` before `super` hands the event to the responder chain:

- **A bare backspace** — the field editor consumes it as an edit (`onBareBackspace`).
- **Chords with no main menu item** — ⌘, and ⌘w, which an app with a menu bar would never see here.
- **The physical number-row slots.** `FavoriteSlots` matches ⌘1…⌘0 by key code before fixed command
  chords, then publishes the resolved position to the active screen. Only the launcher and clipboard
  screens intercept these slots; other screens keep their own ⌘-number shortcuts. The launcher's
  compact visibility setting is visual only and does not disable its favorite slots.
- **Chords AppKit has already bound to a selector.** `⌘.` is the one that bites: AppKit binds it to
  `cancelOperation:` alongside Escape, so `interpretKeyEvents` hands it to the field editor and
  `onKeyPress(keys: ["."])` never fires. Pin (⌘.) therefore arrives through `onCommandShortcut`,
  which bumps `PaletteState.pinChordToken`; `RootPaletteView` observes that and resolves the row
  through the current screen, so **which** row gets pinned still comes from `screen.rows` alone.

Adding a chord that "does nothing" is almost always one of these three — check `sendEvent` before
assuming the handler is wrong.

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

Character shortcut handlers accept every key so SwiftUI still calls them when the active input
source produces a non-ASCII character. Inside the callback, `ASCIIKeyboardLayout` resolves
`NSApp.currentEvent.keyCode` through the current ASCII-capable layout before comparing the shortcut.
Panel-owned chords use the same translation directly. A ⌘ chord translates through the layout's own
Command table, so "Dvorak – QWERTY ⌘" keeps giving QWERTY positions while Command is held; a ⌃ chord
translates without it, since only Command is remapped. A non-ASCII input source or IME therefore
cannot turn ⌘K into a different logical key, while Dvorak and other ASCII layouts keep their own
letter positions. No replacement event is synthesized, and unmodified typing stays on the active
input source and follows the normal composition path.

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
