import Foundation

/// Runs the `linear` CLI off-main, terminating work superseded by a newer palette query.
enum LinearProcessRunner {
    struct Result: Sendable {
        let output: Data
        let status: Int32
        let signalled: Bool
        let errorText: String
    }

    nonisolated static func run(
        _ executable: String, _ arguments: [String], timeout: Duration = .seconds(8)
    ) async -> Result? {
        let worker = LinearProcessWorker(executable: executable, arguments: arguments)
        return await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) { worker.run(timeout: timeout) }.value
        } onCancel: {
            worker.stop()
        }
    }

    /// Resolves the executable before async feature state exists; API requests use `run` above.
    nonisolated static func runSync(_ executable: String, _ arguments: [String]) -> Result? {
        LinearProcessWorker(executable: executable, arguments: arguments).run(timeout: nil)
    }
}

private final class LinearProcessWorker: @unchecked Sendable {
    private let executable: String
    private let arguments: [String]
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    private var timedOut = false

    init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    func run(timeout: Duration?) -> LinearProcessRunner.Result? {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = LinearCredentials.workspaceEnvironment(SubprocessEnvironment.inherited)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr

        lock.lock()
        guard !stopped else {
            lock.unlock()
            return nil
        }
        self.process = process
        lock.unlock()

        do {
            try process.run()
        } catch {
            clearProcess()
            return nil
        }
        stopProcessIfNeeded(process)
        let watchdog = timeout.map { timeout in
            Task.detached { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.stop(timedOut: true)
            }
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog?.cancel()

        lock.lock()
        let timedOut = timedOut
        self.process = nil
        lock.unlock()
        let stderrText =
            String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return LinearProcessRunner.Result(
            output: output, status: process.terminationStatus,
            signalled: process.terminationReason != .exit,
            errorText: timedOut && stderrText.isEmpty ? "request timed out" : stderrText)
    }

    func stop() {
        stop(timedOut: false)
    }

    private func stop(timedOut: Bool) {
        lock.lock()
        stopped = true
        self.timedOut = self.timedOut || timedOut
        let process = process
        lock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }

    private func stopProcessIfNeeded(_ process: Process) {
        lock.lock()
        let shouldStop = stopped
        lock.unlock()
        if shouldStop, process.isRunning { process.terminate() }
    }

    private func clearProcess() {
        lock.lock()
        process = nil
        lock.unlock()
    }
}
