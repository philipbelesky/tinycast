# Linear

The `l` scope combines cached Linear destinations with local ticket matching and live search across every workspace the `linear` CLI is logged in to. An empty or ordinary local query filters saved views, projects, initiatives and fixed workspace pages; a ticket query adds matching issues above those destinations. ↵ opens either kind of result in the Linear app or the browser.

Ticket query grammar is deliberately narrow:

- `861` finds that exact issue number across every team and workspace, including archived issues.
- `PC-861` finds that exact team key and issue number across every workspace, including archived issues.
- `claim editor` searches titles once the trimmed query is at least three characters and excludes archived issues.

## Invariants

- **This is a networked feature and it ships on** ([FORK.md](../../FORK.md) divergence 15). Its enable flag belongs to the Linear store, never general settings, so importing settings cannot turn the network on. Show-in-launcher and destination preferences can be backed up because neither can enable a request.
- **Tinycast never sees a Linear token.** Every request goes through the `linear` CLI, which holds credentials in the system keyring. Tinycast reads only the configured workspace slugs from the CLI's credentials file, and the parser ignores every other key.
- **A selected CLI workspace wins over an ambient API key.** Tinycast removes `LINEAR_API_KEY` from the otherwise-sanitised inherited subprocess environment. Without this, a developer shell's key makes `--workspace` fail or silently changes the identity being queried.
- **Disabling is structural.** A disabled store does not read the destination cache, publish rows or fetch. The flag is re-checked after every await, so disabling or leaving the scope while a request is running prevents that response from landing.
- **Ticket metadata is cached locally.** Each workspace retains at most 500 issue titles, identifiers, links, states and update/archive dates in the app channel’s cache directory. Queries are never persisted, and issue records never enter settings sync, backups or learned launcher ranking. Tickets cannot become favourites or hotkeys. Disabling Linear removes the cache; a changed CLI configuration or confirmed account identity clears the previous account’s records.
- **A result URL must belong to the workspace that answered.** Projects, initiatives and issues use Linear's returned URL because it contains a slug clients cannot safely reconstruct; a URL outside the answering workspace is dropped.
- **A target identity carries its workspace.** Two workspaces may contain identically named views or the same issue number, so identity includes the workspace URL key and destination path.
- **GraphQL errors live in successful CLI output.** Linear can answer HTTP 200 with an `errors` array, so the client checks both process status and response content. A failed destination refresh never replaces the last good disk cache.

## The switch and the two cadences

Sidebar destinations change rarely. Tinycast refreshes them at most every six hours and only when the palette opens, with one request per workspace. The last good list is cached on disk so relaunching does not require a request; disabling Linear deletes it.

Ticket matching is local first: a valid query immediately filters cached metadata with the same number, identifier and title rules as live search. A 200 ms debounce then starts requests to all configured workspaces concurrently. Each workspace publishes as soon as it answers, replacing its local matches; a slow or unavailable workspace cannot hold up the others. Results remain interleaved by workspace and capped at 24. Superseded requests cannot publish even if the user returns to the same query later.

The app restores the issue cache asynchronously after launch and refreshes stale workspaces every 30 minutes. Launch, wake and palette opening also check freshness; they do not refetch a snapshot younger than 30 minutes. Each workspace refresh fetches up to 500 recently updated non-archived issues in pages of 100. Only a successful complete snapshot replaces that workspace’s cache, reconciling deletions and lost access. Failed or cancelled pagination retains the last good snapshot. Live results also populate the bounded cache, making older tickets available locally after searching for them.

The cache records the organization and viewer identity returned by Linear. Changing the CLI configuration invalidates the cache immediately when observed; a response from a different account replaces that workspace’s previous metadata. Cached results can be stale while offline and expire after 24 hours without a successful snapshot. The CLI continues to own every credential. Writes run off-main and are serialized, so disabling during a write leaves no cache behind.

On with no CLI installed, or with no authenticated workspace, is inert rather than fatal. Settings reports the configuration problem and the launcher exposes no unusable scope.

## Data flow

```
palette opens → stale check → one sidebar query per workspace
                                      ↓
                 parse destinations → disk cache → launcher index

launch / wake / 30-minute timer → stale workspaces → paginated recent issues
                                                       ↓
                                             bounded local disk cache
                                                       ↓
Linear scope + valid query → immediate local matches + debounced live search
                                                       ↓
                                  each workspace reply replaces its local matches

destination or issue row → ↵ → selected Linear app/browser destination
```

## Opening: two URLs for one target

A target is a path under its workspace, and only the prefix differs:

```
browser   https://linear.app/philipb/view/c3f94e04a1e5
desktop   linear://linear.app/philipb/view/c3f94e04a1e5
```

**The desktop app declares no URL scheme.** It registers `linear://` at runtime, so LaunchServices knows the scheme only after Linear has run at least once on that Mac. Tinycast checks for a handler and falls back to the browser when there is none. Linear accepts the deep link without necessarily raising itself, so Tinycast activates it separately.

## Settings

`Settings → Linear` contains the network switch, show-in-launcher preference, destination picker, built-in-page toggle, destination refresh status and scope keyword. Its footer discloses the six-hour destination cadence and the half-hourly local ticket cache.

## Not here

Creating, editing or tracking issues; documents and teams; a complete offline workspace mirror; ticket favourites, hotkeys or learned ranking; and ticket lookup outside the explicit Linear scope.
