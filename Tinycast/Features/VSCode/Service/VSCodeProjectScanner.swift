import AppKit

/// Reads VS Code's own record of what it has opened. See docs/features/vscode.md.
enum VSCodeProjectScanner {
    static let bundleID = "com.microsoft.VSCode"

    /// One directory per window VS Code has ever opened, each naming its folder or workspace.
    private static var workspaceStorage: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Code/User/workspaceStorage", directoryHint: .isDirectory)
    }

    @MainActor
    static var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Empty whenever VS Code has never run: no directory is the same answer as no projects.
    nonisolated static func scan() async -> [VSCodeProject] {
        await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            let home = NSHomeDirectory()
            guard
                let directories = try? manager.contentsOfDirectory(
                    at: workspaceStorage, includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles])
            else { return [] }

            let candidates = directories.compactMap { directory -> VSCodeProject.Candidate? in
                let record = directory.appending(path: "workspace.json", directoryHint: .notDirectory)
                guard let payload = try? Data(contentsOf: record) else { return nil }
                // The directory's own mtime, not the file's: VS Code rewrites state beside it.
                let modified =
                    (try? directory.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return VSCodeProject.Candidate(payload: payload, modified: modified)
            }
            return VSCodeProject.parse(candidates, homeDirectory: home) {
                manager.fileExists(atPath: $0)
            }
        }.value
    }

    /// Opens the folder or workspace file the way a Dock drop would, rather than shelling out.
    @MainActor
    static func open(_ project: VSCodeProject) async {
        guard let application = applicationURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.open(
            [URL(filePath: project.path)], withApplicationAt: application,
            configuration: configuration)
    }
}
