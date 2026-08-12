import SwiftUI

/// The Backup pane's sync section. Turning it back on still asks which way first contact goes.
struct SyncSettingsSection: View {
    @Environment(AppCore.self) private var core
    private var sync: SettingsSyncStore { core.settingsSync }
    @State private var foundRemote: SyncEnvelope?

    var body: some View {
        Section {
            // Not bound to the flag: a differing remote opens the sheet, so it springs back.
            Toggle(
                isOn: Binding(
                    get: { sync.isEnabled },
                    set: { wantsOn in
                        if wantsOn {
                            enable()
                        } else {
                            sync.setEnabled(false)
                        }
                    })
            ) {
                Text("Sync Settings via iCloud")
                Text(status)
            }
            .sheet(
                isPresented: Binding(
                    get: { foundRemote != nil }, set: { if !$0 { foundRemote = nil } })
            ) {
                if let envelope = foundRemote {
                    SyncRemoteChoiceSheet(
                        envelope: envelope,
                        onCancel: { foundRemote = nil },
                        onKeepLocal: {
                            foundRemote = nil
                            sync.resolveEnable(applyingRemote: false)
                        },
                        onApplyRemote: {
                            foundRemote = nil
                            sync.resolveEnable(applyingRemote: true)
                        })
                }
            }
        } header: {
            Text("iCloud Sync")
        }
    }

    /// The probes outlived the consent step: an unprovisioned build has to say so out loud.
    private func enable() {
        switch sync.requestEnable() {
        case .notSignedIn:
            Task {
                await core.showNotice(
                    title: "Sign in to iCloud",
                    message: "Settings sync needs an iCloud account. "
                        + "Sign in from System Settings, then try again.",
                    symbol: "icloud.slash", tone: .neutral)
            }
        case .unavailable:
            Task {
                _ = await core.reportFailure(
                    title: "iCloud Sync Unavailable",
                    message: "iCloud key-value storage isn't available for this build.",
                    symbol: "icloud.slash", recovery: nil)
            }
        case .enabledFresh:
            break
        case .remoteFound(let envelope):
            foundRemote = envelope
        }
    }

    /// Carries the off-state promise: nothing leaves the Mac while the switch is off.
    private var status: String {
        guard sync.isEnabled else {
            return "Off — nothing is sent to iCloud."
        }
        guard let at = sync.lastSyncedAt, let by = sync.lastSyncedBy else {
            return "\(SettingsSyncStore.provider) · not synced yet."
        }
        let stamp = at.formatted(date: .abbreviated, time: .shortened)
        return "\(SettingsSyncStore.provider) · \(by), \(stamp)."
    }
}

/// First contact with an existing envelope: the user picks a direction, never a silent merge.
private struct SyncRemoteChoiceSheet: View {
    let envelope: SyncEnvelope
    let onCancel: () -> Void
    let onKeepLocal: () -> Void
    let onApplyRemote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "icloud")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.green)
                Text("iCloud already has settings")
                    .font(.headline)
            }

            Text(
                "\(envelope.writtenBy) saved settings on "
                    + envelope.writtenAt.formatted(date: .abbreviated, time: .shortened)
                    + ". Apply them to this Mac, or replace the iCloud copy with this Mac's "
                    + "settings?"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Spacer()
                Button("Not Now", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Keep This Mac's", action: onKeepLocal)
                Button("Apply iCloud Settings", action: onApplyRemote)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 440)
    }
}
