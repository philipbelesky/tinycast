import SwiftUI

/// Stock `.sidebar` styling throughout: headers, capsule and tint are all system-supplied.
struct SettingsSidebarView: View {
    @Environment(SettingsNavigationState.self) private var navigation
    @State private var query = ""
    @State private var highlighted: SettingsSearchEntry.ID?
    @FocusState private var searchFocused: Bool

    private var results: [SettingsSearchEntry] { SettingsSearchCatalog.results(for: query) }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSearchField(query: $query, focused: $searchFocused)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
            if query.isEmpty {
                browse
            } else {
                found
            }
        }
        // The field sits under the toolbar's material, so it needs its own clearance from the top.
        .padding(.top, Theme.Spacing.md)
        .onExitCommand { query = "" }
        .background(focusShortcut)
    }

    private var browse: some View {
        List(selection: selection) {
            ForEach(SettingsSection.allCases) { section in
                Section(section.title) {
                    ForEach(section.tabs) { tab in
                        SettingsSidebarTabRow(tab: tab).tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private var found: some View {
        if results.isEmpty {
            // Greedy: a finite max height here becomes a constraint that shrinks the whole window.
            ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // A second `List`, so result IDs and `SettingsTab` never share a selection namespace.
            List(selection: $highlighted) {
                Section("Results") {
                    ForEach(results) { entry in
                        SettingsSearchResultRow(entry: entry).tag(entry.id)
                    }
                }
            }
            .listStyle(.sidebar)
            // Arrowing through results moves the pane with the selection, as System Settings does.
            .onChange(of: highlighted) { _, id in
                guard let entry = results.first(where: { $0.id == id }) else { return }
                navigation.select(entry.tab, revealing: entry.target)
            }
        }
    }

    /// ⌘F with no menu item to hang it on; zero-sized so it only ever contributes the shortcut.
    private var focusShortcut: some View {
        Button("Search Settings") { searchFocused = true }
            .keyboardShortcut("f", modifiers: .command)
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    /// `List` hands back an optional selection; routing it through `select` records history.
    private var selection: Binding<SettingsTab?> {
        Binding(
            get: { navigation.tab },
            set: { if let tab = $0 { navigation.select(tab) } }
        )
    }
}

/// Marks a feature pane as off without hiding the place where it can be turned back on.
private struct SettingsSidebarTabRow: View {
    let tab: SettingsTab
    @Environment(AppSettings.self) private var settings
    @Environment(AppCore.self) private var core

    private var isDisabled: Bool {
        switch tab {
        case .ai: !settings.aiEnabled
        case .quickActions: !settings.quickActionsEnabled
        case .fileSearch: !settings.fileSearchEnabled
        case .webSearch: !settings.webSearchEnabled
        case .herdr: !settings.herdrEnabled
        case .vsCode: !settings.vsCodeEnabled
        case .zed: !settings.zedEnabled
        case .linear: !core.linear.isEnabled
        case .notes: !settings.notesEnabled
        case .navigation: !settings.navigationEnabled
        case .snippets: !settings.snippetsEnabled
        case .windowManagement: !settings.windowManagementEnabled
        case .clipboard: !settings.clipboardEnabled
        case .calendar: !settings.calendarEnabled
        case .extensions: !settings.extensionsEnabled
        case .commands: !settings.customCommandsEnabled
        case .quicklinks: !settings.quicklinksEnabled
        case .general, .applications, .systemSettings, .systemActions, .fallbacks, .emoji,
            .permissions, .backup, .miscellaneous, .about:
            false
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Label(tab.title, systemImage: tab.systemImage)
            Spacer(minLength: Theme.Spacing.sm)
            if isDisabled {
                Text("Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsSearchResultRow: View {
    let entry: SettingsSearchEntry

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(entry.title).lineLimit(1)
                Text(entry.breadcrumb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } icon: {
            Image(systemName: entry.tab.systemImage)
        }
    }
}
