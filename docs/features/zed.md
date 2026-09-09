# Zed projects

`z payments` lists the local workspaces Zed has opened, most recent first; ↵ opens one in Zed. Rows
also appear in the unscoped root search, like quicklinks.

## Invariants

- **`Model/ZedProject.swift` is Foundation-only and pure**, so `zed-test` compiles the shipped parser. It receives the home directory and `exists` predicate: the model never reads the filesystem.
- **A workspace with a missing root is dropped whole.** Zed can reopen a multi-root workspace; opening only the surviving roots changes its shape, so pruning is preferable to a misleading partial row.
- **The order is recency, and the launcher preserves it.** `setZedProjects` publishes the slice as given rather than sorting it by name.
- **Nothing here writes to Zed's database.** The scanner opens the database read-only and only selects local workspaces; remote Zed connections are not reusable from another local launcher process.
- **This feature reads local files and never the network**, so its two settings are carried in a backup. Opening an editor grants no permission class.

## Where the list comes from

```text
~/Library/Application Support/Zed/db/0-stable/db.sqlite
    workspaces(paths, paths_order, timestamp, remote_connection_id)
```

Zed writes a local workspace's roots as newline-separated absolute paths. `paths_order` is a comma-separated sequence of indexes into that list, and is retained so a multi-root workspace opens with the same primary root Zed used. `timestamp` is the recency signal. Rows with a remote connection are excluded because their paths belong to a remote host.

Zed holds this database open, so the scanner uses SQLite's read-only connection and its normal WAL view rather than copying or modifying the database. An unavailable database is the same answer as no projects; the feature never reports an error or changes Zed's data.

## How a workspace opens

```text
palette opens → PaletteCoordinator.onShow → ZedCoordinator.refresh
                                                ↓
      ZedProjectScanner.scan — read Zed's database off-main, prune missing roots
                                                ↓
            ZedProject.parse → ZedStore.projects → AppIndex.setZedProjects
                                                ↓
         ↵ → ZedCoordinator.open → NSWorkspace.open(_:withApplicationAt:)
```

Opening uses `NSWorkspace`, rather than Zed's shell CLI: a GUI app does not inherit a login shell's `PATH`, and Zed's app bundle already owns the native document-open behavior. Every root is submitted in one request, which retains Zed's multi-root workspace. The first root supplies the Finder reveal target; ⌘↵ reveals it as for any other file-backed launcher entry.

## What a row reads

For a one-root workspace, the root's final path component and its containing directory. For a multi-root workspace, the ordered first root reads as `name + N`, and every root plus its parent is searchable, so a query can name any folder or file Zed restores with it.

## Not here

Zed Preview or nightly data channels, remote Zed connections, individual file search, manual project management, and project hotkeys. The local stable channel is the installed Zed app this feature opens; other channels must be deliberate additions with their own source and app target.
