import Foundation

@main
struct LinearTest {
    /// Trimmed from a real `linear api '{ organization { … } customViews { … } }'` reply.
    static let payload = """
        {"data":{"organization":{"urlKey":"philipb","name":"philipb"},
        "customViews":{"nodes":[
        {"id":"e4fe","name":"Next Issues","slugId":"0d99bd9ec297","icon":"Checklist",
         "description":"Issues that are in Todo or Backlog status"},
        {"id":"8cd8","name":"Timekept","slugId":"c3f94e04a1e5","icon":"Hourglass","description":null},
        {"id":"b87f","name":"Projectless","slugId":"7f7b0321c1dd","icon":null,
         "description":"Issues not assigned to any project"},
        {"id":"0000","name":"  ","slugId":"deadbeef","icon":"Page","description":null},
        {"id":"1111","name":"No Slug","slugId":null,"icon":"Page","description":null}]}}}
        """

    static let credentials = """
        default = "philipb"
        workspaces = ["philipb", "platopayments"]
        """

    static let issuePayload = """
        {"data":{"organization":{"urlKey":"platopayments","name":"Plato"},
        "issues":{"nodes":[
        {"id":"issue-862","identifier":"PC-862","title":"Archived ticket",
         "url":"https://linear.app/platopayments/issue/PC-862/archived-ticket",
         "updatedAt":"2026-09-02T01:02:03.000Z","archivedAt":"2026-09-03T02:03:04.000Z",
         "state":{"name":"Done","type":"completed"}},
        {"id":"issue-861","identifier":"PC-861","title":"Repair the claim editor",
         "url":"https://linear.app/platopayments/issue/PC-861/repair-the-claim-editor",
         "updatedAt":"2026-09-03T01:02:03.000Z","archivedAt":null,
         "state":{"name":"In Progress","type":"started"}},
        {"id":"issue-elsewhere","identifier":"PC-863","title":"Wrong workspace",
         "url":"https://linear.app/elsewhere/issue/PC-863/wrong-workspace",
         "updatedAt":"2026-09-01T01:02:03.000Z","archivedAt":null,
         "state":{"name":"Todo","type":"unstarted"}},
        {"id":"issue-no-title","identifier":"PC-864","title":"  ",
         "url":"https://linear.app/platopayments/issue/PC-864/no-title",
         "updatedAt":"2026-09-01T01:02:03.000Z","archivedAt":null,
         "state":{"name":"Todo","type":"unstarted"}}]}}}
        """

    static func main() async {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // MARK: - Credentials

        let parsed = LinearCredentials.parse(credentials)
        check("every configured workspace is found", parsed.workspaces == ["philipb", "platopayments"])
        check("the default workspace is read", parsed.defaultWorkspace == "philipb")
        check(
            "a file without a workspace list yields none",
            LinearCredentials.parse("default = \"philipb\"").workspaces.isEmpty)
        check("an empty file yields none", LinearCredentials.parse("").workspaces.isEmpty)
        // The real file keeps tokens in the keyring, but a migrated one may not: never hand one back
        // as if it were a workspace slug.
        check(
            "no other key can be mistaken for a workspace",
            LinearCredentials.parse("token = \"lin_api_secret\"\nworkspaces = [\"a\"]").workspaces
                == ["a"])

        // MARK: - Views

        let views = LinearTarget.parse(Data(payload.utf8), workspaceSlug: "philipb")
        check("the workspace's url key is read", views.first?.workspaceURLKey == "philipb")
        check("a nameless view is dropped", !views.contains { $0.name.trimmed.isEmpty })
        check("a view with no slug is dropped, having nothing to open", views.count == 3)
        check(
            "views are ordered by name so the list is stable between fetches",
            views.map(\.name) == ["Next Issues", "Projectless", "Timekept"])
        check("a saved view knows it is one", views.allSatisfy { $0.kind == .saved })
        check(
            "a Linear icon maps to an SF Symbol",
            views.first { $0.name == "Next Issues" }?.symbol == "checklist")
        check(
            "an unmapped icon falls back rather than dropping the view",
            views.first { $0.name == "Projectless" }?.symbol == LinearTarget.defaultSymbol)

        check(
            "a GraphQL error payload yields no views rather than a crash",
            LinearTarget.parse(Data(#"{"errors":[{"message":"nope"}]}"#.utf8), workspaceSlug: "x")
                .isEmpty)
        check(
            "junk yields no views", LinearTarget.parse(Data("not json".utf8), workspaceSlug: "x").isEmpty)

        // MARK: - Destinations

        guard let timekept = views.first(where: { $0.name == "Timekept" }) else {
            print("FAIL  the fixture parsed")
            exit(1)
        }
        check(
            "the browser destination is the https url",
            timekept.url(opening: .browser)?.absoluteString
                == "https://linear.app/philipb/view/c3f94e04a1e5")
        check(
            "the desktop destination is the same path under linear://",
            timekept.url(opening: .app)?.absoluteString
                == "linear://linear.app/philipb/view/c3f94e04a1e5")
        check(
            "a built-in view opens a fixed path",
            LinearTarget.builtIn(for: "philipb", workspaceSlug: "philipb")
                .first { $0.name == "Inbox" }?.url(opening: .browser)?.absoluteString
                == "https://linear.app/philipb/inbox")
        check(
            "built-ins are marked as such, so they can be hidden as a group",
            LinearTarget.builtIn(for: "philipb", workspaceSlug: "philipb").allSatisfy {
                $0.kind == .builtIn
            })

        // MARK: - Identity

        check(
            "the row reads workspace then view",
            timekept.displayName == "philipb › Timekept")
        check(
            "an entry id round-trips",
            LinearTarget.id(fromEntryID: timekept.entryID) == timekept.id)
        check(
            "a foreign entry id yields nothing",
            LinearTarget.id(fromEntryID: "herdr:w2") == nil)
        // Two workspaces can both hold a view called "Terminal"; only the id keeps them apart.
        let other = LinearTarget.parse(
            Data(payload.replacingOccurrences(of: "philipb", with: "plato").utf8),
            workspaceSlug: "platopayments")
        check(
            "the same view name in two workspaces yields two ids",
            Set(views.map(\.id)).isDisjoint(with: Set(other.map(\.id))))

        // MARK: - Projects and initiatives

        // A project is what sits in the sidebar next to the saved views, and Linear hands back a
        // full url for it — including a name slug no client could reconstruct — so the path is
        // taken from that rather than built.
        let sidebar = """
            {"data":{"organization":{"urlKey":"philipb","name":"philipb"},
            "customViews":{"nodes":[]},
            "projects":{"nodes":[
            {"id":"p1","name":"TVtunes","url":"https://linear.app/philipb/project/tvtunes-d4539ca85332"},
            {"id":"p2","name":"No URL","url":null},
            {"id":"p3","name":"Elsewhere","url":"https://example.com/philipb/project/nope"}]},
            "initiatives":{"nodes":[
            {"id":"i1","name":"Q3","url":"https://linear.app/philipb/initiative/q3-abc123"}]}}}
            """
        let mixed = LinearTarget.parse(Data(sidebar.utf8), workspaceSlug: "philipb")
        check(
            "a project becomes a target",
            mixed.contains { $0.name == "TVtunes" && $0.kind == .project })
        check(
            "its path comes from Linear's own url, name slug and all",
            mixed.first { $0.name == "TVtunes" }?.path == "project/tvtunes-d4539ca85332")
        check(
            "so the browser url is the one Linear gave",
            mixed.first { $0.name == "TVtunes" }?.url(opening: .browser)?.absoluteString
                == "https://linear.app/philipb/project/tvtunes-d4539ca85332")
        check(
            "and the desktop url is that path under linear://",
            mixed.first { $0.name == "TVtunes" }?.url(opening: .app)?.absoluteString
                == "linear://linear.app/philipb/project/tvtunes-d4539ca85332")
        check(
            "an initiative becomes a target too",
            mixed.contains { $0.name == "Q3" && $0.kind == .initiative })
        check("a project with no url is dropped", !mixed.contains { $0.name == "No URL" })
        check(
            "a url outside the workspace is dropped rather than opened",
            !mixed.contains { $0.name == "Elsewhere" })
        check(
            "a payload carrying only projects still yields the workspace's url key",
            mixed.first?.workspaceURLKey == "philipb")

        // MARK: - The environment a spawned tool inherits

        // Xcode injects debugging dylibs into a Debug run and every child inherits them, which is
        // enough to break a Deno-compiled binary outright: `linear` exits 1 with "Did not find
        // magic bytes" because the injection disturbs the self-read it does to find its payload.
        let polluted = [
            "PATH": "/opt/homebrew/bin", "HOME": "/Users/philip",
            "DYLD_INSERT_LIBRARIES": "/Applications/Xcode.app/…/libMainThreadChecker.dylib",
            "DYLD_LIBRARY_PATH": "/…/Build/Products/Debug",
            "DYLD_FRAMEWORK_PATH": "/…/Build/Products/Debug",
            "__XPC_DYLD_LIBRARY_PATH": "/…/Build/Products/Debug",
            "MY_DYLD_SETTING": "kept"
        ]
        let cleaned = SubprocessEnvironment.stripping(polluted)
        check(
            "every dynamic-loader variable is dropped",
            cleaned.keys.allSatisfy { !$0.hasPrefix("DYLD_") && !$0.hasPrefix("__XPC_DYLD_") })
        check("PATH survives, or nothing would resolve", cleaned["PATH"] == "/opt/homebrew/bin")
        check("HOME survives, or the CLI loses its credentials", cleaned["HOME"] == "/Users/philip")
        check(
            "a variable that merely contains the prefix is left alone",
            cleaned["MY_DYLD_SETTING"] == "kept")
        check("nothing else is dropped", cleaned.count == 3)
        let workspaceEnvironment = LinearCredentials.workspaceEnvironment(
            cleaned.merging(["LINEAR_API_KEY": "lin_api_wrong_identity"]) { _, new in new })
        check(
            "an ambient API key cannot override a selected workspace",
            workspaceEnvironment["LINEAR_API_KEY"] == nil)
        check(
            "workspace selection keeps the rest of the safe environment",
            workspaceEnvironment == cleaned)

        // MARK: - Process lifetime

        let timeoutStarted = Date()
        let timedOut = await LinearProcessRunner.run(
            "/bin/sleep", ["2"], timeout: .milliseconds(50))
        check("a timed-out Linear process is terminated", timedOut?.signalled == true)
        check(
            "timeout returns promptly",
            Date().timeIntervalSince(timeoutStarted) < 1)

        let cancellationStarted = Date()
        let cancelledTask = Task {
            await LinearProcessRunner.run("/bin/sleep", ["2"], timeout: .seconds(5))
        }
        try? await Task.sleep(for: .milliseconds(50))
        cancelledTask.cancel()
        let cancelled = await cancelledTask.value
        check("a superseded Linear process is terminated", cancelled?.signalled == true)
        check(
            "cancellation returns promptly",
            Date().timeIntervalSince(cancellationStarted) < 1)

        // MARK: - Issue lookup grammar

        check("a bare issue number searches every team", LinearIssueLookup.parse("861") == .number(861))
        check(
            "a full identifier narrows by normalized team key",
            LinearIssueLookup.parse(" pc-861 ") == .identifier(teamKey: "PC", number: 861))
        check(
            "a team key can contain a number",
            LinearIssueLookup.parse("ref2-17") == .identifier(teamKey: "REF2", number: 17))
        check("issue zero is not a valid lookup", LinearIssueLookup.parse("0") == nil)
        check("zero padding cannot turn zero into a title", LinearIssueLookup.parse("000") == nil)
        check("a zero identifier is not a title lookup", LinearIssueLookup.parse("PC-000") == nil)
        check(
            "an overflowing issue number is rejected instead of becoming a title",
            LinearIssueLookup.parse("999999999999999999999999999999") == nil)
        check("a short title sends no request", LinearIssueLookup.parse("ab") == nil)
        check(
            "a title lookup keeps its words after trimming",
            LinearIssueLookup.parse("  claim editor  ") == .title("claim editor"))
        check(
            "mixed digits and words are a title lookup",
            LinearIssueLookup.parse("861 editor") == .title("861 editor"))

        // MARK: - Issues

        let issues = LinearTarget.parseIssues(Data(issuePayload.utf8), workspaceSlug: "platopayments")
        check("only openable issue rows are parsed", issues.count == 2)
        check(
            "issue rows are ordered by most recently updated",
            issues.map(\.issueDetails?.identifier) == ["PC-861", "PC-862"])
        guard let claim = issues.first else {
            print("FAIL  the issue fixture parsed")
            exit(1)
        }
        check("an issue knows its kind", claim.kind == .issue)
        check("an issue leads with its identifier", claim.displayName == "PC-861 · Repair the claim editor")
        check(
            "an issue identifies its workspace and state",
            claim.displaySubtitle == "platopayments · In Progress")
        check(
            "an issue opens at Linear's own path",
            claim.url(opening: .browser)?.absoluteString
                == "https://linear.app/platopayments/issue/PC-861/repair-the-claim-editor")
        check("an active issue is not archived", claim.issueDetails?.archivedAt == nil)
        check("an archived issue stays distinguishable", issues.last?.issueDetails?.archivedAt != nil)
        check(
            "an archived issue says so in the launcher",
            issues.last?.displaySubtitle == "platopayments · Done · Archived")
        check(
            "a foreign issue URL is dropped",
            !issues.contains { $0.issueDetails?.identifier == "PC-863" })

        // MARK: - Memory-only issue cache

        let lookup = LinearIssueLookup.number(861)
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        var cache = LinearIssueSearchCache()
        cache.store(issues, for: lookup, fetchedAt: fetchedAt)
        check(
            "an issue lookup is reused inside five minutes",
            cache.targets(for: lookup, now: fetchedAt.addingTimeInterval(299)) == issues)
        check(
            "an issue lookup expires at five minutes",
            cache.targets(for: lookup, now: fetchedAt.addingTimeInterval(300)) == nil)
        cache.removeAll()
        check(
            "clearing the memory cache forgets every issue", cache.targets(for: lookup, now: fetchedAt) == nil
        )

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
