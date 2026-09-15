import Foundation

/// The `linear` CLI's runs: `CommandLineProcess` with the credentials-aware environment.
enum LinearProcessRunner {
    typealias Result = CommandLineProcess.Result

    nonisolated static func run(
        _ executable: String, _ arguments: [String], timeout: Duration = .seconds(8)
    ) async -> Result? {
        await CommandLineProcess.run(executable, arguments, environment: environment, timeout: timeout)
    }

    /// Resolves the executable before async feature state exists; API requests use `run` above.
    nonisolated static func runSync(_ executable: String, _ arguments: [String]) -> Result? {
        CommandLineProcess.runSync(executable, arguments, environment: environment)
    }

    nonisolated private static var environment: [String: String] {
        LinearCredentials.workspaceEnvironment(SubprocessEnvironment.inherited)
    }
}
