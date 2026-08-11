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

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
