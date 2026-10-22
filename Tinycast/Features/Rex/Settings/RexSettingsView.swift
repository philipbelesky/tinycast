import SwiftUI

/// Rex's own pane. See docs/features/rex.md — the socket is local, so there is no consent gate.
struct RexSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RexStore.self) private var store

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .rexRex,
                enableTitle: "Enable Rex",
                enableSubtitle:
                    "Lists the tabs of every session on the local Rex server, read over its socket. "
                    + "↵ shows one in the Rex app and brings it forward.",
                isEnabled: $settings.rexEnabled,
                showsInLauncher: $settings.rexShowInLauncher)

            LauncherItemsSection(
                kind: .rexTarget,
                anchor: .rexTabs,
                searchPrompt: "Search Rex tabs…")

            Section {
                LabeledContent("Tabs", value: "\(store.targets.count)")
                LabeledContent("Command line") {
                    Text(store.isAvailable ? "Found" : "Not found")
                        .foregroundStyle(store.isAvailable ? .secondary : Theme.Colors.destructive)
                }
            } footer: {
                Text(
                    store.isAvailable
                        ? "Refreshed each time the palette opens. Tinycast never starts the Rex server."
                        : "Install Rex, or put its rex command on your shell's PATH, and reopen this pane."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.rexEnabled)

            ScopeKeywordSection(
                scopeID: ScopeCatalog.rex,
                explanation:
                    "Type it, then a space, to search Rex tabs only.")
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.rex)
        .task { await store.refresh() }
    }
}
