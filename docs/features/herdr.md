# herdr

herdr is a "terminal workspace manager for AI coding agents", driven by a CLI over a local unix socket.
`h payments` lists its workspaces and tabs; ↵ focuses one and brings the terminal hosting it forward.
Rows also appear in the unscoped root search, like quicklinks.

## Invariants

- **Absence is never an error.** No binary, no running session, or a non-zero exit publishes an empty
  slice: no rows, no HUD, no dialog. `Settings → herdr` is the only surface that says herdr wasn't
  found, because that is the only place a user asked about it.
- **`Model/HerdrTarget.swift` and `Model/HerdrHost.swift` are Foundation-only and pure**, so
  `herdr-test` compiles the shipped parser and the shipped ancestry walk. Parsing is the whole risk
  surface here and it takes its two JSON payloads as parameters.
- **A herdr id is opaque.** A tab's is `w2:tS` — it contains the separator, so it is never split on
  `:`. Only `HerdrTarget.entryIDPrefix` is added and removed.
- **An unrecognised `agent_status` degrades to `.unknown`, never drops the row.** herdr adds statuses
  faster than this app tracks them, and a missing workspace is worse than a missing badge.
- **This feature reads a local socket and never the network**, which is why it ships on with no consent
  dialog ([decisions.md](../decisions.md) entries 10, 11). All three of its settings are carried in a
  backup: focusing a terminal grants no permission class, so none is a consent flag.
- **`focus` is not `reveal`.** herdr's `focus` moves its own internal focus and raises nothing;
  bringing the host app forward is a separate, independently-failing step.

## How a target is reached

```
palette opens → PaletteCoordinator.onShow → HerdrCoordinator.refresh
                                                   ↓
              HerdrClient.snapshot — `workspace list` + `tab list`, off-main, ~5 ms
                                                   ↓
                    HerdrTarget.parse → HerdrStore.targets → AppIndex.setHerdrTargets
                                                   ↓
   ↵ → HerdrCoordinator.focus → `workspace focus` / `tab focus` → revealHost → AppLauncher.launch
```

The refresh rides the palette's existing re-scan trigger in `PaletteCoordinator.showPalette` — a herdr
session moves far faster than the app list does, and 5 ms of socket round trip belongs there rather
than on a keystroke. `HerdrStore` collapses a burst, so re-showing the palette mid-refresh is free.

Focus runs before the reveal. The reverse order raises a window that then visibly jumps to another
workspace.

## Finding the binary, and finding the host

A GUI app inherits none of a login shell's `PATH`, so `HerdrClient` looks by hand:
`/opt/homebrew/bin/herdr`, `/usr/local/bin/herdr`, `~/.local/bin/herdr`, then one `zsh -lc
'command -v herdr'` as a fallback. Resolved once per launch.

The host terminal is found by walking `ppid` from a running `herdr` process to its first ancestor that
AppKit knows as a running application — here `herdr` → `zsh` → `login` → `Ghostty.app`. Clients are
tried newest first, because a detached one can outlive the window it was started from, and an ssh or
mosh client has no local app at all: no host is a normal outcome, and focus still moved.

**That walk is why `ProcessTable` uses `sysctl(KERN_PROC_ALL)` rather than `libproc`.** `proc_pidinfo`
returns EPERM for a process the caller does not own, and every terminal's ancestry runs through
root-owned `login`, so the chain breaks two hops short of the app. Do not "simplify" it back.

`Settings → herdr` has a bundle-id override, which wins outright: detection is a convenience, not an
authority.

## What is listed

Workspaces always. A tab only when its workspace has more than one — a lone tab is the same
destination as its workspace row, so it earns no row of its own. A tab reads `meta › mic-fix`; its
trailing label is its kind, and `focused` plus any non-idle agent status ride in `matchAliases` so
"working" finds them.

## Not here

Panes, agents, prompting or starting an agent, creating workspaces and worktrees, named or remote
sessions (`herdr --session`), and a `HotKeyAction` bound to a target. The last one needs the pruning
story quicklinks have, since a persisted workspace id can vanish between launches.
