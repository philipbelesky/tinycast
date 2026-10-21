import SwiftUI

/// History is local observed track starts, not a claim that every track was listened to in full.
struct MusicHistoryView: View {
    @Environment(MusicCoordinator.self) private var coordinator
    @State private var query = ""

    private var entries: [MusicListeningHistory.Entry] {
        coordinator.service.store.listeningHistory.entries.filter { entry in
            query.isEmpty || entry.playback.track.localizedStandardContains(query)
                || entry.playback.artist.localizedStandardContains(query)
                || entry.playback.album.localizedStandardContains(query)
                || entry.player.title.localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Toggle("Save listening history on this Mac", isOn: Binding(
                get: { coordinator.service.store.historyEnabled },
                set: { coordinator.setHistoryEnabled($0) }))
                .padding(Theme.Spacing.xxl)
            if entries.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No listening history" : "No matching tracks",
                    systemImage: "clock", description: Text(query.isEmpty
                        ? "Tracks appear as connected players start playing. Up to 1,000 starts are kept on this Mac."
                        : "Try another title, artist, album or player."))
                    .frame(maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(entry.playback.track).font(.headline)
                        Text([entry.playback.artist, entry.playback.album].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(entry.player.title)
                            Spacer()
                            Text(entry.playedAt, format: .dateTime.day().month().hour().minute())
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .searchable(text: $query, prompt: "Search listening history")
        .toolbar {
            Button { Task { await coordinator.clearHistory() } } label: {
                SymbolImage(name: "trash", size: Theme.Size.rowIcon)
            }
                .help("Clear History…")
                .accessibilityLabel("Clear History…")
                .disabled(coordinator.service.store.listeningHistory.entries.isEmpty)
        }
    }
}
