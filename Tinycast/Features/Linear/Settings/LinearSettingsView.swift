import SwiftUI

/// Linear's own pane. The only networked feature besides currency, so it wears the same consent
/// gate — see docs/features/linear.md#consent.
struct LinearSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    private var store: LinearViewStore { core.linear }
    @State private var askingConsent = false
    @State private var refreshing = false

    var body: some View {
        @Bindable var settings = settings
        return Form {
            LauncherItemsSection(
                kind: .linearView,
                header: "Linear",
                searchPrompt: "Search views…")

            Section {
                // Not bound to the flag: flipping on opens the sheet, so it springs back.
                Toggle(
                    isOn: Binding(
                        get: { store.isEnabled },
                        set: { wantsOn in
                            if wantsOn { askingConsent = true } else { store.setEnabled(false) }
                        })
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
        .sheet(isPresented: $askingConsent) {
            LinearConsentSheet(
                workspaces: store.workspaceCount,
                onCancel: { askingConsent = false },
                onAccept: {
                    askingConsent = false
                    store.setEnabled(true)
                })
        }
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
        return "\(store.views.count) views, last read \(refreshed.formatted(.relative(presentation: .named)))."
    }
}

private struct LinearConsentSheet: View {
    let workspaces: Int
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "network")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.green)
                Text("Turn on Linear views?")
                    .font(.headline)
            }

            Text(
                "Tinycast asks \(LinearViewStore.provider) for the names of your saved views, at "
                + "most every six hours and only when you open the palette. It goes through the "
                + "linear command line tool, so this app never sees your API token — the request "
                + "covers \(workspaces == 1 ? "the workspace" : "the \(workspaces) workspaces") "
                + "that tool is logged in to. No issue contents are read, and nothing you type is "
                + "sent. Turning it off deletes the cached list."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Link(destination: LinearViewStore.providerURL) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(LinearViewStore.providerURL.host() ?? "Provider")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.callout)
                }
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
