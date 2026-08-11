import Foundation

/// The environment a spawned command-line tool should see.
enum SubprocessEnvironment {
    /// Xcode injects debugging dylibs into a Debug run — `libMainThreadChecker`, the backtrace
    /// recorder — and a child process inherits them. That is enough to break any tool which reads
    /// its own executable: a Deno-compiled binary exits 1 with "Did not find magic bytes", so a
    /// feature that shells out works from a terminal and from a released build, and fails only
    /// while debugging. Stripping the loader's variables costs nothing and removes the trap.
    nonisolated static var inherited: [String: String] {
        stripping(ProcessInfo.processInfo.environment)
    }

    /// Pure, so `linear-test` can pin exactly which variables survive.
    nonisolated static func stripping(_ environment: [String: String]) -> [String: String] {
        environment.filter { !$0.key.hasPrefix("DYLD_") && !$0.key.hasPrefix("__XPC_DYLD_") }
    }
}
