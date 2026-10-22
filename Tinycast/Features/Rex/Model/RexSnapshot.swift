import Foundation

/// One read of the Rex server: its tabs, and the local app that can show them.
/// The payload is the reply of `RexClient.snapshotScript`. See docs/features/rex.md.
struct RexSnapshot: Equatable, Sendable {
    /// The Rex app on this Mac, which is the only client `session.select` can bring forward.
    struct Host: Equatable, Sendable {
        let clientID: String
        let pid: Int32
    }

    var targets: [RexTarget]
    var host: Host?

    static let empty = RexSnapshot(targets: [], host: nil)

    /// Anything unparseable yields an empty snapshot: Rex being absent is not an error.
    static func parse(_ data: Data) -> RexSnapshot {
        guard !data.isEmpty,
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .empty }
        var targets: [RexTarget] = []
        for session in list(root["sessions"]) {
            guard let sessionID = session["session_id"] as? String,
                let sessionLabel = (session["label"] as? String)?.nilIfBlank
            else { continue }
            let activeWindowID = session["active_window_id"] as? String
            for window in list(session["windows"]) {
                guard let id = window["window_id"] as? String,
                    let label = tabLabel(window)
                else { continue }
                let states = list(window["blocks"]).flatMap { block in
                    list(block["states"]).compactMap { $0["state"] as? String }
                }
                targets.append(
                    RexTarget(
                        id: id, sessionID: sessionID, label: label, sessionLabel: sessionLabel,
                        status: .merged(states), active: id == activeWindowID))
            }
        }
        return RexSnapshot(targets: targets, host: host(in: list(root["clients"])))
    }

    /// A tab's own name when someone gave it one, else the title of the pane it has focused.
    private static func tabLabel(_ window: [String: Any]) -> String? {
        let label = (window["label"] as? String)?.nilIfBlank
        if let label, !RexTarget.isPlaceholderLabel(label) { return label }
        let focused = window["focused_block_id"] as? String
        let title =
            list(window["blocks"])
            .first { $0["block_id"] as? String == focused }?["title"] as? String
        return title?.nilIfBlank ?? label
    }

    /// The newest app connected over the local socket; a remote app has no window on this Mac.
    private static func host(in clients: [[String: Any]]) -> Host? {
        for client in clients.reversed() {
            let principal = client["principal"] as? [String: Any]
            guard (client["info"] as? [String: Any])?["kind"] as? String == "app",
                principal?["transport"] as? String == "unix",
                let pid = principal?["pid"] as? Int,
                let id = client["client_id"] as? String
            else { continue }
            return Host(clientID: id, pid: Int32(pid))
        }
        return nil
    }

    /// Lua encodes an empty table as `{}`, so an empty list can arrive as an object.
    private static func list(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }
}

extension String {
    fileprivate var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
