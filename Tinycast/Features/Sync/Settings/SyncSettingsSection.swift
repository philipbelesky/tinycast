import SwiftUI

/// The Backup pane's sync section; the consent gate copies the currency sheet's shape.
struct SyncSettingsSection: View {
    @Environment(AppCore.self) private var core
    private var sync: SettingsSyncStore { core.settingsSync }
    @State private var askingConsent = false
    @State private var foundRemote: SyncEnvelope?

    var body: some View {
        Section {
            // Not bound to the flag: flipping on opens the sheet, so it springs back.
            Toggle(
                isOn: Binding(
                    get: { sync.isEnabled },
                    set: { wantsOn in
                        if wantsOn {
                            askingConsent = true
                        } else {
                            sync.setEnabled(false)
                        }
                    })
            ) {
                Text("Sync Settings via iCloud")
                Text(status)
            }
            .sheet(isPresented: $askingConsent, onDismiss: { foundRemote = nil }) {
                if let envelope = foundRemote {
                    SyncRemoteChoiceSheet(
                        envelope: envelope,
                        onCancel: { askingConsent = false },
                        onKeepLocal: {
                            askingConsent = false
                            sync.resolveEnable(applyingRemote: false)
                        },
                        onApplyRemote: {
                            askingConsent = false
                            sync.resolveEnable(applyingRemote: true)
                        })
                } else {
                    SyncConsentSheet(
                        onCancel: { askingConsent = false },
                        onAccept: acceptConsent)
                }
            }
        } header: {
            Text("iCloud Sync")
        }
    }

    private func acceptConsent() {
        switch sync.requestEnable() {
        case .notSignedIn:
            askingConsent = false
            Task {
                await core.showNotice(
                    title: "Sign in to iCloud",
                    message: "Settings sync needs an iCloud account. "
                        + "Sign in from System Settings, then try again.",
                    symbol: "icloud.slash", tone: .neutral)
            }
        case .unavailable:
            askingConsent = false
            Task {
                _ = await core.reportFailure(
                    title: "iCloud Sync Unavailable",
                    message: "iCloud key-value storage isn't available for this build.",
                    symbol: "icloud.slash", recovery: nil)
            }
        case .enabledFresh:
            askingConsent = false
        case .remoteFound(let envelope):
            foundRemote = envelope
        }
    }

    /// Carries the off-state promise: nothing leaves the Mac until the switch is on.
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

/// The consent step: where settings go, how often, what travels, and what never does.
private struct SyncConsentSheet: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "icloud")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.green)
                Text("Turn on iCloud settings sync?")
                    .font(.headline)
            }

            Text(
                "Tinycast saves your settings, keyboard shortcuts, custom commands, quicklinks, "
                    + "favorites, and hidden items to \(SettingsSyncStore.provider) on every "
                    + "change, and automatically applies what your other Macs save — including "
                    + "shortcuts and custom commands. Consent switches like snippet expansion "
                    + "never sync. Turning it off removes the iCloud copy."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Spacer()
                Button("Not Now", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Enable", action: onAccept)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 420)
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
