import SwiftUI

/// VS Code's own pane. See docs/features/vscode.md — the scan is local, so there is no consent gate.
struct VSCodeSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VSCodeStore.self) private var store

    var body: some View {
        @Bindable var settings = settings
        return Form {
            LauncherItemsSection(
                kind: .vsCodeProject,
                header: "VS Code",
                searchPrompt: "Search projects…")

            FeatureSwitchSection(
                header: "VS Code",
                enableTitle: "Enable VS Code Projects",
                enableSubtitle:
                    "Lists the folders and workspaces VS Code has opened, read from its own storage "
                    + "on disk. ↵ opens one in VS Code.",
                launcherSubtitle: "Find projects in launcher search.",
                isEnabled: $settings.vsCodeEnabled,
                showsInLauncher: $settings.vsCodeShowInLauncher)

            Section {
                LabeledContent("Projects", value: "\(store.projects.count)")
                LabeledContent("Visual Studio Code") {
                    Text(store.isInstalled ? "Found" : "Not found")
                        .foregroundStyle(store.isInstalled ? .secondary : Theme.Colors.destructive)
                }
            } footer: {
                Text(
                    store.isInstalled
                        ? "Refreshed each time the palette opens. A project whose folder has been "
                            + "deleted or unmounted drops off the list."
                        : "Install Visual Studio Code and reopen this pane."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.vsCodeEnabled)
        }
        .formStyle(.grouped)
        .task { await store.refresh() }
    }
}
