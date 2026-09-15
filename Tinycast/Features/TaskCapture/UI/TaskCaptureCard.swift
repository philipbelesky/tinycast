import SwiftUI

/// The capture preview above nothing: the task as it will be stored, one chip per attribute,
/// so what ↵ adds is never a surprise. Selectable like a row; ↵ adds.
struct TaskCaptureCard: View {
    @Environment(\.metrics) private var metrics
    let preview: TaskCapturePreview
    let selected: Bool

    private var task: CapturedTask { preview.task }

    var body: some View {
        HStack(alignment: .top, spacing: metrics.spacing.xl) {
            SymbolImage(name: preview.destination.symbol, size: metrics.size.headerIconSlot)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                Text(task.isTitled ? task.title : "New task")
                    .font(metrics.typography.calcResult.weight(.semibold))
                    .foregroundStyle(task.isTitled ? .primary : .tertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if chips.isEmpty {
                    Text(hint)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    TaskCaptureChipFlow(chips: chips)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.xxl)
        .leadCard(selected: selected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var hint: String {
        "Type a task — @project #tag due fri 5pm ! // note"
    }

    private var chips: [TaskCaptureChip] {
        let unsupported = Set(preview.unsupported)
        var chips: [TaskCaptureChip] = []
        for field in task.fields {
            let dropped = unsupported.contains(field)
            switch field {
            case .project:
                chips.append(
                    .init(
                        field, symbol: preview.projectUnknown ? "questionmark.folder" : "folder",
                        text: task.project ?? "", dropped: dropped || preview.projectUnknown,
                        unreadable: preview.projectUnknown))
            case .tags:
                chips += task.tags.map { .init(field, symbol: "number", text: $0, dropped: dropped) }
            case .due:
                chips.append(
                    dateChip(
                        field, symbol: "calendar", label: "Due", date: task.due,
                        raw: task.unresolvedDue, dropped: dropped))
            case .defer:
                chips.append(
                    dateChip(
                        field, symbol: "calendar.badge.clock", label: "Defer", date: task.deferDate,
                        raw: task.unresolvedDefer, dropped: dropped))
            case .flag:
                chips.append(.init(field, symbol: "flag.fill", text: "Flagged", dropped: dropped))
            case .estimate:
                let estimate = TaskCaptureFormat.estimate(task.estimateMinutes ?? 0)
                chips.append(.init(field, symbol: "timer", text: estimate, dropped: dropped))
            case .note:
                chips.append(.init(field, symbol: "text.alignleft", text: task.note ?? "", dropped: dropped))
            case .status:
                chips.append(.init(field, symbol: "circle.lefthalf.filled", text: task.status?.title ?? "", dropped: dropped))
            case .assignee:
                chips.append(.init(field, symbol: "person", text: task.assignee ?? "", dropped: dropped))
            }
        }
        return chips
    }

    private func dateChip(
        _ field: CapturedTask.Field, symbol: String, label: String, date: TaskDate?, raw: String?,
        dropped: Bool
    ) -> TaskCaptureChip {
        guard let date else {
            return .init(
                field, symbol: "questionmark.circle", text: "\(label) “\(raw ?? "")”", dropped: dropped,
                unreadable: true)
        }
        return .init(field, symbol: symbol, text: "\(label) \(TaskCaptureFormat.date(date))", dropped: dropped)
    }

    private var accessibilityLabel: String {
        let parts = [task.isTitled ? task.title : "New task"] + chips.map(\.text)
        return parts.joined(separator: ", ") + ", add to \(preview.destination.title)"
    }
}

/// One attribute as the card states it. Dropped means the destination will not keep it; unreadable
/// means Tinycast could not resolve it and will not send it.
struct TaskCaptureChip: Identifiable, Equatable {
    let field: CapturedTask.Field
    let symbol: String
    let text: String
    let dropped: Bool
    var unreadable = false

    init(_ field: CapturedTask.Field, symbol: String, text: String, dropped: Bool, unreadable: Bool = false) {
        self.field = field
        self.symbol = symbol
        self.text = text
        self.dropped = dropped
        self.unreadable = unreadable
    }

    var id: String { "\(field)-\(text)" }
}

/// Chips wrap onto as many lines as they need; a long tag list must not truncate a due date.
private struct TaskCaptureChipFlow: View {
    @Environment(\.metrics) private var metrics
    let chips: [TaskCaptureChip]

    var body: some View {
        ChipFlowLayout(spacing: metrics.spacing.xs) {
            ForEach(chips) { chip in
                TaskCaptureChipView(chip: chip)
            }
        }
    }
}

private struct TaskCaptureChipView: View {
    @Environment(\.metrics) private var metrics
    let chip: TaskCaptureChip

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            Image(systemName: chip.symbol)
                .symbolRenderingMode(.hierarchical)
            Text(chip.text)
                .strikethrough(chip.dropped)
                .lineLimit(1)
        }
        .font(metrics.typography.keyCap)
        .foregroundStyle(tint)
        .padding(.horizontal, metrics.spacing.sm)
        .padding(.vertical, metrics.spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.keyCap, style: .continuous)
                .fill(Theme.Colors.controlSurface)
        )
        .help(help ?? "")
    }

    private var tint: Color {
        if chip.unreadable { return Theme.Colors.destructive }
        return chip.dropped ? Theme.Colors.textTertiary : Theme.Colors.textSecondary
    }

    private var help: String? {
        if chip.unreadable {
            return chip.field == .project
                ? "No project by this name, so the task goes to the inbox"
                : "Not understood as a date, so it will not be sent"
        }
        return chip.dropped ? "This destination has nowhere to keep it" : nil
    }
}

/// Wraps its children like words in a paragraph — SwiftUI ships no flow container.
private struct ChipFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(proposal: proposal, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let limit = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + needed > limit, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += extra
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

/// How the card spells a date and a duration; both destinations get the canonical form instead.
enum TaskCaptureFormat {
    static func date(_ value: TaskDate, now: Date = Date(), calendar: Calendar = .current) -> String {
        let day: String
        if calendar.isDateInToday(value.date) {
            day = "today"
        } else if calendar.isDateInTomorrow(value.date) {
            day = "tomorrow"
        } else {
            let sameYear = calendar.component(.year, from: value.date) == calendar.component(.year, from: now)
            day = value.date.formatted(
                sameYear
                    ? .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                    : .dateTime.day().month(.abbreviated).year())
        }
        guard value.hasTime else { return day }
        return day + ", " + value.date.formatted(.dateTime.hour().minute())
    }

    static func estimate(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}

/// The card's ⌘K menu: the add itself, and the TaskPaper it would send, for pasting elsewhere.
@MainActor
enum TaskCaptureActionsMenu {
    static func content(preview: TaskCapturePreview, core: AppCore) -> PopoverMenuContent {
        PopoverMenuContent(
            header: preview.task.isTitled ? preview.task.title : "New task",
            items: [
                PopoverMenuItem(
                    title: "Add to \(preview.destination.title)", systemImage: preview.destination.symbol,
                    shortcut: "↵"
                ) {
                    core.taskCaptureCoordinator.capture(preview)
                },
                PopoverMenuItem(title: "Copy as TaskPaper", systemImage: "doc.on.doc") {
                    core.taskCaptureCoordinator.copyTaskPaper(preview)
                }
            ])
    }
}
