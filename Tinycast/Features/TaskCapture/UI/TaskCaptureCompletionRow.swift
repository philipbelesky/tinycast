import SwiftUI

/// One project or tag the catalog offers for the token being typed; ↵ writes it into the field.
struct TaskCaptureCompletionRow: View {
    @Environment(\.metrics) private var metrics
    let completion: TaskCaptureCompletion
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Image(systemName: completion.kind == .project ? "folder" : "number")
                .font(metrics.typography.rowTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
            Text(completion.value)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.middle)
            if let detail = completion.detail {
                Text(detail)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(completion.kind == .project ? "Project" : "Tag")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(selected ? Theme.Colors.selection : (hovered ? Theme.Colors.rowHover : .clear))
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(completion.value), \(completion.kind == .project ? "project" : "tag")")
        .accessibilityAddTraits(.isButton)
    }
}
