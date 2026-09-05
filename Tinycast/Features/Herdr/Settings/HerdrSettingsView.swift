import SwiftUI

/// herdr's own pane. See docs/features/herdr.md — the socket is local, so there is no consent gate.
struct HerdrSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HerdrStore.self) private var store

    var body: some View {
        @Bindable var settings = settings
        return Form {
            LauncherItemsSection(
                kind: .herdrTarget,
                anchor: .herdrHerdr,
                searchPrompt: "Search herdr targets…")

            FeatureSwitchSection(
                anchor: .herdrHerdr,
                enableTitle: "Enable herdr",
                enableSubtitle:
                    "Lists the tabs of the running herdr session, read over its local socket. "
                    + "↵ focuses one and brings its terminal forward.",
                launcherSubtitle: "Find herdr tabs in launcher search.",
                isEnabled: $settings.herdrEnabled,
                showsInLauncher: $settings.herdrShowInLauncher)

            Section {
                LabeledContent("Tabs", value: "\(store.targets.count)")
                LabeledContent("Command line") {
                    Text(store.isAvailable ? "Found" : "Not found")
                        .foregroundStyle(store.isAvailable ? .secondary : Theme.Colors.destructive)
                }
            } footer: {
                Text(
                    store.isAvailable
                        ? "Refreshed each time the palette opens."
                        : "Install herdr, or put it on the default path, and reopen this pane."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.herdrEnabled)

            Section {
                TextField(
                    "Terminal bundle ID",
                    text: Binding(
                        get: { settings.herdrTerminalBundleID ?? "" },
                        set: { settings.herdrTerminalBundleID = $0.isEmpty ? nil : $0 }),
                    prompt: Text("Detected automatically"))
            } footer: {
                Text(
                    "Which app to bring forward after focusing. Left blank, Tinycast follows the "
                    + "herdr process up to whichever app owns it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.herdrEnabled)

            ScopeKeywordSection(
                scopeID: ScopeCatalog.herdr,
                explanation:
                    "Type it, then a space, to search herdr tabs only.")
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.herdr)
        .task { await store.refresh() }
    }
}
