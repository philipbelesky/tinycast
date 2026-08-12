import SwiftUI

/// Linear's own pane. See docs/features/linear.md#the-switch-and-the-cadence.
struct LinearSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    private var store: LinearStore { core.linear }
    @State private var refreshing = false

    var body: some View {
        @Bindable var settings = settings
        return Form {
            LauncherItemsSection(
                kind: .linearTarget,
                header: "Linear",
                searchPrompt: "Search views…")

            Section {
                Toggle(
                    isOn: Binding(get: { store.isEnabled }, set: { store.setEnabled($0) })
                ) {
                    Text("Enable Linear views")
                    Text(status)
                }
                Toggle(isOn: $settings.linearShowInLauncher) {
                    Text("Show in launcher")
                    Text("Find your views in launcher search.")
                }
                .settingsEnabled(store.isEnabled)
            } header: {
                Text("Linear")
            }

            Section {
                Picker("Open views in", selection: $settings.linearDestination) {
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
                            await store.refresh(force: true)
                            refreshing = false
                        }
                    }
                    .disabled(refreshing)
                } label: {
                    Text("Views")
                    Text(viewsStatus)
                }
            } footer: {
                Text(
                    "Views are re-read at most every six hours, and only when you open the palette. "
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
                    "Type it, then a space, to search Linear views only.")
        }
        .formStyle(.grouped)
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
