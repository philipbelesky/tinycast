import Foundation

/// A resolved date phrase. `hasTime` says whether the phrase named a clock, so a bare day never
/// reaches a destination as midnight.
struct TaskDate: Equatable, Sendable {
    let date: Date
    let hasTime: Bool

    /// `2026-09-18` or `2026-09-18 17:00` — the one spelling both OmniFocus and TextFlow read.
    func canonical(calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        guard hasTime else { return day }
        return day + String(format: " %02d:%02d", parts.hour!, parts.minute!)
    }
}

/// The date grammar both destinations' own parsers overlap on, resolved here so the card can
/// show what will be stored before ↵. See docs/features/task-capture.md#dates.
enum TaskDateParser {
    private struct Clock: Equatable {
        let hour: Int
        let minute: Int
    }

    private enum Day {
        case offset(DateComponents)
        /// A named day; midnight of it unless a clock joins.
        case absolute(year: Int?, month: Int, day: Int)
        case weekday(Int)
        case today
        case tomorrow
    }

    static func parse(_ text: String, now: Date, calendar: Calendar) -> TaskDate? {
        var tokens = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        tokens.removeAll { $0 == "at" }
        guard !tokens.isEmpty, tokens.count <= 3 else { return nil }

        var clock: Clock?
        var dayTokens: [String] = []
        for token in tokens {
            if clock == nil, let parsed = parseClock(token) {
                clock = parsed
            } else {
                dayTokens.append(token)
            }
        }
        guard dayTokens.count <= 2 else { return nil }

        let day: Day?
        switch dayTokens.count {
        case 0: day = nil
        case 1: day = parseDay(dayTokens[0])
        default: day = parsePair(dayTokens[0], dayTokens[1])
        }
        if day == nil, !dayTokens.isEmpty { return nil }
        if day == nil, clock == nil { return nil }

        guard let base = resolve(day, now: now, calendar: calendar) else { return nil }
        if let clock {
            guard let dated = calendar.date(
                bySettingHour: clock.hour, minute: clock.minute, second: 0, of: base.date)
            else { return nil }
            return TaskDate(date: dated, hasTime: true)
        }
        return base
    }

    // MARK: - Days

    private static func parseDay(_ token: String) -> Day? {
        switch token {
        case "today", "tod": return .today
        case "tomorrow", "tom", "tmr": return .tomorrow
        default: break
        }
        if let weekday = weekdays[token] { return .weekday(weekday) }
        if let offset = parseOffset(token) { return .offset(offset) }
        if let iso = parseISO(token) { return iso }
        if let slashed = parseSlashed(token) { return slashed }
        return nil
    }

    private static func parsePair(_ first: String, _ second: String) -> Day? {
        if first == "next", let weekday = weekdays[second] { return .weekday(weekday) }
        if let day = Int(first), let month = months[second] { return absolute(month: month, day: day) }
        if let month = months[first], let day = Int(second) { return absolute(month: month, day: day) }
        return nil
    }

    private static func absolute(year: Int? = nil, month: Int, day: Int) -> Day? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        return .absolute(year: year, month: month, day: day)
    }

    /// `+3d`, `2w`, `+1m` (months), `+2h`, `+30min`; the sign is optional because it is implied.
    private static func parseOffset(_ token: String) -> DateComponents? {
        var body = Substring(token)
        if body.first == "+" { body = body.dropFirst() }
        let digits = body.prefix(while: \.isNumber)
        guard !digits.isEmpty, let count = Int(digits) else { return nil }
        switch body.dropFirst(digits.count) {
        case "min", "mins", "minute", "minutes": return DateComponents(minute: count)
        case "h", "hr", "hrs", "hour", "hours": return DateComponents(hour: count)
        case "d", "day", "days": return DateComponents(day: count)
        case "w", "wk", "wks", "week", "weeks": return DateComponents(day: 7 * count)
        case "m", "mo", "month", "months": return DateComponents(month: count)
        case "y", "yr", "year", "years": return DateComponents(year: count)
        default: return nil
        }
    }

    private static func parseISO(_ token: String) -> Day? {
        let parts = token.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        return absolute(year: year, month: month, day: day)
    }

    /// Day first, the way the owner's locale writes it; a year is four digits or absent.
    private static func parseSlashed(_ token: String) -> Day? {
        let parts = token.split(separator: "/", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), let day = Int(parts[0]), let month = Int(parts[1])
        else { return nil }
        if parts.count == 3 {
            guard parts[2].count == 4, let year = Int(parts[2]) else { return nil }
            return absolute(year: year, month: month, day: day)
        }
        return absolute(month: month, day: day)
    }

    // MARK: - Clocks

    private static func parseClock(_ token: String) -> Clock? {
        switch token {
        case "noon", "midday": return Clock(hour: 12, minute: 0)
        case "midnight": return Clock(hour: 0, minute: 0)
        default: break
        }
        var body = Substring(token)
        var meridiem: String?
        if body.hasSuffix("am") || body.hasSuffix("pm") {
            meridiem = String(body.suffix(2))
            body = body.dropLast(2)
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let hour = Int(parts[0]) else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) : 0
        guard let minute, (0...59).contains(minute) else { return nil }
        // A bare number is a count, not a clock: `18` stays prose and `18:00` is six in the evening.
        guard meridiem != nil || parts.count == 2 else { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            let shifted = hour % 12 + (meridiem == "pm" ? 12 : 0)
            return Clock(hour: shifted, minute: minute)
        }
        guard (0...23).contains(hour) else { return nil }
        return Clock(hour: hour, minute: minute)
    }

    // MARK: - Resolution

    private static func resolve(_ day: Day?, now: Date, calendar: Calendar) -> TaskDate? {
        let today = calendar.startOfDay(for: now)
        switch day {
        case nil: return TaskDate(date: today, hasTime: false)
        case .today: return TaskDate(date: today, hasTime: false)
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: today).map { TaskDate(date: $0, hasTime: false) }
        case .weekday(let weekday):
            let current = calendar.component(.weekday, from: today)
            var ahead = (weekday - current + 7) % 7
            if ahead == 0 { ahead = 7 }
            return calendar.date(byAdding: .day, value: ahead, to: today).map { TaskDate(date: $0, hasTime: false) }
        case .offset(let components):
            let keepsClock = components.hour != nil || components.minute != nil
            let from = keepsClock ? now : today
            return calendar.date(byAdding: components, to: from).map { TaskDate(date: $0, hasTime: keepsClock) }
        case .absolute(let year, let month, let day):
            let thisYear = calendar.component(.year, from: today)
            var parts = DateComponents(year: year ?? thisYear, month: month, day: day)
            guard var date = calendar.date(from: parts), calendar.component(.day, from: date) == day
            else { return nil }
            // A day/month already behind us means the next one, the way a person says it.
            if year == nil, date < today {
                parts.year = thisYear + 1
                guard let next = calendar.date(from: parts) else { return nil }
                date = next
            }
            return TaskDate(date: date, hasTime: false)
        }
    }

    private static let weekdays: [String: Int] = [
        "sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "weds": 4, "wednesday": 4, "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6, "sat": 7, "saturday": 7
    ]

    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4,
        "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8, "sep": 9,
        "sept": 9, "september": 9, "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12,
        "december": 12
    ]
}
