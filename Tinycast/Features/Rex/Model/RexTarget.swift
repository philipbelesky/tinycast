import Foundation

/// A tab in the running Rex server. See docs/features/rex.md.
struct RexTarget: Identifiable, Hashable, Sendable {
    /// What a program in the tab reported over Rex's program-status protocol.
    enum ProgramStatus: String, Sendable {
        case idle
        case working
        case done
        case blocked
        case error

        /// The state a tab shows when its panes disagree: whatever most needs the user wins.
        fileprivate var urgency: Int {
            switch self {
            case .idle: 0
            case .working: 1
            case .done: 2
            case .error: 3
            case .blocked: 4
            }
        }

        /// Only a status worth reading across the palette; `idle` is the boring default.
        var isNoteworthy: Bool { self != .idle }

        /// The most urgent of several reports; unrecognised states are dropped, never guessed at.
        static func merged(_ raw: [String]) -> ProgramStatus? {
            raw.compactMap(ProgramStatus.init(rawValue:)).max { $0.urgency < $1.urgency }
        }
    }

    /// Rex's window id, `window:01a1…`. Opaque: it contains a colon, so it is never split.
    let id: String
    let sessionID: String
    let label: String
    /// The owning session's label, so a row reads `terminal4 - main › Branch code review`.
    let sessionLabel: String
    /// nil when no program in the tab reports a status, which is most shells.
    let status: ProgramStatus?
    /// The session's active tab — what Rex shows when that session is selected.
    let active: Bool

    static let entryIDPrefix = "rex:"

    var entryID: String { Self.entryIDPrefix + id }

    static func id(fromEntryID entryID: String) -> String? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return String(entryID.dropFirst(entryIDPrefix.count))
    }

    /// What the launcher row reads: a tab is only meaningful under its session.
    var displayName: String { sessionLabel + " › " + label }

    /// Rex names an unnamed tab `Window` plus its id's last eight hex digits, which says nothing.
    static func isPlaceholderLabel(_ label: String) -> Bool {
        let parts = label.split(separator: " ")
        guard parts.count == 2, parts[0] == "Window", parts[1].count == 8 else { return false }
        return parts[1].allSatisfy(\.isHexDigit)
    }
}
