import Foundation

@main
struct VSCodeTest {
    static let home = "/Users/philip"

    static func candidate(_ json: String, _ daysAgo: TimeInterval) -> VSCodeProject.Candidate {
        VSCodeProject.Candidate(
            payload: Data(json.utf8), modified: Date(timeIntervalSince1970: 1_000_000 - daysAgo))
    }

    /// Every path the fake filesystem admits to; anything else is a project since deleted.
    static let onDisk: Set<String> = [
        "/Users/philip/Sites/aical", "/Users/philip/Sites/payments2", "/Users/philip/.settings",
        "/Users/philip/Library/Application Support/Code/User/agent-sessions.code-workspace",
        "/Volumes/Work/detached"
    ]

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

        func parse(_ candidates: [VSCodeProject.Candidate]) -> [VSCodeProject] {
            VSCodeProject.parse(candidates, homeDirectory: home) { onDisk.contains($0) }
        }

        // MARK: - Folders

        let folders = parse([
            candidate(#"{"folder":"file:///Users/philip/Sites/aical"}"#, 3),
            candidate(#"{"folder":"file:///Users/philip/Sites/payments2"}"#, 1),
            candidate(#"{"folder":"file:///Users/philip/.settings"}"#, 2)
        ])
        check("every folder that still exists becomes a project", folders.count == 3)
        check(
            "projects are ordered most recently opened first",
            folders.map(\.name) == ["payments2", ".settings", "aical"])
        check("a folder project is a folder", folders.allSatisfy { $0.kind == .folder })
        check(
            "the path is the decoded POSIX path, not the URI",
            folders.first?.path == "/Users/philip/Sites/payments2")
        check("the id is the path, so two windows on one folder collapse", folders.first?.id == folders.first?.path)

        // MARK: - Workspaces

        let workspaceURI =
            "file:///Users/philip/Library/Application%20Support/Code/User/agent-sessions.code-workspace"
        let workspaces = parse([candidate(#"{"workspace":"\#(workspaceURI)"}"#, 1)])
        check("a multi-root workspace becomes a project", workspaces.count == 1)
        check("a workspace is a workspace", workspaces.first?.kind == .workspace)
        check(
            "percent-encoding is decoded",
            workspaces.first?.path
                == "/Users/philip/Library/Application Support/Code/User/agent-sessions.code-workspace")
        check(
            "the .code-workspace suffix is dropped from the name",
            workspaces.first?.name == "agent-sessions")

        // MARK: - What is dropped

        check("an empty window contributes nothing", parse([candidate("", 1)]).isEmpty)
        check("unparseable JSON contributes nothing", parse([candidate("{not json", 1)]).isEmpty)
        check(
            "a payload naming neither key contributes nothing",
            parse([candidate(#"{"emptyWindow":true}"#, 1)]).isEmpty)
        check(
            "a folder that has since been deleted is dropped",
            parse([candidate(#"{"folder":"file:///Users/philip/Sites/gone"}"#, 1)]).isEmpty)
        check(
            "a remote folder is dropped, having no local path to open",
            parse([
                candidate(#"{"folder":"vscode-remote://ssh-remote%2Bbox/srv/app"}"#, 1)
            ]).isEmpty)

        // MARK: - Duplicates

        let duplicated = parse([
            candidate(#"{"folder":"file:///Users/philip/Sites/aical"}"#, 9),
            candidate(#"{"folder":"file:///Users/philip/Sites/aical"}"#, 1)
        ])
        check("one folder opened twice yields one project", duplicated.count == 1)
        check(
            "the surviving duplicate carries the more recent open",
            duplicated.first?.lastOpened == Date(timeIntervalSince1970: 1_000_000 - 1))

        // MARK: - Display

        let trailing = parse([candidate(#"{"folder":"file:///Users/philip/Sites/aical/"}"#, 1)])
        check("a trailing slash does not empty the name", trailing.first?.name == "aical")
        check(
            "a path under home is abbreviated for display",
            folders.first { $0.name == "aical" }?.displayPath == "~/Sites")
        let detached = parse([candidate(#"{"folder":"file:///Volumes/Work/detached"}"#, 1)])
        check(
            "a path outside home stays absolute",
            detached.first?.displayPath == "/Volumes/Work")

        // MARK: - Entry ids

        let project = folders[0]
        check("an entry id round-trips", VSCodeProject.path(fromEntryID: project.entryID) == project.path)
        check(
            "a foreign entry id yields no path",
            VSCodeProject.path(fromEntryID: "herdr:w2") == nil)

        print("")
        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        if failures > 0 { exit(1) }
    }
}
