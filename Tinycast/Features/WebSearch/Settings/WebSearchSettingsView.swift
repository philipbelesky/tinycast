import SwiftUI

/// The engines and their keywords. One switch here *is* a network switch — suggestions send what
/// you type. See docs/features/web-search.md#suggestions.
struct WebSearchSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppCore.self) private var core
    private var store: SearchSuggestionStore { core.searchSuggestions }

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
                Toggle(
                    isOn: Binding(get: { store.isEnabled }, set: { store.setEnabled($0) })
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
    }

    private var suggestionStatus: String {
        store.isEnabled
            ? "On. Each keystroke in a search scope is sent to that engine."
            : "Off. Nothing you type leaves the machine."
    }
}
