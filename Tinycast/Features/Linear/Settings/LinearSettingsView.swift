import SwiftUI

/// Linear's own pane. See docs/features/linear.md#the-switch-and-the-two-cadences.
struct LinearSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    private var store: LinearStore { core.linear }
    @State private var refreshing = false

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(
                    isOn: Binding(get: { store.isEnabled }, set: { store.setEnabled($0) })
                ) {
                    SettingsRowTitle(.linearLinear, "Enable Linear")
                    Text(status)
                }
                Toggle(isOn: $settings.linearShowInLauncher) {
                    Text("Show in launcher")
                    Text("Find views and tickets in the main launcher and Linear scope.")
                }
                .settingsEnabled(store.isEnabled)
            } header: {
                SettingsSectionHeader(.linearLinear)
            }

            LauncherItemsSection(
                kind: .linearTarget,
                anchor: .linearLinear,
                searchPrompt: "Search views…")

            Section {
                Picker("Open Linear in", selection: $settings.linearDestination) {
                    ForEach(LinearDestination.allCases) { destination in
                        Text(destination.title).tag(destination)
                    }
                }
                Toggle(isOn: Binding(
                    get: { store.includesBuiltIn }, set: { store.includesBuiltIn = $0 })
                ) {
                    Text("Include built-in views")
                    Text("Inbox, My Issues, Projects, Initiatives and Settings, per workspace.")
                }
                LabeledContent {
                    Button("Refresh Now") {
                        refreshing = true
                        Task {
                            store.issues.refreshIfStale(force: true)
                            await store.refresh(force: true)
                            refreshing = false
                        }
                    }
                    .disabled(refreshing)
                } label: {
                    Text("Views")
                    Text(viewsStatus)
                }
                LabeledContent("Cached tickets", value: "\(store.issues.cachedIssueCount)")
                if let error = store.issues.refreshError {
                    Text("Ticket refresh: " + error).foregroundStyle(.secondary)
                }
            } footer: {
                Text(
                    "Views are re-read at most every six hours, and only when you open the palette. "
                        + "Recent ticket titles, keys, states and links are cached on this Mac and "
                        + "refreshed every 30 minutes. Local matches appear immediately; after a short "
                        + "pause in the main launcher or Linear scope, your query is sent to each "
                        + "logged-in workspace for more results. "
                        + "Disabling Linear removes the cache; it is never synced or backed up. "
                        + "The Linear app has to have been launched once before it can answer a link; "
                        + "until then, choose Browser."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .settingsEnabled(store.isEnabled)

            ScopeKeywordSection(
                scopeID: ScopeCatalog.linear,
                explanation:
                    "Type it, then a space, to search Linear views and tickets.")
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.linear)
    }

    private var status: String {
        guard store.isAvailable else {
            return "The linear command line tool wasn't found. Install it, then reopen this pane."
        }
        guard store.isEnabled else { return "Off. Nothing is sent to Linear." }
        let count = store.workspaceCount
        return "On for \(count) \(count == 1 ? "workspace" : "workspaces")."
    }

    private var viewsStatus: String {
        if let lastError = store.lastError { return lastError }
        guard let refreshed = store.lastRefreshed else { return "Not fetched yet." }
        return "\(store.targets.count) views, last read \(refreshed.formatted(.relative(presentation: .named)))."
    }
}
