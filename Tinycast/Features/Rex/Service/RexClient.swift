import AppKit

/// Talks to the running Rex server through its CLI, which is a thin client on a local unix socket.
/// One `rex do` script reads every session, tab and pane in about 25 ms. See docs/features/rex.md.
enum RexClient {
    /// Rex ships its CLI inside the server bundle; the shell finds it through the PATH Rex sets up.
    private static let bundledCLI =
        "Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/"
        + "Rex Server.app/Contents/MacOS/rex"

    nonisolated static func locate() async -> URL? {
        await ExecutableLocator.locate("rex", extraHomePaths: [bundledCLI])
    }

    /// Everything in one process: `session.view` refuses an unattached caller, so each session is
    /// attached, which lasts only as long as the script.
    nonisolated static let snapshotScript = """
        local terminal = "com.superlogical.terminal"
        local sessions = {}
        for _, listed in ipairs(rex.call("session.list").sessions or {}) do
          local attached = rex.call("session.attach", { session_id = listed.session_id })
          local view = attached and attached.view
          if view then
            local windows = {}
            for _, window in ipairs(view.windows or {}) do
              local blocks = {}
              for _, layer in ipairs(window.layers or {}) do
                for _, block in ipairs(layer.blocks or {}) do
                  if block.creator_name == terminal then
                    local function call(method)
                      return (rex.call("block.method", {
                        session_id = listed.session_id, block_id = block.block_id,
                        method = method }))
                    end
                    local title = call("title")
                    local status = call("program_status")
                    blocks[#blocks + 1] = {
                      block_id = block.block_id,
                      title = title and title.title,
                      states = status and status.records }
                  end
                end
              end
              windows[#windows + 1] = {
                window_id = window.window_id, label = window.label,
                focused_block_id = window.focused_block_id, blocks = blocks }
            end
            sessions[#sessions + 1] = {
              session_id = listed.session_id, label = listed.label,
              active_window_id = view.active_window_id, windows = windows }
          end
        end
        return { sessions = sessions, clients = (rex.call("client.list") or {}).clients }
        """

    /// Empty on any failure: Rex not running is the normal case, not one to report.
    nonisolated static func snapshot(executable: URL) async -> RexSnapshot {
        guard let output = await run(executable, ["do", "-e", snapshotScript]) else { return .empty }
        return RexSnapshot.parse(output)
    }

    /// Asks the Rex app to show the tab. Raising the app is a separate step — see `reveal`.
    nonisolated static func select(
        _ target: RexTarget, host: RexSnapshot.Host, executable: URL
    ) async -> Bool {
        let arguments = [
            "-C", host.clientID, "do", "session.select",
            "session_id=" + target.sessionID, "window_id=" + target.id
        ]
        return await run(executable, arguments) != nil
    }

    /// The host is a running app by construction, so its bundle is read from the pid.
    @MainActor
    static func reveal(_ host: RexSnapshot.Host) {
        guard let url = NSRunningApplication(processIdentifier: host.pid)?.bundleURL else { return }
        AppLauncher.launch(url)
    }

    /// nil on a launch failure, a timeout or a non-zero exit; stdout otherwise.
    nonisolated private static func run(_ executable: URL, _ arguments: [String]) async -> Data? {
        // Load-bearing: the CLI otherwise starts a server when none is running.
        let result = await CommandLineProcess.run(
            executable.path, ["--autostart=false"] + arguments,
            environment: SubprocessEnvironment.inherited, timeout: .seconds(3))
        guard let result, !result.signalled, result.status == 0 else { return nil }
        return result.output
    }
}
