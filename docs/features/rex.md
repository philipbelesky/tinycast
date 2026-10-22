# Rex

[Rex](https://www.superlogical.com/rex/docs) is a terminal multiplexer whose sessions live in a local server, driven by a CLI over a unix socket. `r payments` lists the tabs of every Rex session; ↵ shows one in the Rex app and brings it forward. Rows also appear in the unscoped root search, like herdr's.

## Invariants

- **Absence is never an error.** No binary, no running server, no local app, or a non-zero exit publishes an empty slice: no rows, no HUD, no dialog. `Settings → Rex` is the only surface that says the command line wasn't found.
- **Tinycast never starts the Rex server.** Every call passes `--autostart=false`; without it, opening the palette would launch a server the user had stopped.
- **`Model/RexTarget.swift` and `Model/RexSnapshot.swift` are Foundation-only and pure**, so `rex-test` compiles the shipped parser. The payload is the reply of `RexClient.snapshotScript`, so a change to the script's shape is a change to the harness fixture.
- **A Rex id is opaque.** A tab's is `window:01a1…`; it contains the separator, so it is never split on `:`. Only `RexTarget.entryIDPrefix` is added and removed.
- **An unrecognised status is dropped, never guessed at.** Rex itself ignores a report whose state it doesn't know, so a state Tinycast doesn't know means nothing more than "no status".
- **This feature reads a local socket and never the network**, so nothing here is gated ([AGENTS.md](../../AGENTS.md#non-negotiables)). Both settings are carried in a backup.

## How a target is reached

```
palette opens → PaletteCoordinator.onShow → RexCoordinator.refresh
                                                  ↓
     RexClient.snapshot — one `rex do -e <snapshotScript>`, off-main, ~25 ms
                                                  ↓
              RexSnapshot.parse → RexStore.targets + host → AppIndex.setRexTargets
                                                  ↓
↵ → RexCoordinator.focus → `rex -C <host> do session.select` → RexClient.reveal
```

One Lua script reads everything in one process: `session.list`, then each session's view, each terminal pane's title and `program_status`, and `client.list`. `session.view` refuses a caller that isn't attached, so the script attaches to each session; the attachment ends with the script. Several `rex` invocations would cost a process each, which is ten times the round trip on a machine with ten sessions.

The tab is selected before the app is raised, for the same reason as herdr: the reverse order raises a window that then visibly jumps.

## Finding the binary, and finding the host

`RexClient.locate` goes through `ExecutableLocator`, which asks the login shell first, with Rex's own copy inside its server bundle (`~/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/…/rex`) as a fallback. The lookup runs once per launch.

Unlike herdr, the host needs no process-tree walk. Rex's `client.list` names every connected client with its kind, transport and pid, so the host is the newest `app` client on the `unix` transport. A remote Rex app, on another Mac over Tailscale, has no window here and is skipped; so is the CLI, which shares the app's pid. `session.select` is a client action, so `rex -C <client_id> do session.select session_id=… window_id=…` makes that app show the tab, and `NSRunningApplication(processIdentifier:)` gives the bundle to raise.

No local app means no host. The tabs still list, because they are real, but ↵ does nothing.

## What is listed

Tabs, and only tabs, in the server's order. A session earns no row of its own, for the same reason a herdr workspace doesn't: it is the same destination as its active tab.

A row reads `terminal4 - main › Branch code review`: the session's label, then the tab's. A tab someone named keeps its name. Rex labels an unnamed tab `Window` plus eight hex digits of its id, which says nothing, so that placeholder gives way to the title of the tab's focused pane (which is how Claude Code's and Codex's session titles reach the row). A session with a blank label is dropped rather than shown unprefixed.

Status comes from Rex's [program status protocol](https://www.superlogical.com/rex/docs/build/program-status): every record across the tab's terminal panes, merged to the one that most needs the user (`blocked` › `error` › `done` › `working` › `idle`). A tab where nothing reports has no status, which is most shells. A non-idle status and `active` (the session's active tab) ride in `alternateTitles`, so "blocked" finds them.

## Not here

Panes, creating sessions or tabs, restoring sessions, remote Rex servers (`rex.host`), launching the Rex app when it isn't running, and a `HotKeyAction` bound to a target, which needs the same pruning story herdr's would.
