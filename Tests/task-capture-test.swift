import Foundation

@main
struct TaskCaptureTest {
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

        // Tuesday 15 September 2026, 10:30 in Melbourne — fixed, so a weekday resolves the same
        // on every machine that runs this.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        calendar.locale = Locale(identifier: "en_AU")
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 10, minute: 30))!

        func parse(_ query: String) -> CapturedTask {
            TaskCaptureGrammar.parse(query, now: now, calendar: calendar)
        }
        func has(_ argv: [String], _ run: [String]) -> Bool {
            argv.indices.contains { argv[$0...].starts(with: run) }
        }
        func date(_ text: String) -> String? {
            TaskDateParser.parse(text, now: now, calendar: calendar)?.canonical(calendar: calendar)
        }

        // MARK: - Dates

        check("today is the date alone", date("today") == "2026-09-15")
        check("tomorrow", date("tomorrow") == "2026-09-16")
        check("tom abbreviates tomorrow", date("tom") == "2026-09-16")
        check("a weekday is the coming one", date("fri") == "2026-09-18")
        check("a full weekday name", date("friday") == "2026-09-18")
        check("today's weekday name means a week away", date("tue") == "2026-09-22")
        check("next weekday reads the same", date("next mon") == "2026-09-21")
        check("+3d", date("+3d") == "2026-09-18")
        check("a bare count of days", date("3d") == "2026-09-18")
        check("+2w", date("+2w") == "2026-09-29")
        check("+1m is a month", date("+1m") == "2026-10-15")
        check("+1y", date("+1y") == "2027-09-15")
        check("+2h keeps the clock", date("+2h") == "2026-09-15 12:30")
        check("+30min", date("+30min") == "2026-09-15 11:00")
        check("an ISO date", date("2026-12-24") == "2026-12-24")
        check("an ISO date with a time", date("2026-12-24 17:00") == "2026-12-24 17:00")
        check("day/month is day first", date("18/9") == "2026-09-18")
        check("day/month/year", date("1/2/2027") == "2027-02-01")
        check("a past day/month rolls to next year", date("1/3") == "2027-03-01")
        check("day then month name", date("18 sep") == "2026-09-18")
        check("month name then day", date("sep 18") == "2026-09-18")
        check("a full month name", date("december 24") == "2026-12-24")
        check("a time alone is today", date("5pm") == "2026-09-15 17:00")
        check("a time with minutes", date("5:30pm") == "2026-09-15 17:30")
        check("a 24-hour clock", date("17:00") == "2026-09-15 17:00")
        check("noon", date("noon") == "2026-09-15 12:00")
        check("a date and a time", date("fri 5pm") == "2026-09-18 17:00")
        check("a date, at, and a time", date("fri at 5pm") == "2026-09-18 17:00")
        check("time then date also works", date("5pm fri") == "2026-09-18 17:00")
        check("case is ignored", date("FRI 5PM") == "2026-09-18 17:00")
        check("prose is not a date", date("the report") == nil)
        check("an empty string is not a date", date("") == nil)
        check("a lone number is not a date", date("18") == nil)
        check("hasTime is false for a day", TaskDateParser.parse("fri", now: now, calendar: calendar)?.hasTime == false)
        check("hasTime is true for a clock", TaskDateParser.parse("fri 5pm", now: now, calendar: calendar)?.hasTime == true)

        // MARK: - The grammar

        let plain = parse("Buy milk")
        check("a bare query is the title", plain.title == "Buy milk")
        check("a bare query has no project", plain.project == nil)
        check("a bare query has no tags", plain.tags.isEmpty)
        check("a bare query is not flagged", !plain.flagged)

        let full = parse(
            "Buy milk @Groceries #errands #\"Home : Kitchen\" due fri 5pm defer tom ! ~30m >Hermes /inprogress "
                + "// ask about crown")
        check("the title is the prose left over", full.title == "Buy milk")
        check("@Word is the project", full.project == "Groceries")
        check("#tags collect in order", full.tags == ["errands", "Home : Kitchen"])
        check("due reads the date phrase that follows it", full.due?.canonical(calendar: calendar) == "2026-09-18 17:00")
        check("defer reads its phrase too", full.deferDate?.canonical(calendar: calendar) == "2026-09-16")
        check("a lone ! flags", full.flagged)
        check("~30m is an estimate in minutes", full.estimateMinutes == 30)
        check(">name assigns", full.assignee == "Hermes")
        check("/status sets a status", full.status == .inProgress)
        check("// starts the note", full.note == "ask about crown")

        check("a quoted project keeps its spaces", parse("Plant bulbs @\"Back garden\"").project == "Back garden")
        check("a project may sit mid-title", parse("Call @Plato Sam about the claim").title == "Call Sam about the claim")
        check("~1h30m", parse("Fix it ~1h30m").estimateMinutes == 90)
        check("~2h", parse("Fix it ~2h").estimateMinutes == 120)
        check("/hold is on hold", parse("Wait /hold").status == .onHold)
        check("/onhold is on hold too", parse("Wait /onhold").status == .onHold)
        check("an unknown status is prose", parse("Try /fast").title == "Try /fast")
        check("a ! inside a word is prose", parse("Wow!").title == "Wow!")
        check("an email address is not a project", parse("Email sam@plato.io").title == "Email sam@plato.io")
        check("a lone @ is prose", parse("Meet @ noon").title == "Meet @ noon")
        check("a URL fragment is not a tag", parse("Read https://x.io/#top").title == "Read https://x.io/#top")

        let dueEnd = parse("Send invoice due fri")
        check("due at the end of the title", dueEnd.title == "Send invoice")
        check("…resolves", dueEnd.due?.canonical(calendar: calendar) == "2026-09-18")
        let dueMid = parse("Send invoice due fri #work")
        check("a marker ends the date phrase", dueMid.title == "Send invoice")
        check("…and the tag still lands", dueMid.tags == ["work"])
        let unparsed = parse("Pay rent due whenever")
        check("an unreadable date phrase stays a phrase", unparsed.due == nil)
        check("…and is reported so the card can say so", unparsed.unresolvedDue == "whenever")
        let dueThenProse = parse("Send invoice due fri and call Sam")
        check("prose after a date phrase goes back to the title", dueThenProse.title == "Send invoice and call Sam")
        check("…having given up only what read as a date", dueThenProse.due?.canonical(calendar: calendar) == "2026-09-18")
        check(
            "a date phrase may be three words",
            parse("x due next fri 5pm").due?.canonical(calendar: calendar) == "2026-09-18 17:00")
        check("a due with nothing after it is prose", parse("Rent is due").title == "Rent is due")
        check("due: compact form", parse("Rent due:fri").due?.canonical(calendar: calendar) == "2026-09-18")
        check("Due capitalised still reads", parse("Rent Due tomorrow").due?.canonical(calendar: calendar) == "2026-09-16")

        // MARK: - TaskPaper attributes

        let attributed = parse(
            "Buy milk @due(fri 5pm) @defer(+2d) @tags(errands, home) @flagged @estimate(45m) @project(Groceries) "
                + "@note(ask) @status(onhold) @assignee(Sam)")
        check("@due(…) is a due", attributed.due?.canonical(calendar: calendar) == "2026-09-18 17:00")
        check("@defer(…)", attributed.deferDate?.canonical(calendar: calendar) == "2026-09-17")
        check("@tags(a, b) splits on commas", attributed.tags == ["errands", "home"])
        check("@flagged", attributed.flagged)
        check("@estimate(45m)", attributed.estimateMinutes == 45)
        check("@project(…)", attributed.project == "Groceries")
        check("@note(…)", attributed.note == "ask")
        check("@status(onhold)", attributed.status == .onHold)
        check("@assignee(…)", attributed.assignee == "Sam")
        check("the title survives the attributes", attributed.title == "Buy milk")
        check("@in(…) is @project", parse("x @in(Garden)").project == "Garden")
        check("@Word( with an unknown name is a project", parse("x @Garden(bulbs)").project == "Garden(bulbs)")
        check("attributes are case-insensitive", parse("x @Due(fri)").due != nil)

        // MARK: - Completion context

        func context(_ query: String) -> TaskCaptureGrammar.CompletionContext? {
            TaskCaptureGrammar.completionContext(in: query)
        }
        check("a trailing @ asks for a project", context("Buy milk @")?.kind == .project)
        check("a trailing @Gr carries its prefix", context("Buy milk @Gr")?.prefix == "Gr")
        check("a trailing # asks for a tag", context("Buy milk #ho")?.kind == .tag)
        check("a quoted prefix is unwrapped", context("x @\"Back g")?.prefix == "Back g")
        check("a closed quote is not a prompt", context("x @\"Back garden\"") == nil)
        check("a finished token is not a prompt", context("Buy milk @Groceries ") == nil)
        check("a known attribute is not a prompt", context("x @due(") == nil)
        check("prose is not a prompt", context("Buy milk") == nil)
        check("an email is not a prompt", context("Email sam@plato") == nil)
        check(
            "accepting a completion replaces the token and adds a space",
            TaskCaptureGrammar.accepting("Groceries", in: "Buy milk @Gr") == "Buy milk @Groceries ")
        check(
            "a completion with spaces is quoted",
            TaskCaptureGrammar.accepting("Back garden", in: "x @Ba") == "x @\"Back garden\" ")
        check(
            "a tag path is quoted for its spaces",
            TaskCaptureGrammar.accepting("Home : Kitchen", in: "x #ho") == "x #\"Home : Kitchen\" ")
        check(
            "a half-typed quote is replaced whole",
            TaskCaptureGrammar.accepting("Back garden", in: "x @\"Back g") == "x @\"Back garden\" ")

        // MARK: - The catalog

        let catalog = TaskCaptureCatalog(
            projects: [
                .init(name: "Groceries", path: "Groceries", folder: "Home"),
                .init(name: "Garden", path: "Garden", folder: "Home"),
                .init(name: "Unsorted", path: "Plato/Unsorted", folder: "Plato"),
                .init(name: "Unsorted", path: "Personal/Unsorted", folder: "Personal")
            ],
            tags: ["errands", "Home : Kitchen", "Home : Office", "Any : Mac"])
        let projectHits = catalog.completions(for: .init(kind: .project, prefix: "g"))
        check("projects match by prefix, in catalog order", projectHits.map(\.value) == ["Groceries", "Garden"])
        check("a project completion carries its folder", projectHits.first?.detail == "Home")
        let unsorted = catalog.completions(for: .init(kind: .project, prefix: "uns"))
        check("a colliding name completes to its path", unsorted.map(\.value) == ["Plato/Unsorted", "Personal/Unsorted"])
        let tagHits = catalog.completions(for: .init(kind: .tag, prefix: "kit"))
        check("a tag matches any path component", tagHits.map(\.value) == ["Home : Kitchen"])
        check("an empty prefix lists everything", catalog.completions(for: .init(kind: .tag, prefix: "")).count == 4)
        check(
            "a substring match ranks after a prefix match",
            catalog.completions(for: .init(kind: .tag, prefix: "o")).map(\.value).first == "Home : Office")

        // MARK: - OmniFocus

        let omni = TaskPaperFormatter.taskPaper(full, calendar: calendar)
        check("a TaskPaper line leads with the title", omni.hasPrefix("- Buy milk"))
        check("…carries the due", omni.contains("@due(2026-09-18 17:00)"))
        check("…the defer", omni.contains("@defer(2026-09-16)"))
        check("…the flag", omni.contains("@flagged"))
        check("…every tag in one attribute", omni.contains("@tags(errands, Home : Kitchen)"))
        check("…the estimate", omni.contains("@estimate(30m)"))
        check("…and the note on an indented line", omni.hasSuffix("\n\task about crown"))
        check("…but no status, which OmniFocus has no notion of", !omni.contains("status"))
        check("a bare task is one line", TaskPaperFormatter.taskPaper(plain, calendar: calendar) == "- Buy milk")
        let inboxURL = TaskPaperFormatter.omniFocusURL(plain, calendar: calendar)
        check(
            "a bare task pastes into the inbox",
            inboxURL?.absoluteString == "omnifocus:///paste?target=inbox&content=-%20Buy%20milk")
        let projectURL = TaskPaperFormatter.omniFocusURL(parse("Plant bulbs @\"Back garden\""), calendar: calendar)
        check("a project routes the paste to it", projectURL?.absoluteString.contains("target=/task/Back%20garden") == true)
        check("an empty title makes no URL", TaskPaperFormatter.omniFocusURL(parse("@Garden"), calendar: calendar) == nil)

        // MARK: - TextFlow

        let argv = TextFlowCommand.addArguments(full, calendar: calendar)
        check("add leads with the verb and the title", Array(argv.prefix(2)) == ["add", "Buy milk"])
        check("--in carries the project", has(argv, ["--in", "Groceries"]))
        check("--tags repeats per tag", has(argv, ["--tags", "errands", "--tags", "Home : Kitchen"]))
        check("--due", has(argv, ["--due", "2026-09-18 17:00"]))
        check("--defer", has(argv, ["--defer", "2026-09-16"]))
        check("--flag", argv.contains("--flag"))
        check("--assignee", has(argv, ["--assignee", "Hermes"]))
        check("--note", has(argv, ["--note", "ask about crown"]))
        check("the result is JSON with a stable id", argv.suffix(2) == ["--json", "--assign-id"])
        check(
            "a bare task is minimal",
            TextFlowCommand.addArguments(plain, calendar: calendar) == ["add", "Buy milk", "--json", "--assign-id"])
        check(
            "status is a second command",
            TextFlowCommand.statusArguments(reference: "@k6r35h", status: .inProgress)
                == ["status", "@k6r35h", "inprogress", "--json"])
        check(
            "on hold spells textflow's way",
            TextFlowCommand.statusArguments(reference: "@x", status: .onHold).contains("onhold"))

        let addReply = #"""
            {"result":"write","operation":"add","item":{"reference":"@k6r35h","address":"Groceries/Buy milk",
            "text":"Buy milk"},"changed":["Home/Groceries.md"],"replayed":false}
            """#
        check("an add reply yields its reference", TextFlowCommand.parseAddResult(Data(addReply.utf8))?.reference == "@k6r35h")
        check("…and its address", TextFlowCommand.parseAddResult(Data(addReply.utf8))?.address == "Groceries/Buy milk")
        let errorReply = #"{"error":{"code":"notFound","message":"No project named Grocery","candidates":["Groceries"]}}"#
        check("an error reply yields nothing", TextFlowCommand.parseAddResult(Data(errorReply.utf8)) == nil)
        check("…but its message is readable", TextFlowCommand.errorMessage(Data(errorReply.utf8)) == "No project named Grocery")

        let projectsReply = #"""
            {"result":"projects","root":{"name":"","path":[],"projects":[{"address":"Loose","reference":"Loose",
            "status":"active","folder":[],"text":"Loose"}],"subfolders":[{"name":"Home","path":["Home"],
            "projects":[{"address":"Garden","reference":"Garden","status":"active","folder":["Home"],
            "text":"Garden"},{"address":"Old","reference":"Old","status":"done","folder":["Home"],
            "text":"Old"}],"subfolders":[{"name":"Sub","path":["Home","Sub"],
            "projects":[{"address":"Personal/Unsorted","reference":"Personal/Unsorted","status":"active",
            "folder":["Home","Sub"],"text":"Unsorted"}],"subfolders":[]}]}]}}
            """#
        let projects = TextFlowCommand.parseProjects(Data(projectsReply.utf8))
        check("projects walk every folder", projects.map(\.path) == ["Loose", "Garden", "Personal/Unsorted"])
        check("a project's name is its text", projects.last?.name == "Unsorted")
        check("a project's folder is the innermost", projects.last?.folder == "Sub")
        check("a root project has no folder", projects.first?.folder == nil)
        check("a finished project is left out", !projects.map(\.path).contains("Old"))
        let tagsReply = #"""
            {"result":"tags","tags":[{"name":"Home","path":"Home","onHold":false,"children":[{"name":"Kitchen",
            "path":"Home : Kitchen","onHold":false,"children":[],"entries":[]}],"entries":[]},{"name":"Lazy",
            "path":"Lazy","onHold":false,"children":[],"entries":[]}]}
            """#
        check(
            "tags flatten to their paths",
            TextFlowCommand.parseTags(Data(tagsReply.utf8)) == ["Home", "Home : Kitchen", "Lazy"])

        // MARK: - OmniFocus catalog

        let omniReply = #"""
            {"projects":[{"name":"Garden","folder":"Home"},{"name":"Loose","folder":null}],"tags":["Errands",
            "Home : Kitchen"]}
            """#
        let omniCatalog = OmniFocusCatalog.parse(Data(omniReply.utf8))
        check("OmniFocus projects carry their folder", omniCatalog?.projects.first?.folder == "Home")
        check("a folderless project has none", omniCatalog?.projects.last?.folder == nil)
        check("OmniFocus tags are paths", omniCatalog?.tags == ["Errands", "Home : Kitchen"])
        check("the script asks for active projects only", OmniFocusCatalog.script.contains("active status"))

        // MARK: - What each destination can take

        let preview = TaskCapturePreview(task: full, destination: .omniFocus)
        check("OmniFocus cannot take a status", preview.unsupported == [.status, .assignee])
        check(
            "TextFlow cannot take an estimate",
            TaskCapturePreview(task: full, destination: .textFlow).unsupported == [.estimate])
        check("a titled task can be captured", preview.canCapture)
        check("an untitled task cannot", !TaskCapturePreview(task: parse("@Garden #x"), destination: .textFlow).canCapture)
        check("an unresolved due does not block capture", TaskCapturePreview(task: unparsed, destination: .textFlow).canCapture)

        // MARK: - A project the destination has never heard of

        check("a catalog knows a project by name", catalog.knows(project: "groceries"))
        check("…and by path", catalog.knows(project: "personal/unsorted"))
        check("…and not otherwise", !catalog.knows(project: "Grocery"))
        let typo = parse("Buy milk @Grocery")
        let checked = TaskCapturePreview(task: typo, destination: .omniFocus, catalog: catalog)
        check("an unknown project is flagged when the catalog is loaded", checked.projectUnknown)
        check("…and is not sent", checked.sent.project == nil)
        check("…but the title still is", checked.sent.title == "Buy milk")
        let unchecked = TaskCapturePreview(task: typo, destination: .omniFocus, catalog: nil)
        check(
            "with no catalog the project is taken on trust",
            !unchecked.projectUnknown && unchecked.sent.project == "Grocery")
        let known = TaskCapturePreview(task: parse("Buy milk @Groceries"), destination: .omniFocus, catalog: catalog)
        check("a known project passes", !known.projectUnknown && known.sent.project == "Groceries")
        check("no project is never unknown", !TaskCapturePreview(task: plain, destination: .omniFocus, catalog: catalog).projectUnknown)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
