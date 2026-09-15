import AppKit

/// Every OmniFocus effect: the paste that adds a task, and the JXA read behind completions.
enum OmniFocusRunner {
    private static let probe = URL(string: "omnifocus:///")!

    /// Installed at all — Launch Services knows the scheme or it doesn't.
    @MainActor static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }

    /// Opens the paste URL without bringing OmniFocus forward: the palette was summoned from
    /// somewhere, and that is where the user still is.
    @MainActor static func paste(_ url: URL) async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        do {
            _ = try await NSWorkspace.shared.open(url, configuration: configuration)
            return true
        } catch {
            return false
        }
    }

    enum CatalogFailure: Error, Equatable {
        /// The Automation grant was refused; System Settings is where it comes back.
        case notAuthorized
        case failed(String)
    }

    /// The first read blocks on the macOS consent dialog for as long as the user leaves it up.
    private static let readTimeout: Duration = .seconds(180)

    /// A batch of Apple events through `osascript`, so the app process never links Automation.
    nonisolated static func readCatalog() async -> Result<TaskCaptureCatalog, CatalogFailure> {
        let result = await CommandLineProcess.run(
            "/usr/bin/osascript", ["-l", "JavaScript", "-e", OmniFocusCatalog.script],
            environment: SubprocessEnvironment.inherited, timeout: readTimeout)
        guard let result else { return .failure(.failed("osascript did not run")) }
        guard result.status == 0 else {
            // -1743 is errAEEventNotPermitted: the one failure the user can fix, so it is named.
            if result.errorText.contains("-1743") { return .failure(.notAuthorized) }
            return .failure(.failed(result.errorText))
        }
        guard let catalog = OmniFocusCatalog.parse(result.output) else {
            return .failure(.failed("unreadable reply"))
        }
        return .success(catalog)
    }
}
