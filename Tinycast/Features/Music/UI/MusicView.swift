import SwiftUI

/// Both players remain visible; choosing the gadget target does not start or pause either app.
struct MusicView: View {
    @Environment(MusicCoordinator.self) private var coordinator

    var body: some View {
        NavigationStack {
            TabView {
                Tab("Players", systemImage: "music.note") {
                    Form {
                        ForEach(MusicPlayer.allCases) { player in
                            MusicPlayerSection(player: player)
                        }
                        Section("Gadget") {
                            Picker("Control", selection: Binding(
                                get: { coordinator.service.store.selectedPlayer },
                                set: { coordinator.selectPlayer($0) })) {
                                ForEach(MusicPlayer.allCases) { Text($0.title).tag($0) }
                            }
                            LabeledContent("Connection", value: coordinator.service.remote.status)
                            if coordinator.service.remote.connectedDevices > 0 {
                                LabeledContent("Connected gadgets", value: "\(coordinator.service.remote.connectedDevices)")
                            }
                        }
                        if let error = coordinator.service.store.persistenceError ?? coordinator.service.pairingError {
                            Section { Text(error).foregroundStyle(Theme.Colors.destructive) }
                        }
                    }
                    .formStyle(.grouped)
                }
                Tab("Listening History", systemImage: "clock") {
                    MusicHistoryView()
                }
            }
            .navigationTitle("Music")
            .toolbar {
                Button(action: coordinator.refresh) {
                    SymbolImage(name: "arrow.clockwise", size: Theme.Size.rowIcon)
                }
                    .help("Refresh playback")
                    .accessibilityLabel("Refresh playback")
                    .disabled(coordinator.service.store.isBusy)
                Button(action: coordinator.showSettings) {
                    SymbolImage(name: "gearshape", size: Theme.Size.rowIcon)
                }
                .help("Music Settings…")
                .accessibilityLabel("Music Settings…")
            }
        }
    }
}

private struct MusicPlayerSection: View {
    let player: MusicPlayer
    @Environment(MusicCoordinator.self) private var coordinator
    private var store: MusicStore { coordinator.service.store }
    private var state: MusicPlayback { store.snapshots[player] ?? MusicPlayback() }
    private var connected: Bool { store.monitored.contains(player) }

    var body: some View {
        Section(player.title) {
            Toggle("Connect to \(player.title)", isOn: Binding(
                get: { connected }, set: { coordinator.setMonitoring(player, enabled: $0) }))
            if connected {
                if state.status == .error {
                    Text(state.error).foregroundStyle(Theme.Colors.destructive)
                    Button("Reconnect") { coordinator.reconnect(player) }
                        .disabled(store.isBusy)
                } else {
                    LabeledContent("Track", value: state.track.isEmpty ? "Nothing playing" : state.track)
                    if !state.artist.isEmpty { LabeledContent("Artist", value: state.artist) }
                    if !state.album.isEmpty { LabeledContent("Album", value: state.album) }
                    LabeledContent("Playback", value: state.status.rawValue.capitalized)
                    HStack(spacing: Theme.Spacing.xl) {
                        control(.previousAlbum, "Previous album", "backward.end.alt")
                            .disabled(!coordinator.service.canPrevious(player))
                        control(.previousTrack, "Previous track", "backward.end.fill")
                        control(.toggle, state.status == .playing ? "Pause" : "Play",
                            state.status == .playing ? "pause.fill" : "play.fill")
                        control(.nextTrack, "Next track", "forward.end.fill")
                        control(.nextAlbum, "Next album", "forward.end.alt")
                    }
                    .disabled(store.isBusy)
                }
            } else {
                Text("Open the player, then connect to enable controls and playback monitoring.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func control(_ command: MusicCommand, _ title: String, _ symbol: String) -> some View {
        Button { coordinator.perform(command, player: player) } label: {
            SymbolImage(name: symbol, size: Theme.Size.rowIcon).accessibilityLabel(title)
        }
        .help(title)
        .accessibilityLabel(title)
    }
}
