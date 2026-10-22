import Foundation

@main
struct RexTest {
    // Captured from `RexClient.snapshotScript` against Rex Beta 0.1.0 (1347), api revision 5, then
    // trimmed. The second session's portless tab shows Lua's empty table arriving as `{}`.
    static let snapshotJSON = """
        {"sessions":[
         {"session_id":"session:01a1-aa","label":"terminal1 - faisandier-schema",
          "active_window_id":"window:01a165a9-b434-7dc7-b334-c03393eb48d0","windows":[
           {"window_id":"window:01a165a9-b434-7dc7-b334-c03393eb48d0","label":"Window 93eb48d0",
            "focused_block_id":"block:b1","blocks":[
             {"block_id":"block:b1","title":"Reset DB with latest fh data | terminal1",
              "states":[{"app":"codex","state":"idle"}]}]},
           {"window_id":"window:01a165a9-b452-72c6-b48c-3de2828310eb","label":"portless",
            "focused_block_id":"block:b2","blocks":[{"block_id":"block:b2","title":"","states":{}}]}]},
         {"session_id":"session:01a1-bb","label":"terminal5 - fix/identity-record-titles",
          "active_window_id":"window:w3","windows":[
           {"window_id":"window:w3","label":"agents","focused_block_id":"block:b3","blocks":[
             {"block_id":"block:b3","title":"Branch code review",
              "states":[{"app":"claude-code","state":"working"}]},
             {"block_id":"block:b4","title":"zsh",
              "states":[{"app":"terraform","state":"blocked"},{"app":"x","state":"sleeping"}]}]},
           {"window_id":"window:w4","label":"Window 0bbd0c38","focused_block_id":"block:b5",
            "blocks":{}}]},
         {"session_id":"session:01a1-cc","label":"  ","windows":[
           {"window_id":"window:w5","label":"orphan","blocks":{}}]}],
         "clients":[
          {"client_id":"client:cli","principal":{"kind":"peer","pid":800,"transport":"unix"}},
          {"client_id":"client:remote","info":{"kind":"app","label":"ersatz"},
           "principal":{"transport":"tailscale"}},
          {"client_id":"client:local","info":{"kind":"app","label":"entail"},
           "principal":{"kind":"peer","pid":800,"transport":"unix"}},
          {"client_id":"client:rex","info":{"kind":"cli"},
           "principal":{"pid":32388,"transport":"unix"}}]}
        """

    static let remoteOnlyJSON = """
        {"sessions":[],"clients":[
         {"client_id":"c","info":{"kind":"app"},"principal":{"transport":"tailscale"}}]}
        """

    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        let snapshot = RexSnapshot.parse(Data(snapshotJSON.utf8))
        let targets = snapshot.targets
        func target(_ id: String) -> RexTarget? { targets.first { $0.id == id } }

        // MARK: - What becomes a row

        check("every tab of every labelled session becomes a row", targets.count == 4)
        check(
            "tabs keep the server's order",
            targets.map(\.id) == [
                "window:01a165a9-b434-7dc7-b334-c03393eb48d0",
                "window:01a165a9-b452-72c6-b48c-3de2828310eb", "window:w3", "window:w4"
            ])
        check(
            "a session with a blank label takes its tabs with it",
            target("window:w5") == nil)
        check(
            "a row reads as its session, then its tab",
            target("window:w3")?.displayName == "terminal5 - fix/identity-record-titles › agents")
        check(
            "a tab keeps its session id for selecting it", target("window:w3")?.sessionID == "session:01a1-bb"
        )

        // MARK: - Naming a tab

        check(
            "a placeholder label gives way to the focused pane's title",
            target("window:01a165a9-b434-7dc7-b334-c03393eb48d0")?.label
                == "Reset DB with latest fh data | terminal1")
        check(
            "a name someone gave the tab wins over its title",
            target("window:w3")?.label == "agents")
        check(
            "a named tab with an empty title keeps its name",
            target("window:01a165a9-b452-72c6-b48c-3de2828310eb")?.label == "portless")
        check(
            "a placeholder with no title to replace it is kept rather than dropping the tab",
            target("window:w4")?.label == "Window 0bbd0c38")
        check("Rex's placeholder is recognised", RexTarget.isPlaceholderLabel("Window 93eb48d0"))
        check("a word that is not hex is a real name", !RexTarget.isPlaceholderLabel("Window shopping"))
        check("a bare Window is a real name", !RexTarget.isPlaceholderLabel("Window"))

        // MARK: - Status

        check(
            "a pane's reported status is carried",
            target("window:01a165a9-b434-7dc7-b334-c03393eb48d0")?.status == .idle)
        check(
            "the most urgent status across a tab's panes wins",
            target("window:w3")?.status == .blocked)
        check(
            "a tab where nothing reports has no status",
            target("window:01a165a9-b452-72c6-b48c-3de2828310eb")?.status == nil)
        check("an unrecognised state is ignored", RexTarget.ProgramStatus.merged(["sleeping"]) == nil)
        check(
            "error outranks done, but not blocked",
            RexTarget.ProgramStatus.merged(["done", "error"]) == .error
                && RexTarget.ProgramStatus.merged(["error", "blocked"]) == .blocked)
        check("idle is not noteworthy", !RexTarget.ProgramStatus.idle.isNoteworthy)
        check("the session's active tab is marked", target("window:w3")?.active == true)
        check("other tabs are not", target("window:w4")?.active == false)

        // MARK: - Host

        check(
            "the host is the local app, not the CLI sharing its pid or a remote app",
            snapshot.host == RexSnapshot.Host(clientID: "client:local", pid: 800))
        check(
            "no local app means no host, while the tabs still list",
            RexSnapshot.parse(
                Data(remoteOnlyJSON.utf8)
            ).host == nil)

        // MARK: - Degrading

        check("malformed JSON yields an empty snapshot", RexSnapshot.parse(Data("not json".utf8)) == .empty)
        check("empty input yields an empty snapshot", RexSnapshot.parse(Data()) == .empty)
        check(
            "Lua's empty table for no sessions yields no targets",
            RexSnapshot.parse(Data(#"{"sessions":{},"clients":{}}"#.utf8)) == .empty)

        // MARK: - Entry identity

        check("an entry id carries the window id", target("window:w3")?.entryID == "rex:window:w3")
        check(
            "a window entry id survives its colon", RexTarget.id(fromEntryID: "rex:window:w3") == "window:w3")
        check("another kind's entry id yields nothing", RexTarget.id(fromEntryID: "herdr:w2:tS") == nil)
        check("entry ids are unique", Set(targets.map(\.entryID)).count == targets.count)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
