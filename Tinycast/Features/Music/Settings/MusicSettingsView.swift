import SwiftUI

/// Device access and monitoring remain per-Mac grants rather than synced feature preferences.
struct MusicSettingsView: View {
    @Environment(MusicCoordinator.self) private var coordinator

    var body: some View {
        Form {
            Section {
                Button("Open Music Controls", action: coordinator.show)
                ForEach(MusicPlayer.allCases) { player in
                    Toggle("Connect to \(player.title)", isOn: Binding(
                        get: { coordinator.service.store.monitored.contains(player) },
                        set: { coordinator.setMonitoring(player, enabled: $0) }))
                }
            } header: {
                SettingsSectionHeader(.musicPlayers)
            } footer: {
                Text("Open the player first. Connecting allows Tinycast to read playback "
                    + "and run controls through macOS Automation.")
            }

            Section {
                Toggle(isOn: Binding(get: { coordinator.service.store.historyEnabled },
                    set: { coordinator.setHistoryEnabled($0) })) {
                    SettingsRowTitle(.musicHistory, "Save listening history")
                }
                Button("Clear History…") { Task { await coordinator.clearHistory() } }
            } header: {
                SettingsSectionHeader(.musicHistory)
            } footer: {
                Text("Keeps the latest 1,000 observed track starts from connected players on this Mac. "
                    + "History is not synced or exported.")
            }

            Section {
                Toggle(isOn: Binding(get: { coordinator.service.store.remoteEnabled },
                    set: { coordinator.setRemoteEnabled($0) })) {
                    SettingsRowTitle(.musicGadget, "Allow gadget connections")
                }
                Picker(selection: Binding(get: { coordinator.service.store.selectedPlayer },
                    set: { coordinator.selectPlayer($0) })) {
                    ForEach(MusicPlayer.allCases) { Text($0.title).tag($0) }
                } label: { SettingsRowTitle(.musicGadget, "Gadget player") }
                LabeledContent("Connection", value: coordinator.service.remote.status)
                if coordinator.service.store.remoteEnabled {
                    LabeledContent("Address", value: "ws://<Mac IP>:\(coordinator.service.port)/device")
                        .textSelection(.enabled)
                    RevealableSecureField(title: "Pairing token", text: .constant(coordinator.service.pairingToken))
                    Button("Reset Pairing…") { Task { await coordinator.rotatePairing() } }
                    if let percent = coordinator.service.remote.batteryPercent {
                        LabeledContent("Gadget battery", value: "\(percent)%")
                    }
                }
            } header: {
                SettingsSectionHeader(.musicGadget)
            } footer: {
                Text("Uses the gadget's existing unencrypted WebSocket protocol on your trusted LAN. "
                    + "Pair using this Mac's IP address and the token. Reset Pairing revokes existing connections.")
            }

            FeatureCommandsSection(owner: .music, anchor: .musicCommands)
            if let error = coordinator.service.store.persistenceError ?? coordinator.service.pairingError {
                Section { Text(error).foregroundStyle(Theme.Colors.destructive) }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.music)
    }
}
