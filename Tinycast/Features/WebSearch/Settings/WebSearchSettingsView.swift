import SwiftUI

/// The engines and their keywords. Nothing here is a network switch — see
/// docs/features/web-search.md: a search opens in the browser, the app never fetches.
struct WebSearchSettingsView: View {
    @Environment(AppSettings.self) private var settings

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
}
