import Foundation

@main
struct HerdrTest {
    // Captured verbatim from `herdr workspace list` / `herdr tab list`, v0.8 protocol 19.
    static let workspacesJSON = """
        {"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[
        {"active_tab_id":"w2:tX","agent_status":"idle","focused":false,"label":"meta","number":1,
         "pane_count":4,"tab_count":4,"workspace_id":"w2"},
        {"active_tab_id":"wT:t1","agent_status":"idle","focused":false,"label":"payments1","number":2,
         "pane_count":3,"tab_count":1,"workspace_id":"wT"},
        {"active_tab_id":"wN:t1","agent_status":"done","focused":false,"label":"tvtunes","number":6,
         "pane_count":2,"tab_count":1,"workspace_id":"wN"},
        {"active_tab_id":"wW:t1","agent_status":"working","focused":true,"label":"tinycast","number":10,
         "pane_count":1,"tab_count":1,"workspace_id":"wW"}]}}
        """
    static let tabsJSON = """
        {"id":"cli:tab:list","result":{"type":"tab_list","tabs":[
        {"agent_status":"idle","focused":false,"label":"raycast-spoon","number":25,"pane_count":1,
         "tab_id":"w2:tS","workspace_id":"w2"},
        {"agent_status":"unknown","focused":false,"label":"4","number":29,"pane_count":1,
         "tab_id":"w2:tX","workspace_id":"w2"},
        {"agent_status":"idle","focused":false,"label":"1","number":1,"pane_count":3,
         "tab_id":"wT:t1","workspace_id":"wT"},
        {"agent_status":"working","focused":true,"label":"1","number":1,"pane_count":1,
         "tab_id":"wW:t1","workspace_id":"wW"},
        {"agent_status":"blocked","focused":false,"label":"orphan","number":3,"pane_count":1,
         "tab_id":"wZ:t9","workspace_id":"wZ"}]}}
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

        let targets = HerdrTarget.parse(
            workspaces: Data(workspacesJSON.utf8), tabs: Data(tabsJSON.utf8))

        // MARK: - What becomes a row

        check("only tabs become rows", targets.count == 4)
        check(
            "no workspace earns a row of its own",
            !targets.contains { $0.id == "w2" })
        check(
            "tabs keep their listed order",
            targets.map(\.id) == ["w2:tS", "w2:tX", "wT:t1", "wW:t1"])
        // Nothing stands in for it now, so suppressing it would strand the workspace.
        check(
            "a workspace's only tab is listed like any other",
            targets.contains { $0.id == "wW:t1" && $0.displayName == "tinycast › 1" })
        check(
            "a tab id containing a colon survives intact",
            targets.first { $0.label == "raycast-spoon" }?.id == "w2:tS")
        check(
            "a row reads as its workspace, then itself",
            targets.first { $0.id == "w2:tS" }?.displayName == "meta › raycast-spoon")
        check(
            "a tab whose workspace is unknown is dropped rather than shown unlabelled",
            !targets.contains { $0.id == "wZ:t9" })
        check(
            "the focused tab is marked",
            targets.first { $0.id == "wW:t1" }?.focused == true)
        check(
            "agent status is carried",
            targets.first { $0.id == "wW:t1" }?.status == .working)

        // MARK: - Degrading rather than dropping

        let oneTab = #"{"result":{"tabs":[{"tab_id":"w1:t1","label":"1","workspace_id":"w1"}]}}"#
        check(
            "an unrecognised status reads as unknown",
            targets.first { $0.id == "w2:tX" }?.status == .unknown)
        check(
            "a status absent from the payload reads as unknown",
            HerdrTarget.parse(
                workspaces: Data(
                    #"{"result":{"workspaces":[{"workspace_id":"w1","label":"a"}]}}"#.utf8),
                tabs: Data(oneTab.utf8)
            ).first?.status == .unknown)
        check(
            "a workspace with no label takes its tabs with it: an unnamed row is unusable",
            HerdrTarget.parse(
                workspaces: Data(#"{"result":{"workspaces":[{"workspace_id":"w1"}]}}"#.utf8),
                tabs: Data(oneTab.utf8)
            ).isEmpty)
        check(
            "malformed JSON yields no targets rather than throwing",
            HerdrTarget.parse(workspaces: Data("not json".utf8), tabs: Data(oneTab.utf8)).isEmpty)
        check(
            "empty input yields no targets",
            HerdrTarget.parse(workspaces: Data(), tabs: Data()).isEmpty)

        // MARK: - Entry identity

        check(
            "an entry id carries the target id",
            targets.first?.entryID == "herdr:w2:tS")
        check(
            "a tab entry id survives its colon",
            HerdrTarget.id(fromEntryID: "herdr:w2:tS") == "w2:tS")
        check(
            "another kind's entry id yields nothing",
            HerdrTarget.id(fromEntryID: "quicklink:1234") == nil)
        check(
            "entry ids are unique across the whole set",
            Set(targets.map(\.entryID)).count == targets.count)

        // MARK: - Host detection walks the process tree to the first bundled ancestor

        // pid, ppid, bundled — the shape `HerdrHost` takes so the walk is testable.
        let table: [HerdrHost.Entry] = [
            HerdrHost.Entry(pid: 5334, parentPID: 4427, bundleID: nil),
            HerdrHost.Entry(pid: 4427, parentPID: 4425, bundleID: nil),
            HerdrHost.Entry(pid: 4425, parentPID: 690, bundleID: nil),
            HerdrHost.Entry(pid: 690, parentPID: 1, bundleID: "com.mitchellh.ghostty"),
            HerdrHost.Entry(pid: 1, parentPID: 0, bundleID: nil)
        ]
        check(
            "the walk finds the first bundled ancestor",
            HerdrHost.bundleID(forClient: 5334, in: table) == "com.mitchellh.ghostty")
        check(
            "a client with no bundled ancestor yields nil",
            HerdrHost.bundleID(forClient: 5334, in: Array(table.prefix(3))) == nil)
        check(
            "an unknown pid yields nil",
            HerdrHost.bundleID(forClient: 9999, in: table) == nil)
        // A pid cycle is impossible on a healthy system and fatal if we trust it.
        check(
            "a parent cycle terminates instead of hanging",
            HerdrHost.bundleID(
                forClient: 2,
                in: [
                    HerdrHost.Entry(pid: 2, parentPID: 3, bundleID: nil),
                    HerdrHost.Entry(pid: 3, parentPID: 2, bundleID: nil)
                ]) == nil)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
