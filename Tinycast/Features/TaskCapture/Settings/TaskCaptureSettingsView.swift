import SwiftUI

/// Task Capture's own pane: one switch per destination. See docs/features/task-capture.md.
struct TaskCaptureSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(TaskCaptureIndex.self) private var index
    @State private var refreshing: Set<TaskCaptureDestination> = []

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.taskCaptureOmniFocusEnabled) {
                    SettingsRowTitle(.taskCaptureOmniFocus, "Enable OmniFocus")
                    Text(availability(.omniFocus, installedHint: "Install OmniFocus 4 to capture into it."))
                }
                Toggle(isOn: $settings.taskCaptureOmniFocusSuggestions) {
                    Text("Suggest projects and tags")
                    Text(omniFocusSuggestionsStatus)
                }
                .settingsEnabled(settings.taskCaptureOmniFocusEnabled)
                if index.omniFocusAutomationDenied {
                    LabeledContent {
                        Button("Open System Settings", action: Permissions.openAutomationSettings)
                    } label: {
                        Text("Automation")
                        Text("Allow Tinycast to control OmniFocus, then refresh.")
                    }
                }
                catalogRow(.omniFocus)
            } header: {
                SettingsSectionHeader(.taskCaptureOmniFocus)
            } footer: {
                Text(
                    "Tasks are handed to OmniFocus as a TaskPaper paste link, so the app does not "
                        + "need to be running and is not brought forward. Suggestions read the project "
                        + "and tag lists through Apple events, which macOS asks you to allow once."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ScopeKeywordSection(
                scopeID: ScopeCatalog.omniFocus,
                explanation: "Type it, then a space, to write a task for OmniFocus.")

            Section {
                Toggle(isOn: $settings.taskCaptureTextFlowEnabled) {
                    SettingsRowTitle(.taskCaptureTextFlow, "Enable TextFlow")
                    Text(availability(.textFlow, installedHint: "Install TextFlow to /Applications to capture into it."))
                }
                catalogRow(.textFlow)
            } header: {
                SettingsSectionHeader(.taskCaptureTextFlow)
            } footer: {
                Text(
                    "Tasks are added through TextFlow's command line, which needs the app running: "
                        + "Tinycast launches it in the background if it is not. Projects and tags are "
                        + "re-read each time the palette opens."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ScopeKeywordSection(
                scopeID: ScopeCatalog.textFlow,
                explanation: "Type it, then a space, to write a task for TextFlow.")

            Section {
                ForEach(Self.grammar, id: \.0) { marker, meaning in
                    LabeledContent(meaning) {
                        Text(marker).font(.body.monospaced())
                    }
                }
            } header: {
                SettingsSectionHeader(.taskCaptureGrammar)
            } footer: {
                Text(
                    "Everything else is the title. Dates read today, tomorrow, weekday names, "
                        + "+3d, 18 sep or 2026-09-18, with an optional time such as 5pm or 17:00. "
                        + "TaskPaper attributes like @due(fri) and @tags(a, b) work as well. "
                        + "A field the destination cannot keep is struck through in the preview."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.taskCapture)
    }

    private static let grammar: [(String, String)] = [
        ("@Project", "Project, quoted if it has spaces"),
        ("#tag", "Tag, repeatable"),
        ("due fri 5pm", "Due date"),
        ("defer +1w", "Defer date"),
        ("!", "Flag"),
        ("~30m", "Estimate (OmniFocus)"),
        ("/inprogress  /hold", "Status (TextFlow)"),
        (">Name", "Assignee (TextFlow)"),
        ("// text", "Note"),
    ]

    private func availability(_ destination: TaskCaptureDestination, installedHint: String) -> String {
        guard index.isAvailable(destination) else { return installedHint }
        return core.taskCaptureCoordinator.isEnabled(destination)
            ? "On. Type the keyword in the launcher to capture a task."
            : "Off. The keyword does nothing."
    }

    private var omniFocusSuggestionsStatus: String {
        settings.taskCaptureOmniFocusSuggestions
            ? "Projects and tags are read from OmniFocus when its keyword is typed."
            : "Off. Projects and tags are typed from memory."
    }

    private func catalogRow(_ destination: TaskCaptureDestination) -> some View {
        LabeledContent {
            Button("Refresh Now") {
                refreshing.insert(destination)
                Task {
                    await core.taskCaptureCoordinator.refreshCatalogNow(destination)
                    refreshing.remove(destination)
                }
            }
            .disabled(refreshing.contains(destination) || !index.isAvailable(destination))
        } label: {
            Text("Projects and tags")
            Text(catalogStatus(destination))
        }
        .settingsEnabled(core.taskCaptureCoordinator.isEnabled(destination))
    }

    private func catalogStatus(_ destination: TaskCaptureDestination) -> String {
        if let failure = index.failures[destination] { return failure }
        guard let catalog = index.catalogs[destination] else { return "Not read yet." }
        return "\(catalog.projects.count) projects, \(catalog.tags.count) tags."
    }
}
