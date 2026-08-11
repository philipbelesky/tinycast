# Web search

`g swift actors` opens a Google search in the default browser. Four engines ship — Google,
DuckDuckGo, Bing, Kagi — each with its own scope keyword.

## Invariants

- **Searching never fetches.** A search is a URL handed to `NSWorkspace.shared.open`; the query leaves
  the machine only because the *browser* sends it. That is why the feature itself ships **on** and its
  engines, keywords and default carry no consent dialog.
- **Suggestions do fetch, and are a separate switch that ships off.** `SearchSuggestionStore` is the
  only thing in the app that sends what the user is *typing*, so it wears the consent shape
  ([decisions.md](../decisions.md) entries 10, 11, 35) — flag on the store, dialog naming the provider
  and the cadence, ephemeral session. Turning web search on does not turn suggestions on.
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

## Suggestions

With the scope armed, the engine is asked what the query might become, and each answer is a row under
the verbatim search:

```
scope armed, query typed → RootPaletteView.refreshSuggestions
                                    ↓
        SearchSuggestionStore.update — cancels whatever was in flight, waits 200ms
                                    ↓
     engine.suggestURL (https only) → ephemeral session → SearchSuggestions.parse
                                    ↓
      LauncherScreen rows = [.webSearch(engine)] + suggestions.map(Row.suggestion)
```

All four engines answer in the same OpenSearch shape, `["typed", ["first", "second", …], …]`, so one
parser covers them: `suggestqueries.google.com`, `duckduckgo.com/ac`, `api.bing.com/osjson.aspx`,
`kagi.com/api/autosuggest`.

**What holds it in place.**

- **The consent flag lives on the store**, under `searchSuggestionsEnabled`, never in `AppSettings` —
  so importing a settings backup cannot start a keystroke feed ([decisions.md](../decisions.md) entry 8).
- **Nothing is persisted, ever.** No disk cache, no cookies (`httpShouldSetCookies = false`), no
  `URLSession.shared`. A query exists in memory for as long as its row is on screen. This is stricter
  than `CurrencyRateStore`, which does keep its snapshot, and deliberately so: a rate table is public
  data, a query is the user's.
- **One request per pause, not per letter.** A 200ms debounce, and the previous request is cancelled,
  so what is on screen always answers the newest keystroke.
- **`suggestURL` refuses anything but https**, unlike `url(for:context:)` which allows http: an opened
  link is the user's own browser request, whereas this is the app posting what they typed.
- **A reply is never trusted.** `SearchSuggestions.parse` is total — malformed JSON, non-string
  elements, control characters, anything over 120 characters and more than `limit` rows are all
  dropped rather than raised, and the suggestion identical to what was typed goes too, since the row
  above already searches for it.
- **`SearchSuggestions.rowID` is shared** by the screen that indexes rows and the list that draws them.
  Two spellings of it would put the selection highlight on a different row than the one ↵ activates.

Activating a suggestion searches for **the suggestion**, not for whatever is still in the field.

## Settings

`Settings → Web Search`: enable, show-in-launcher, the default engine, a field per engine for its
[scope keyword](palette.md#choosing-your-own), and the suggestions switch. Everything but that switch
is carried in a settings backup: opening a link grants no permission class, so none of those is a
consent flag ([decisions.md](../decisions.md) entry 8). The suggestions flag is not in `AppSettings`
at all, so there is nothing for a backup to carry.

An engine id that no longer resolves — a renamed or dropped engine, a backup from a later build —
falls back to Google rather than leaving the scope dead.

## Not here

User-authored engines and per-engine hotkeys are deliberately absent; both are additive, and neither
has been needed yet. A user-authored *suggest* endpoint would not be additive — it would let a backup
name where keystrokes go — so if custom engines ever land, their suggest template stays ours.
