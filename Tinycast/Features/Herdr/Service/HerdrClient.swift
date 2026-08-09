import AppKit

/// Talks to the running herdr session over its CLI, which is a thin client on a local unix socket —
/// a `list` round trip costs about 5 ms. See docs/features/herdr.md.
enum HerdrClient {
    /// A GUI app inherits none of a login shell's PATH, so the binary is looked for by hand.
    private static let candidatePaths = [
        "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr",
        NSHomeDirectory() + "/.local/bin/herdr"
    ]

    /// Resolved once per launch: the path is stable, and the shell fallback costs a login shell.
    private static let executablePath: String? = {
        let manager = FileManager.default
        if let known = candidatePaths.first(where: manager.isExecutableFile(atPath:)) {
            return known
        }
        guard let resolved = run("/bin/zsh", ["-lc", "command -v herdr"]),
            let path = String(data: resolved, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            manager.isExecutableFile(atPath: path)
        else { return nil }
        return path
    }()

    static var isAvailable: Bool { executablePath != nil }

    /// Both lists in one hop off-main. Empty on any failure: herdr being absent is the normal case.
    nonisolated static func snapshot() async -> [HerdrTarget] {
        await Task.detached(priority: .userInitiated) {
            guard let herdr = executablePath else { return [] }
            let workspaces = run(herdr, ["workspace", "list"]) ?? Data()
            let tabs = run(herdr, ["tab", "list"]) ?? Data()
            return HerdrTarget.parse(workspaces: workspaces, tabs: tabs)
        }.value
    }

    /// Moves herdr's own focus. Raising the app that hosts it is a separate step — see `HerdrHost`.
    nonisolated static func focus(_ target: HerdrTarget) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            guard let herdr = executablePath else { return false }
            let noun = target.kind == .workspace ? "workspace" : "tab"
            return run(herdr, [noun, "focus", target.id]) != nil
        }.value
    }

    /// The bundle id of the app hosting a running herdr client, or nil when it runs over ssh.
    /// The running-app list is AppKit's, so it is read here and the scan runs off-main with a copy.
    @MainActor
    static func hostBundleID() async -> String? {
        var bundleIDs: [Int32: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier else { continue }
            bundleIDs[app.processIdentifier] = id
        }
        return await Task.detached(priority: .userInitiated) {
            let table = ProcessTable.entries(bundleIDs: bundleIDs)
            let hosts = table.map(\.host)
            // Newest client first: a detached one may outlive the window it was started from, and
            // an ssh or mosh client has no local app at all — fall through to the next.
            for pid in table.filter({ $0.command == "herdr" }).map(\.pid).sorted(by: >) {
                if let host = HerdrHost.bundleID(forClient: pid, in: hosts) { return host }
            }
            return nil
        }.value
    }

    /// nil on a launch failure or a non-zero exit; stdout otherwise.
    nonisolated private static func run(_ executable: String, _ arguments: [String]) -> Data? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // Load-bearing: a herdr that waited on input would hang the palette's refresh.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        return data
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
