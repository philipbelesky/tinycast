import Foundation

/// The capture query grammar: prose is the title, and every marker pulls one attribute out of it.
/// See docs/features/task-capture.md#the-grammar.
enum TaskCaptureGrammar {
    /// A `@` or `#` token still being typed, which the catalog can complete.
    struct CompletionContext: Equatable, Sendable {
        enum Kind: Sendable { case project, tag }
        let kind: Kind
        let prefix: String
    }

    static func parse(_ query: String, now: Date, calendar: Calendar) -> CapturedTask {
        var task = CapturedTask()
        var prose: [String] = []
        var tokens = tokenize(query, note: &task.note)
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            if let keyword = dateKeyword(token) {
                // The phrase runs to the next marker; the longest readable head of it is the date.
                var phrase = keyword.attached.map { [$0] } ?? []
                while index < tokens.count, !isMarker(tokens[index]), dateKeyword(tokens[index]) == nil {
                    phrase.append(tokens[index])
                    index += 1
                }
                guard !phrase.isEmpty else {
                    prose.append(token)
                    continue
                }
                let (date, consumed) = longestDate(in: phrase, now: now, calendar: calendar)
                let leftover = phrase.dropFirst(consumed)
                tokens.insert(contentsOf: leftover, at: index)
                apply(keyword.field, date: date, phrase: phrase.joined(separator: " "), to: &task)
                continue
            }
            guard apply(token, to: &task, now: now, calendar: calendar) else {
                prose.append(token)
                continue
            }
        }
        task.title = prose.joined(separator: " ")
        return task
    }

    // MARK: - Completion

    static func completionContext(in query: String) -> CompletionContext? {
        guard let token = trailingMarkerToken(in: query) else { return nil }
        let kind: CompletionContext.Kind = token.marker == "@" ? .project : .tag
        // A known attribute is a value, not a name; a finished quote is a name already given.
        if kind == .project, isAttribute(token.body) { return nil }
        if token.quoted, token.closed { return nil }
        if !token.quoted, query.last?.isWhitespace == true { return nil }
        return CompletionContext(kind: kind, prefix: token.body)
    }

    /// The query with its trailing `@`/`#` token replaced by `value`, quoted where it needs to be.
    static func accepting(_ value: String, in query: String) -> String {
        guard let token = trailingMarkerToken(in: query) else { return query }
        let spelled = value.contains(where: \.isWhitespace) ? "\"\(value)\"" : value
        return String(query[..<token.start]) + token.marker + spelled + " "
    }

    private struct MarkerToken {
        let start: String.Index
        let marker: String
        let body: String
        let quoted: Bool
        let closed: Bool
    }

    /// The last `@`/`#` that starts a token, with what follows it to the end of the query.
    private static func trailingMarkerToken(in query: String) -> MarkerToken? {
        var index = query.endIndex
        while index > query.startIndex {
            let previous = query.index(before: index)
            let character = query[previous]
            let startsToken =
                (character == "@" || character == "#")
                && (previous == query.startIndex || query[query.index(before: previous)].isWhitespace)
            guard startsToken else {
                index = previous
                continue
            }
            let rest = query[index...]
            if rest.first == "\"" {
                let inner = rest.dropFirst()
                let closed = inner.contains("\"")
                let body = closed ? String(inner.prefix(while: { $0 != "\"" })) : String(inner)
                return MarkerToken(
                    start: previous, marker: String(character), body: body, quoted: true, closed: closed)
            }
            guard !rest.contains(where: \.isWhitespace) else { return nil }
            return MarkerToken(
                start: previous, marker: String(character), body: String(rest), quoted: false, closed: false)
        }
        return nil
    }

    // MARK: - Tokens

    /// Splits on whitespace, keeping a quoted or parenthesised value whole; `//` ends the scan.
    private static func tokenize(_ query: String, note: inout String?) -> [String] {
        var tokens: [String] = []
        var index = query.startIndex
        while index < query.endIndex {
            if query[index].isWhitespace {
                index = query.index(after: index)
                continue
            }
            if query[index...].hasPrefix("//") {
                let rest = query[query.index(index, offsetBy: 2)...].trimmingCharacters(in: .whitespaces)
                note = rest.isEmpty ? nil : rest
                break
            }
            let start = index
            let marker = query[index]
            index = query.index(after: index)
            if "@#>".contains(marker), index < query.endIndex, query[index] == "\"" {
                index = closingQuote(in: query, after: index)
            } else if marker == "@" {
                index = attributeEnd(in: query, from: index)
            } else {
                index = wordEnd(in: query, from: index)
            }
            tokens.append(String(query[start..<index]))
        }
        return tokens
    }

    private static func closingQuote(in query: String, after opening: String.Index) -> String.Index {
        var index = query.index(after: opening)
        while index < query.endIndex, query[index] != "\"" { index = query.index(after: index) }
        return index < query.endIndex ? query.index(after: index) : index
    }

    /// `@due(fri 5pm)` is one token, spaces and all; `@Groceries` ends at the next space.
    private static func attributeEnd(in query: String, from start: String.Index) -> String.Index {
        var index = start
        while index < query.endIndex, !query[index].isWhitespace, query[index] != "(" {
            index = query.index(after: index)
        }
        guard index < query.endIndex, query[index] == "(" else { return index }
        while index < query.endIndex, query[index] != ")" { index = query.index(after: index) }
        return index < query.endIndex ? query.index(after: index) : index
    }

    private static func wordEnd(in query: String, from start: String.Index) -> String.Index {
        var index = start
        while index < query.endIndex, !query[index].isWhitespace { index = query.index(after: index) }
        return index
    }

    // MARK: - Classification

    private struct DateKeyword {
        let field: CapturedTask.Field
        /// The value glued on with a colon, as in `due:fri`.
        let attached: String?
    }

    private static func dateKeyword(_ token: String) -> DateKeyword? {
        let lowered = token.lowercased()
        for (word, field) in [("due", CapturedTask.Field.due), ("defer", .defer)] {
            if lowered == word { return DateKeyword(field: field, attached: nil) }
            if lowered.hasPrefix(word + ":"), token.count > word.count + 1 {
                return DateKeyword(field: field, attached: String(token.dropFirst(word.count + 1)))
            }
        }
        return nil
    }

    private static func isMarker(_ token: String) -> Bool {
        guard let first = token.first else { return false }
        if token == "!" { return true }
        if "@#~>".contains(first) { return token.count > 1 }
        if first == "/" { return status(from: token) != nil }
        return false
    }

    /// The longest head of the phrase that reads as a date, and how many tokens it took.
    private static func longestDate(
        in phrase: [String], now: Date, calendar: Calendar
    ) -> (TaskDate?, Int) {
        for count in stride(from: min(phrase.count, 3), through: 1, by: -1) {
            let head = phrase.prefix(count).joined(separator: " ")
            if let date = TaskDateParser.parse(head, now: now, calendar: calendar) { return (date, count) }
        }
        return (nil, phrase.count)
    }

    private static func apply(
        _ field: CapturedTask.Field, date: TaskDate?, phrase: String, to task: inout CapturedTask
    ) {
        switch field {
        case .due:
            task.due = date
            task.unresolvedDue = date == nil ? phrase : nil
        default:
            task.deferDate = date
            task.unresolvedDefer = date == nil ? phrase : nil
        }
    }

    /// True when the token was an attribute and has been applied; false leaves it as prose.
    private static func apply(_ token: String, to task: inout CapturedTask, now: Date, calendar: Calendar) -> Bool {
        guard let first = token.first, token.count > 1 || token == "!" else { return false }
        let body = String(token.dropFirst())
        switch first {
        case "!":
            guard token == "!" else { return false }
            task.flagged = true
        case "#":
            task.tags.append(unquoted(body))
        case ">":
            task.assignee = unquoted(body)
        case "~":
            guard let minutes = estimate(body) else { return false }
            task.estimateMinutes = minutes
        case "/":
            guard let status = status(from: token) else { return false }
            task.status = status
        case "@":
            return applyAttribute(body, to: &task, now: now, calendar: calendar)
        default:
            return false
        }
        return true
    }

    private static func applyAttribute(
        _ body: String, to task: inout CapturedTask, now: Date, calendar: Calendar
    ) -> Bool {
        guard let open = body.firstIndex(of: "("), body.hasSuffix(")") else {
            if body.lowercased() == "flagged" || body.lowercased() == "flag" {
                task.flagged = true
            } else if task.project == nil {
                task.project = unquoted(body)
            }
            return true
        }
        let name = body[..<open].lowercased()
        let value = String(body[body.index(after: open)..<body.index(before: body.endIndex)])
            .trimmingCharacters(in: .whitespaces)
        switch name {
        case "due", "defer":
            let date = TaskDateParser.parse(value, now: now, calendar: calendar)
            apply(name == "due" ? .due : .defer, date: date, phrase: value, to: &task)
        case "tags", "tag":
            task.tags += value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        case "project", "in": task.project = value
        case "flagged", "flag": task.flagged = true
        case "estimate":
            guard let minutes = estimate(value) else { return false }
            task.estimateMinutes = minutes
        case "note": task.note = value
        case "status":
            guard let status = status(from: "/" + value) else { return false }
            task.status = status
        case "assignee", "assign": task.assignee = value
        // Unknown attributes are what a project name with brackets looks like.
        default: task.project = task.project ?? body
        }
        return true
    }

    private static func isAttribute(_ body: String) -> Bool {
        let name = body.prefix(while: { $0 != "(" }).lowercased()
        return body.contains("(") && attributeNames.contains(name)
            || ["flagged", "flag"].contains(body.lowercased())
    }

    private static let attributeNames: Set<String> = [
        "due", "defer", "tags", "tag", "project", "in", "flagged", "flag", "estimate", "note",
        "status", "assignee", "assign"
    ]

    private static func status(from token: String) -> TaskStatus? {
        switch token.lowercased() {
        case "/inprogress", "/in-progress", "/progress", "/started": .inProgress
        case "/onhold", "/on-hold", "/hold", "/waiting": .onHold
        default: nil
        }
    }

    /// `30m`, `2h`, `1h30m` — minutes, and only minutes, is what both destinations store.
    private static func estimate(_ text: String) -> Int? {
        var minutes = 0
        var digits = ""
        var seen = false
        for character in text.lowercased() {
            if character.isNumber {
                digits.append(character)
                continue
            }
            guard let count = Int(digits) else { return nil }
            switch character {
            case "h": minutes += count * 60
            case "m": minutes += count
            default: return nil
            }
            digits = ""
            seen = true
        }
        guard digits.isEmpty, seen else { return nil }
        return minutes
    }

    private static func unquoted(_ text: String) -> String {
        guard text.hasPrefix("\""), text.count >= 2 else { return text }
        return String(text.dropFirst().dropLast(text.hasSuffix("\"") ? 1 : 0))
    }
}
