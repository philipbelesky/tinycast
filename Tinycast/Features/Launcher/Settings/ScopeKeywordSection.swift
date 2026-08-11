import SwiftUI

/// The keyword that scopes the root search to one feature, and the field that changes it.
/// See docs/features/palette.md#scope-keywords.
struct ScopeKeywordSection: View {
    let scopeID: String
    /// What typing the keyword narrows to, in the pane's own words.
    let explanation: String

    var body: some View {
        Section {
            ScopeKeywordField(scopeID: scopeID)
        } header: {
            Text("Keyword")
        } footer: {
            Text(explanation + " Clear the field to leave the feature with no keyword.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A single row: the keyword, the space that commits it, and whatever is already using it.
struct ScopeKeywordField: View {
    let scopeID: String
    var title: String?

    @Environment(AppSettings.self) private var settings
    @State private var text = ""
    /// The scope already holding what was typed; the edit is refused while this is set.
    @State private var conflict: String?

    private var keyword: String {
        ScopeCatalog.allDefinitions(settings: settings).first { $0.id == scopeID }?.keyword ?? ""
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                if let conflict {
                    Text("Used by \(conflict)")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.destructive)
                }
                TextField("None", text: $text)
                    .frame(width: Self.fieldWidth)
                    .multilineTextAlignment(.center)
                    .font(.body.monospaced())
                    .onChange(of: text) { _, typed in commit(typed) }
            }
        } label: {
            Text(title ?? ScopeCatalog.title(id: scopeID))
        }
        // The stored keyword can move without this field: a backup import, or a collision resolved
        // in another pane. `onChange` of the resolved value is what keeps the two honest.
        .onAppear { text = keyword }
        .onChange(of: keyword) { _, resolved in
            if conflict == nil { text = resolved }
        }
    }

    private static let fieldWidth: CGFloat = 56 * Theme.scale

    private func commit(_ typed: String) {
        let candidate = ScopeKeywords.normalized(typed)
        let definitions = ScopeCatalog.allDefinitions(settings: settings)
        if let other = ScopeKeywords.conflict(for: candidate, assignedTo: scopeID, in: definitions) {
            conflict = other.title
            return
        }
        conflict = nil
        // A keyword back at its shipped value is stored as no override at all, so the default can
        // still move under it in a later build.
        if candidate == ScopeCatalog.defaultKeyword(id: scopeID) {
            settings.scopeKeywords.removeValue(forKey: scopeID)
        } else {
            settings.scopeKeywords[scopeID] = candidate
        }
    }
}
