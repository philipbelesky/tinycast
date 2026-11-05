import SwiftUI

struct ApplicationsSettingsView: View {
    var body: some View {
        Form {
            LauncherCategorySwitchSection(
                kind: .application, anchor: .applicationsApplications,
                title: "Enable Applications")

            SearchScopesSection()

            LauncherItemsSection(
                kind: .application,
                anchor: .applicationsApplications,
                searchPrompt: "Search applications…",
                emptyMessage: LocalizedStringResource(
                    "applications-empty", defaultValue: "Nothing here yet."))

            ScopeKeywordSection(
                scopeID: ScopeCatalog.applications,
                explanation:
                    "Type it, then a space, to search applications and System Settings panes only.")
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.applications)
        .releasesFocusOnOutsideClick()
    }

}
