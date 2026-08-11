import Foundation

/// Where a view opens. The desktop app registers `linear://` at runtime; it declares no URL type,
/// so LaunchServices only knows the scheme once Linear has run at least once.
enum LinearDestination: String, CaseIterable, Identifiable, Sendable {
    case app
    case browser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: return "Linear app"
        case .browser: return "Browser"
        }
    }
}

/// One Linear view — saved by the user, or one of the fixed pages every workspace has.
/// See docs/features/linear.md.
struct LinearView: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case saved
        case builtIn

        var label: String {
            switch self {
            case .saved: return "Linear View"
            case .builtIn: return "Linear"
            }
        }
    }

    /// The workspace slug the CLI knows, which is not always the url key the web app uses.
    let workspaceSlug: String
    let workspaceURLKey: String
    let name: String
    /// Everything after the workspace: `view/<slugId>`, or a fixed page like `inbox`.
    let path: String
    let kind: Kind
    let symbol: String

    /// Unique across workspaces, which matters: two of them can hold a view of the same name.
    var id: String { workspaceURLKey + "/" + path }

    static let entryIDPrefix = "linear:"
    static let defaultSymbol = "line.3.horizontal.decrease.circle"

    var entryID: String { Self.entryIDPrefix + id }

    static func id(fromEntryID entryID: String) -> String? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return String(entryID.dropFirst(entryIDPrefix.count))
    }

    /// The workspace leads, so one glance separates two views that share a name.
    var displayName: String { workspaceURLKey + " › " + name }

    func url(opening destination: LinearDestination) -> URL? {
        let base = destination == .app ? "linear://linear.app/" : "https://linear.app/"
        return URL(string: base + workspaceURLKey + "/" + path)
    }

    /// The pages every workspace has, which no query returns because they are routes, not records.
    static func builtIn(for urlKey: String, workspaceSlug: String) -> [LinearView] {
        [("Inbox", "inbox", "tray"), ("My Issues", "my-issues", "person.crop.circle"),
         ("Projects", "projects", "square.stack.3d.up"),
         ("Initiatives", "initiatives", "flag"), ("Settings", "settings", "gearshape")]
            .map { name, path, symbol in
                LinearView(
                    workspaceSlug: workspaceSlug, workspaceURLKey: urlKey, name: name, path: path,
                    kind: .builtIn, symbol: symbol)
            }
    }

    /// The saved views in one `organization`+`customViews` reply. Empty for anything unreadable —
    /// `linear api` answers 200 with an `errors` array, so a failed query lands here, not in a throw.
    static func parse(_ payload: Data, workspaceSlug: String) -> [LinearView] {
        guard let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let data = root["data"] as? [String: Any],
            let organization = data["organization"] as? [String: Any],
            let urlKey = (organization["urlKey"] as? String)?.nilIfBlank,
            let nodes = (data["customViews"] as? [String: Any])?["nodes"] as? [[String: Any]]
        else { return [] }

        return nodes.compactMap { node -> LinearView? in
            guard let name = (node["name"] as? String)?.nilIfBlank,
                let slugID = (node["slugId"] as? String)?.nilIfBlank
            else { return nil }
            return LinearView(
                workspaceSlug: workspaceSlug, workspaceURLKey: urlKey, name: name,
                path: "view/" + slugID, kind: .saved,
                symbol: symbol(forLinearIcon: node["icon"] as? String))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Linear names its icons in its own vocabulary; anything unmapped keeps the view visible.
    static func symbol(forLinearIcon icon: String?) -> String {
        switch icon {
        case "Checklist": return "checklist"
        case "ClockOutline", "Hourglass": return "clock"
        case "Page", "Document": return "doc.text"
        case "Image": return "photo"
        case "Robot": return "cpu"
        case "Users", "Team": return "person.2"
        case "Dollar": return "dollarsign.circle"
        case "Calendar": return "calendar"
        case "Diagram": return "chart.bar"
        case "Rocket": return "paperplane"
        case "Bug": return "ladybug"
        case "Star": return "star"
        case "Labels", "Tag": return "tag"
        default: return defaultSymbol
        }
    }
}

extension String {
    fileprivate var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
