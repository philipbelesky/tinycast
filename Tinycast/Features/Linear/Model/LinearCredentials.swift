import Foundation

/// The workspace slugs the `linear` CLI is logged in to. See docs/features/linear.md.
enum LinearCredentials {
    struct Configuration: Equatable, Sendable {
        var defaultWorkspace: String?
        var workspaces: [String]
    }

    /// A four-line TOML file read by two regexes rather than a parser: only these two keys are
    /// wanted, and every other key — a migrated token among them — must stay unread.
    static func parse(_ toml: String) -> Configuration {
        Configuration(
            defaultWorkspace: value(of: "default", in: toml).flatMap(unquoted),
            workspaces: (value(of: "workspaces", in: toml).map(list) ?? []))
    }

    private static func value(of key: String, in toml: String) -> String? {
        for line in toml.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                parts[0].trimmingCharacters(in: .whitespaces) == key
            else { continue }
            return parts[1].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func list(_ raw: String) -> [String] {
        guard raw.hasPrefix("["), raw.hasSuffix("]") else { return [] }
        return raw.dropFirst().dropLast()
            .split(separator: ",")
            .compactMap { unquoted($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func unquoted(_ raw: String) -> String? {
        let stripped = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? nil : stripped
    }
}
