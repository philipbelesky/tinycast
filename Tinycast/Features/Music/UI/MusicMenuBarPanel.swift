import SwiftUI

/// What the menu bar panel draws. A value, so a tracking menu can replace it without waiting on Observation.
struct MusicMenuBarModel: Equatable, Sendable {
    var playerName: String?
    var track: String
    var detail: String
    var rating: MusicRating?
    var status: MusicPlayback.Status
    var canPrevious: Bool
    var isBusy: Bool
    var player: MusicPlayer
}

/// Track, stars and transport for the menu bar item. Stars are omitted when the track cannot be rated.
struct MusicMenuBarPanel: View {
    let model: MusicMenuBarModel
    let rate: (Int) -> Void
    let perform: (MusicCommand) -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            if let playerName = model.playerName {
                Text(verbatim: playerName)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            Text(verbatim: model.track)
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            if !model.detail.isEmpty {
                Text(verbatim: model.detail)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            if let rating = model.rating {
                MusicStarRow(rating: rating, isBusy: model.isBusy, rate: rate)
            }
            MusicTransportControls(
                status: model.status, canPrevious: model.canPrevious, isBusy: model.isBusy, perform: perform)
        }
        .padding(metrics.spacing.lg)
        .frame(width: metrics.size.menuWidth, alignment: .leading)
    }
}

private struct MusicStarRow: View {
    let rating: MusicRating
    var isBusy: Bool
    let rate: (Int) -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            ForEach(1...5, id: \.self) { star in
                Button { rate(star) } label: {
                    SymbolImage(name: symbol(for: star), size: metrics.size.rowIcon)
                        .foregroundStyle(rating.fill(for: star) == .empty
                            ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityLabel(String(localized: "Rate \(star) stars"))
                .accessibilityAddTraits(isCurrent(star) ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Rating"))
        .accessibilityValue(valueText)
    }

    private var valueText: String {
        if rating.halfStars == 0 { return String(localized: "Unrated") }
        if rating.hasHalfStar { return String(localized: "\(rating.wholeStars).5 stars") }
        return String(localized: "\(rating.wholeStars) stars")
    }

    private func isCurrent(_ star: Int) -> Bool {
        star == rating.wholeStars && !rating.hasHalfStar && rating.halfStars > 0
    }

    private func symbol(for star: Int) -> String {
        switch rating.fill(for: star) {
        case .full: "star.fill"
        case .half: "star.leadinghalf.filled"
        case .empty: "star"
        }
    }
}

#if DEBUG
    private extension MusicMenuBarModel {
        static func preview(
            rating: MusicRating?, status: MusicPlayback.Status = .playing, playerName: String? = nil
        ) -> Self {
            Self(playerName: playerName, track: "Trunkline", detail: "Hex — Album", rating: rating,
                status: status, canPrevious: true, isBusy: false, player: .appleMusic)
        }
    }

    #Preview("Unrated") {
        MusicMenuBarPanel(model: .preview(rating: .unrated), rate: { _ in }, perform: { _ in })
            .previewOnPanel()
    }

    #Preview("Rated 3.5") {
        MusicMenuBarPanel(
            model: .preview(rating: MusicRating(halfStars: 7), playerName: "Apple Music"),
            rate: { _ in }, perform: { _ in })
            .previewOnPanel()
    }

    #Preview("Cannot rate") {
        MusicMenuBarPanel(model: .preview(rating: nil), rate: { _ in }, perform: { _ in })
            .previewOnPanel()
    }

    #Preview("Paused") {
        MusicMenuBarPanel(
            model: .preview(rating: .whole(2), status: .paused), rate: { _ in }, perform: { _ in })
            .previewOnPanel()
    }
#endif
