# Task capture

`o Buy milk @Groceries #errands due fri 5pm !` writes a task into OmniFocus; `t` does the same into TextFlow. While either keyword is armed the launcher stops being a search: the list becomes a preview card of the task as it will be stored — one chip per attribute — with project and tag completions from the destination app beneath it. ↵ adds the task and the palette closes without bringing the app forward.

## Invariants

- **`Model/` is Foundation-only and pure**, so `task-capture-test` compiles the shipped grammar, date parser, TaskPaper formatter, TextFlow argument builder and both catalog parsers. Every one of them takes the clock and calendar as parameters; nothing in `Model/` reads a date, a file or a process.
- **One grammar, two destinations.** The query is parsed the same way whichever keyword is armed. A destination declares which fields it can keep; the preview strikes through the rest and the sinks drop them. A field is never silently rewritten into something the destination does keep.
- **What the card shows is what is sent.** The preview and the sink are built from the same parsed task. A date phrase the parser could not read is shown as unreadable and is not sent, rather than being guessed at or passed through as text. A project that a loaded catalog does not know is flagged the same way and the task goes to the inbox instead — OmniFocus answers an unknown paste target by creating a project named after the URL path, which is what a typo must never do. With no catalog loaded the project is taken on trust.
- **The palette hides before the add runs, and the add never activates the target app.** OmniFocus receives a URL opened without activation; TextFlow is driven by its command line, and if it has to be launched it is launched in the background. A capture is a side effect on the app the user was in, not a switch to another.
- **Catalogs are read from the apps and never persisted.** Projects and tags exist only to complete what is being typed. They are re-read on the palette's own trigger (TextFlow) or when the scope is armed (OmniFocus), and are never backed up, synced or ranked.
- **OmniFocus is only read with consent, in context.** Reading its projects and tags sends Apple events, which macOS gates behind an Automation prompt. Tinycast issues that read only after the `o` scope is armed and only while the suggestions switch is on; adding a task never needs it, because the paste link is a URL, not an event.
- **Both switches live in `AppSettings` and are backed up.** Neither destination touches the network: OmniFocus is a local URL scheme and TextFlow a local process. The Automation grant is the only permission class involved and the OS owns it.

## The grammar

Everything that is not a marker is the title. Markers can appear in any order, and the first `@Name` wins as the project.

| Written | Field |
| --- | --- |
| `@Groceries`, `@"Home Renovation"` | project — quoted when it has spaces |
| `#errands`, `#"Home : Kitchen"` | tag, repeatable |
| `due fri 5pm` | due date, the phrase up to the next marker |
| `defer +1w` | defer date |
| `!` | flagged |
| `~30m`, `~1h30m` | estimate (OmniFocus only) |
| `/inprogress`, `/hold` | status (TextFlow only) |
| `>Name` | assignee (TextFlow only) |
| `// text` | note — everything after it |

TaskPaper's own attribute form is accepted too — `@due(fri 5pm)`, `@defer(+2d)`, `@tags(a, b)`, `@flagged`, `@estimate(45m)`, `@project(Groceries)`, `@note(…)`, `@status(onhold)`, `@assignee(Sam)` — so a line copied from a TaskPaper document captures unchanged.

A `due`/`defer` keyword consumes the words up to the next marker and takes the longest readable head (at most three words) as the date; the rest returns to the title. A phrase with no readable head is kept as unresolved so the card can say so.

## Dates

Relative: `today`/`tod`, `tomorrow`/`tom`/`tmr`, a weekday name (the next one, `next fri` for the one after), `+3d`/`+2w`/`+1m`/`+1y`. Absolute: `2026-09-18`, `18/9`, `18/9/2026` (day first, rolling to next year when past), `18 sep`, `sep 18`. A clock — `5pm`, `5:30pm`, `17:00`, `noon`, `midnight`, optionally after `at` — may follow any of them and marks the date as having a time. A lone number is not a date, so `due 5` stays in the title.

## OmniFocus

The task becomes one TaskPaper line — `- title @due(…) @defer(…) @flagged @tags(a, b) @estimate(30m)` with tab-indented note lines — and is sent to `omnifocus:///paste` targeting the inbox, or `/task/<Project>` when a project is named. OmniFocus resolves the date phrases itself from the canonical `yyyy-MM-dd HH:mm` form. The URL is opened with activation off, so OmniFocus takes the task without coming forward, and it need not already be running.

Completions come from a JavaScript-for-Automation script run through the system script runner: active projects with their folder, and visible tags with their full `Parent : Child` path. An Automation refusal is remembered so the Settings pane can point at the System Settings switch; the next successful read clears it.

## TextFlow

The task is added through TextFlow's bundled command line — the helper inside the app bundle first, then anything named `textflow` on the default path. `add` takes project, note, tags, dates, flag and assignee directly and is asked for JSON with an assigned reference; a status is set by a second `status` call against that reference. The CLI needs the app running and says so with its own exit status; on that answer Tinycast launches TextFlow in the background and retries for a few seconds before reporting.

Projects and tags are read with the same CLI's JSON listings. Only active and on-hold projects are offered; a project name that repeats across folders completes to its folder path so the add is unambiguous.

## Completions

While the caret is inside an open `@` or `#` token the catalog is filtered against it: a prefix match on any path component leads, a substring match follows, eight at most. ↵ on a completion writes the value into the field — quoted if it has whitespace — and returns the selection to the card; it never adds the task. Everything else in the list is suppressed while a capture scope is armed: no calculator, colour, meeting or fallback rows.

## Data flow

```text
keystroke → TaskCaptureGrammar.parse → TaskCapturePreview → card + chips
                                     ↘ completionContext → catalog → completion rows
↵ on the card → palette hides → OmniFocus paste URL  |  textflow add (+ status)
                                                   ↘ HUD: "Added to … · project"
```
