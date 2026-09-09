import SwiftUI

/// Zed's own pane. See docs/features/zed.md — the scan is local, so there is no consent gate.
struct ZedSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ZedStore.self) private var store

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .zedZed,
                enableTitle: "Enable Zed Projects",
                enableSubtitle:
                    "Lists the workspaces Zed has opened, read from its own storage on disk. "
                    + "↵ opens one in Zed.",
                launcherSubtitle: "Find projects in launcher search.",
                isEnabled: $settings.zedEnabled,
                showsInLauncher: $settings.zedShowInLauncher)

            LauncherItemsSection(
                kind: .zedProject,
                anchor: .zedZed,
                searchPrompt: "Search projects…")

            Section {
                LabeledContent("Projects", value: "\(store.projects.count)")
                LabeledContent("Zed") {
                    Text(store.isInstalled ? "Found" : "Not found")
                        .foregroundStyle(store.isInstalled ? .secondary : Theme.Colors.destructive)
                }
            } footer: {
                Text(
                    store.isInstalled
                        ? "Refreshed each time the palette opens. A workspace with a deleted or "
                            + "unmounted root drops off the list."
                        : "Install Zed and reopen this pane."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.zedEnabled)

            ScopeKeywordSection(
                scopeID: ScopeCatalog.zed,
                explanation: "Type it, then a space, to search Zed projects only.")
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.zed)
        .task { await store.refresh() }
    }
}
