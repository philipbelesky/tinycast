import SwiftUI

struct ApplicationsSettingsView: View {
    var body: some View {
        Form {
            // Scopes first: they decide what gets indexed, so they read before the results.
            SearchScopesSection()

            LauncherItemsSection(
                kind: .application,
                header: "Applications",
                searchPrompt: "Search applications…")

            ScopeKeywordSection(
                scopeID: ScopeCatalog.applications,
                explanation:
                    "Type it, then a space, to search applications and System Settings panes only.")
        }
        .formStyle(.grouped)
    }
}
