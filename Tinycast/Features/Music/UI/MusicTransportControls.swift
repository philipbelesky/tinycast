import SwiftUI

/// The Music window's transport row.
struct MusicTransportControls: View {
    let status: MusicPlayback.Status
    var canPrevious = true
    var isBusy = false
    let perform: (MusicCommand) -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.spacing.xl) {
            button(.previousAlbum, String(localized: "Previous album"), "backward.end.alt",
                enabled: canPrevious && !isBusy)
            button(.previousTrack, String(localized: "Previous track"), "backward.end.fill", enabled: !isBusy)
            button(.toggle, status == .playing ? String(localized: "Pause") : String(localized: "Play"),
                status == .playing ? "pause.fill" : "play.fill", enabled: !isBusy)
            button(.nextTrack, String(localized: "Next track"), "forward.end.fill", enabled: !isBusy)
            button(.nextAlbum, String(localized: "Next album"), "forward.end.alt", enabled: !isBusy)
        }
    }

    private func button(
        _ command: MusicCommand, _ title: String, _ symbol: String, enabled: Bool
    ) -> some View {
        Button { perform(command) } label: {
            SymbolImage(name: symbol, size: metrics.size.rowIcon).accessibilityLabel(title)
        }
        .help(title)
        .accessibilityLabel(title)
        .disabled(!enabled)
    }
}
