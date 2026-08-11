# Web search

`g swift actors` opens a Google search in the default browser. Four engines ship — Google,
DuckDuckGo, Bing, Kagi — each with its own scope keyword.

## Invariants

- **Nothing here fetches.** A search is a URL handed to `NSWorkspace.shared.open`; the query leaves
  the machine only because the *browser* sends it. That is why this feature ships **on** and carries
  no consent dialog, unlike `CurrencyRateStore` ([decisions.md](../decisions.md) entries 10, 11).
  **Search suggestions would change that** — a suggest endpoint is a fetch, keystroke by keystroke, and
  would need the full consent shape before a single request. Do not add one casually.
- **`Model/WebSearchEngine.swift` is Foundation-only and pure**, so `websearch-test` compiles the
  shipped URL builder. It takes its `ExpansionContext` as a parameter rather than reading the clock.
- **There is one template engine.** A template expands through `SnippetTemplateEngine` with
  `.percentEncoding` ([decisions.md](../decisions.md) entry 15), which is what stops a query containing
  `&` or `/` from adding a parameter or escaping the path — `websearch-test` pins exactly that.
- **`url(for:context:)` returns nil rather than a blank search.** An empty query, a template that lost
  its `{argument}`, or a result that isn't an absolute `http(s)` URL are all "nothing to open". The
  scoped row stays visible and unactionable instead, so ↵ on an empty `g` does nothing.

## How a search happens

```
"g" + space → QueryScope.adopting → PaletteState.scope = Google
                                          ↓
                        LauncherScreen resolves the scope to .webSearch(engine)
                                          ↓
                  rows = [.webSearch(engine)] — the list is replaced, not filtered
                                          ↓
        ↵ → WebSearchCoordinator.search → SnippetTemplateEngine → NSWorkspace.open
```

Each engine also publishes as an `AppEntry` of kind `.webSearch`, so typing "google" finds it by name.
Activating that row **arms its scope** rather than opening anything: the palette stays up with the chip
showing, waiting for a query — the same state its keyword would have reached. That is why it is handled
before `hidePalette` in `LauncherCoordinator.launch`, next to quicklinks.

Because a template is expanded, not just interpolated, an engine may use `{clipboard}` or `{date}` as
well as `{argument}`; the coordinator captures the context per search for exactly that reason.

## Settings

`Settings → Web Search`: enable, show-in-launcher, the default engine, and a field per engine for its
[scope keyword](palette.md#choosing-your-own). All of them are carried in a settings backup: opening a
link grants no permission class, so none is a consent flag ([decisions.md](../decisions.md) entry 8).

An engine id that no longer resolves — a renamed or dropped engine, a backup from a later build —
falls back to Google rather than leaving the scope dead.

## Not here

User-authored engines, per-engine hotkeys and search suggestions are all deliberately absent. The first
two are additive; the third is not, and would need the consent shape above.
