import SwiftUI

/// The engines and their keywords. One switch here *is* a network switch — suggestions send what
/// you type, so they wear the consent gate. See docs/features/web-search.md#suggestions.
struct WebSearchSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppCore.self) private var core
    private var store: SearchSuggestionStore { core.searchSuggestions }
    @State private var askingConsent = false

    var body: some View {
        @Bindable var settings = settings
        return Form {
            LauncherItemsSection(
                kind: .webSearch,
                header: "Web Search",
                searchPrompt: "Search engines…")

            FeatureSwitchSection(
                header: "Web Search",
                enableTitle: "Enable web search",
                enableSubtitle:
                    "Type an engine's keyword, a space, then your query. The search opens in your "
                    + "default browser; Tinycast never sends it anywhere itself.",
                launcherSubtitle: "Find the engines in launcher search.",
                isEnabled: $settings.webSearchEnabled,
                showsInLauncher: $settings.webSearchShowInLauncher)

            Section {
                Picker("Default engine", selection: $settings.webSearchEngine) {
                    ForEach(WebSearchEngine.builtIn) { engine in
                        Text(engine.name).tag(engine)
                    }
                }
            } footer: {
                Text("Used by the “Search the Web” row; every engine keeps its own keyword.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.webSearchEnabled)

            Section {
                // Not bound to the flag: flipping on opens the sheet, so it springs back.
                Toggle(
                    isOn: Binding(
                        get: { store.isEnabled },
                        set: { wantsOn in
                            if wantsOn { askingConsent = true } else { store.setEnabled(false) }
                        })
                ) {
                    Text("Search suggestions")
                    Text(suggestionStatus)
                }
            } header: {
                Text("Suggestions")
            } footer: {
                Text(
                    "This is the one thing Tinycast sends as you type. Nothing is stored: no cache, "
                        + "no cookies, and no query is ever written to disk."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.webSearchEnabled)

            Section {
                ForEach(WebSearchEngine.builtIn) { engine in
                    ScopeKeywordField(
                        scopeID: ScopeCatalog.scope(for: engine, settings: settings).id,
                        title: engine.name)
                }
            } header: {
                Text("Keywords")
            } footer: {
                Text(
                    "Type an engine's keyword, then a space, to send the rest of the query to it. "
                    + "Clear a field to leave that engine with no keyword."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.webSearchEnabled)
        }
        .formStyle(.grouped)
        .sheet(isPresented: $askingConsent) {
            SuggestionConsentSheet(
                onCancel: { askingConsent = false },
                onAccept: {
                    askingConsent = false
                    store.setEnabled(true)
                })
        }
    }

    private var suggestionStatus: String {
        store.isEnabled
            ? "On. Each keystroke in a search scope is sent to that engine."
            : "Off. Nothing you type leaves the machine."
    }
}

/// The one dialog in the app that has to say "what you type", rather than "once a day".
private struct SuggestionConsentSheet: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "network")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.green)
                Text("Turn on search suggestions?")
                    .font(.headline)
            }

            Text(
                "While a search scope is armed, Tinycast will send what you are typing to that "
                    + "engine's suggestion endpoint — Google, DuckDuckGo, Bing or Kagi, whichever "
                    + "the scope is for — about a fifth of a second after you stop typing, and once "
                    + "per query rather than per letter. Nothing else is sent, and nothing is kept: "
                    + "the requests carry no cookies, and no query is written to disk. Typing "
                    + "anywhere else in the palette sends nothing at all."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Spacer()
                Button("Not Now", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Enable", action: onAccept)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 420)
    }
}
