# VS Code projects

`p payments` lists the folders and workspaces VS Code has opened, most recent first; ↵ opens one in VS
Code. Rows also appear in the unscoped root search, like quicklinks.

## Invariants

- **`Model/VSCodeProject.swift` is Foundation-only and pure**, so `vscode-test` compiles the shipped
  parser. It takes the home directory *and* an `exists` predicate as parameters: whether a folder is
  still on disk is an environment fact, and the model may not go and look.
- **A project that has been deleted or unmounted is dropped, not shown greyed.** VS Code's record is
  append-only in practice — ten of the thirty-two entries on the author's machine name folders that no
  longer exist — so pruning is the normal path, not an error case.
- **The order is recency, and the launcher preserves it.** `setVSCodeProjects` publishes the slice as
  given rather than sorting by name; the whole point of the feature is that what you worked on
  yesterday is near the top.
- **Nothing here writes to VS Code's storage**, and nothing here parses `state.vscdb` — see below.
- **This feature reads local files and never the network**, which is why it ships on with no consent
  dialog ([decisions.md](../decisions.md) entries 10, 11). Both of its settings are carried in a
  backup: opening an editor grants no permission class, so neither is a consent flag.

## Where the list comes from

```
~/Library/Application Support/Code/User/workspaceStorage/
    <hash>/workspace.json   →  {"folder":    "file:///Users/philip/Sites/aical"}
    <hash>/workspace.json   →  {"workspace": "file:///…/agent-sessions.code-workspace"}
    <hash>/                 →  no workspace.json at all: an empty window
```

One directory per window VS Code has ever opened. The directory's **own modification time** is the
recency signal — VS Code keeps rewriting state beside `workspace.json`, which itself never changes
after it is created.

**The obvious source is the wrong one.** Raycast's VS Code extension reads the key
`history.recentlyOpenedPathsList` out of `globalStorage/state.vscdb`; on a current VS Code that key
holds `{"entries":[]}`, so a faithful port of that design lists nothing. Reading it would also mean
linking SQLite to parse a database VS Code holds open. `workspaceStorage` is plain JSON, needs no
library, and is the only source here that actually carries data.

A URI that isn't a `file://` one — an SSH or container remote, a virtual filesystem — is dropped,
because there is no local path to hand to VS Code.

## How a project opens

```
palette opens → PaletteCoordinator.onShow → VSCodeCoordinator.refresh
                                                   ↓
        VSCodeProjectScanner.scan — read the directory off-main, prune what's gone
                                                   ↓
              VSCodeProject.parse → VSCodeStore.projects → AppIndex.setVSCodeProjects
                                                   ↓
            ↵ → VSCodeCoordinator.open → NSWorkspace.open(_:withApplicationAt:)
```

Opening goes through `NSWorkspace`, not the `code` CLI: a GUI app inherits none of a login shell's
`PATH`, and the shell wrapper only ends up calling the same app anyway.

A row's icon is the real file icon rather than an SF Symbol, so a folder and a `.code-workspace` look
as different in the palette as they do in Finder, and **⌘↵ reveals the project in Finder** like any
other file-backed entry.

## What a row reads

The last path component, with `.code-workspace` stripped from a workspace. The containing directory
rides alongside as a match alias — `~/Sites` — so a query naming the parent finds the projects under
it, and so two folders called `src` can be told apart.

## Not here

Opening a *file* rather than a project, VS Code Insiders, Cursor and the other forks, the Project
Manager extension's own project list, and a `HotKeyAction` bound to a project. The last one needs the
pruning story quicklinks have, since a path can vanish between launches — as ten of them already have.
