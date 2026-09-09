import Foundation

@main
struct ZedTest {
    static let home = "/Users/philip"

    static func candidate(
        _ paths: String, order: String = "0", daysAgo: TimeInterval
    ) -> ZedProject.Candidate {
        ZedProject.Candidate(
            paths: paths, pathsOrder: order,
            lastOpened: Date(timeIntervalSince1970: 1_000_000 - daysAgo))
    }

    /// Every path the fake filesystem admits to; anything else is a removed workspace root.
    static let onDisk: Set<String> = [
        "/Users/philip/Sites/aical", "/Users/philip/Sites/payments2",
        "/Users/philip/Desktop/notes.md", "/Volumes/Work/detached"
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

        func parse(_ candidates: [ZedProject.Candidate]) -> [ZedProject] {
            ZedProject.parse(candidates, homeDirectory: home) { onDisk.contains($0) }
        }

        let projects = parse([
            candidate("/Users/philip/Sites/aical", daysAgo: 3),
            candidate("/Users/philip/Sites/payments2", daysAgo: 1),
            candidate("/Volumes/Work/detached", daysAgo: 2)
        ])
        check("every local root that still exists becomes a project", projects.count == 3)
        check(
            "projects are ordered most recently opened first",
            projects.map(\.name) == ["payments2", "detached", "aical"])
        check("the id is stable for a workspace", projects.first?.id == projects.first?.entryID)

        let workspace = parse([
            candidate(
                "/Users/philip/Desktop/notes.md\n/Users/philip/Sites/payments2",
                order: "1,0", daysAgo: 1)
        ]).first
        check("a multi-root workspace remains one project", workspace?.paths.count == 2)
        check(
            "Zed's recorded root order is preserved",
            workspace?.paths.first == "/Users/philip/Sites/payments2")
        check("a multi-root workspace names its primary root", workspace?.name == "payments2 + 1")

        check("an empty workspace contributes nothing", parse([candidate("", daysAgo: 1)]).isEmpty)
        check(
            "a workspace with a deleted root is dropped intact",
            parse([candidate("/Users/philip/Sites/aical\n/Users/philip/Sites/gone", order: "0,1", daysAgo: 1)]
            ).isEmpty)
        check(
            "a relative path is dropped",
            parse([candidate("Sites/aical", daysAgo: 1)]).isEmpty)
        check(
            "the root directory is not a project",
            parse([candidate("/", daysAgo: 1)]).isEmpty)

        let duplicated = parse([
            candidate("/Users/philip/Sites/aical", daysAgo: 9),
            candidate("/Users/philip/Sites/aical", daysAgo: 1)
        ])
        check("one workspace opened twice yields one project", duplicated.count == 1)
        check(
            "the surviving duplicate carries the more recent open",
            duplicated.first?.lastOpened == Date(timeIntervalSince1970: 999_999))

        check(
            "a malformed root order falls back to stored paths",
            parse([
                candidate(
                    "/Users/philip/Sites/aical\n/Users/philip/Sites/payments2",
                    order: "1,1", daysAgo: 1)
            ]).first?.paths
                == ["/Users/philip/Sites/aical", "/Users/philip/Sites/payments2"])
        check(
            "a path under home is abbreviated for display",
            projects.first { $0.name == "aical" }?.displayPaths == ["~/Sites"])
        check(
            "a path outside home stays absolute",
            projects.first { $0.name == "detached" }?.displayPaths == ["/Volumes/Work"])

        print("")
        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        if failures > 0 { exit(1) }
    }
}
