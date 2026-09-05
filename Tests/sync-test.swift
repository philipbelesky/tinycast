import Foundation

@main
struct SyncTest {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        func decide(
            _ trigger: SyncTrigger, local: String, remote: String?,
            syncedLocal: String?, syncedRemote: String?
        ) -> SyncDecision {
            SyncPlan.decide(
                trigger: trigger, localHash: local, remoteHash: remote,
                syncedLocalHash: syncedLocal, syncedRemoteHash: syncedRemote)
        }

        // Every field non-nil, so the privacy check below covers a fully populated payload.
        func maximalSettings() -> SettingsBackup.SettingsData {
            var s = SettingsBackup.SettingsData()
            s.clipboardRetentionDays = 7
            s.clipboardDisabledApps = ["com.example.app"]
            s.launchAtLogin = true
            s.hyperKey = "capsLock"
            s.hyperKeyIncludesShift = true
            s.hyperKeyQuickPress = "escape"
            s.emojiSkinTone = "default"
            s.showInMenuBar = true
            s.popToRootSeconds = 30
            s.compactMode = true
            s.showFavoritesInCompactMode = true
            s.searchScopes = ["apps"]
            s.openOnCursorScreen = true
            s.customCommandsEnabled = true
            s.customCommandsShowInLauncher = true
            s.snippetsShowInLauncher = true
            s.windowManagementEnabled = true
            s.windowManagementShowInLauncher = true
            s.windowGap = 8
            s.windowCycleOnRepeat = true
            s.quicklinksEnabled = true
            s.quicklinksShowInLauncher = true
            s.quicklinkOpensNewWindow = true
            s.quicklinkSelectionFallback = "clipboard"
            s.quicklinkConfirmsBeforeDelete = true
            s.webSearchEnabled = true
            s.webSearchShowInLauncher = true
            s.webSearchEngine = "google"
            s.herdrEnabled = true
            s.herdrShowInLauncher = true
            s.herdrTerminalBundleID = "com.apple.Terminal"
            s.vsCodeEnabled = true
            s.vsCodeShowInLauncher = true
            s.scopeKeywords = ["l": "linear"]
            s.linearShowInLauncher = true
            s.linearDestination = "app"
            return s
        }

        // MARK: Envelope round-trip

        var backup = SettingsBackup()
        var settings = SettingsBackup.SettingsData()
        settings.compactMode = true
        settings.scopeKeywords = ["l": "linear"]
        backup.settings = settings

        let envelope = SyncEnvelope(
            writtenAt: Date(timeIntervalSince1970: 1_755_000_000),
            writtenBy: "Test Mac",
            backup: backup)
        do {
            let data = try envelope.encoded()
            let decoded = try SyncEnvelope(json: data)
            check("envelope round-trips writtenBy", decoded.writtenBy == "Test Mac")
            check(
                "envelope round-trips writtenAt to the second",
                abs(decoded.writtenAt.timeIntervalSince(envelope.writtenAt)) < 1)
            check(
                "envelope round-trips a settings field",
                decoded.backup.settings?.compactMode == true)
            check(
                "envelope encoding is compact",
                String(bytes: data, encoding: .utf8)?.contains("\n") == false)
        } catch {
            check("envelope round-trips (\(error))", false)
        }

        let minimal = #"{"backup":{"version":4},"writtenAt":"2026-08-11T00:00:00Z","writtenBy":"Other Mac"}"#
        check(
            "a minimal envelope decodes, so partial payloads degrade rather than fail",
            (try? SyncEnvelope(json: Data(minimal.utf8))) != nil)

        // MARK: Content hash

        do {
            let first = try SyncEnvelope.contentHash(of: backup)
            let second = try SyncEnvelope.contentHash(of: backup)
            check("contentHash is stable across encodes", first == second)
            check("contentHash is 64 hex characters", first.count == 64
                && first.allSatisfy { $0.isHexDigit })

            var changed = backup
            changed.settings?.compactMode = false
            let changedHash = try SyncEnvelope.contentHash(of: changed)
            check("contentHash changes when a setting changes", changedHash != first)
        } catch {
            check("contentHash computes (\(error))", false)
        }

        // MARK: Decision table

        for trigger in [SyncTrigger.startup, .localChange, .remoteNotification] {
            check(
                "an absent remote never clears local settings (\(trigger))",
                decide(trigger, local: "l1", remote: nil, syncedLocal: "l1", syncedRemote: "r1")
                    == .writeLocal)
            check(
                "nothing changed is a noop (\(trigger))",
                decide(trigger, local: "l1", remote: "r1", syncedLocal: "l1", syncedRemote: "r1")
                    == .noop)
            check(
                "identical content is a noop even before first sync (\(trigger))",
                decide(trigger, local: "same", remote: "same", syncedLocal: nil, syncedRemote: nil)
                    == .noop)
            check(
                "a local-only change writes local (\(trigger))",
                decide(trigger, local: "l2", remote: "r1", syncedLocal: "l1", syncedRemote: "r1")
                    == .writeLocal)
            check(
                "a remote-only change applies remote (\(trigger))",
                decide(trigger, local: "l1", remote: "r2", syncedLocal: "l1", syncedRemote: "r1")
                    == .applyRemote)
        }

        check(
            "a conflict during a local change keeps the local edit",
            decide(.localChange, local: "l2", remote: "r2", syncedLocal: "l1", syncedRemote: "r1")
                == .writeLocal)
        check(
            "a conflict at startup applies remote",
            decide(.startup, local: "l2", remote: "r2", syncedLocal: "l1", syncedRemote: "r1")
                == .applyRemote)
        check(
            "a conflict on a push applies remote",
            decide(.remoteNotification, local: "l2", remote: "r2", syncedLocal: "l1", syncedRemote: "r1")
                == .applyRemote)

        check(
            "first contact during a local change writes local",
            decide(.localChange, local: "l1", remote: "r1", syncedLocal: nil, syncedRemote: nil)
                == .writeLocal)
        check(
            "first contact at startup applies remote",
            decide(.startup, local: "l1", remote: "r1", syncedLocal: nil, syncedRemote: nil)
                == .applyRemote)
        check(
            "first contact on a push applies remote",
            decide(.remoteNotification, local: "l1", remote: "r1", syncedLocal: nil, syncedRemote: nil)
                == .applyRemote)

        // MARK: Quota

        check("a small payload fits the quota", SyncPlan.fitsQuota(byteCount: 10_000))
        check(
            "the cap itself fits",
            SyncPlan.fitsQuota(byteCount: SyncPlan.maximumPayloadBytes))
        check(
            "past the cap does not fit",
            !SyncPlan.fitsQuota(byteCount: SyncPlan.maximumPayloadBytes + 1))

        // MARK: Privacy — the sync payload inherits the backup exclusions

        var maximal = SettingsBackup()
        maximal.settings = maximalSettings()
        let full = SyncEnvelope(writtenAt: Date(timeIntervalSince1970: 0), writtenBy: "A", backup: maximal)
        let encodedFull = (try? full.encoded()).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        check(
            "a fully populated envelope never carries snippetsEnabled",
            !encodedFull.isEmpty && !encodedFull.contains("snippetsEnabled"))
        check(
            "snippetsEnabled stays deliberately excluded from the shared payload",
            SettingsBackupCoverage.deliberatelyExcluded[AppSettingsKey.snippetsEnabled.rawValue] != nil)

        // MARK: Hotkeys — both clipboard slots ride the synced payload

        let slug = CommandID.clipboardHistory.rawValue
        var hotkeys = SettingsBackup.HotkeyBackup()
        hotkeys.commands = [slug: .combo(KeyShortcut(carbonKeyCode: 9, carbonModifiers: 0))]
        hotkeys.commandAlternates = [slug: .doubleTap(.command)]
        var bound = SettingsBackup()
        bound.hotkeys = hotkeys
        let boundEnvelope = SyncEnvelope(
            writtenAt: Date(timeIntervalSince1970: 0), writtenBy: "A", backup: bound)
        let roundTripped = (try? boundEnvelope.encoded()).flatMap { try? SyncEnvelope(json: $0) }
        check(
            "the primary clipboard chord survives the envelope round trip",
            roundTripped?.backup.hotkeys?.commands?[slug] == hotkeys.commands?[slug])
        check(
            "the alternate clipboard chord rides alongside it",
            roundTripped?.backup.hotkeys?.commandAlternates?[slug] == .doubleTap(.command))

        // A Mac still on the older build writes an envelope with no alternates map at all.
        let priorJSON = Data(
            (#"{"backup":{"hotkeys":{"commands":{"command:clipboard-history":"#
                + #"{"doubleTap":{"_0":"command"}}}}},"#
                + #""writtenAt":"1970-01-01T00:00:00Z","writtenBy":"B"}"#).utf8)
        let prior = try? SyncEnvelope(json: priorJSON)
        check(
            "an envelope written before the alternate existed still decodes",
            prior?.backup.hotkeys?.commands?[slug] == .doubleTap(.command))
        check(
            "and reads as no alternate rather than failing outright",
            prior != nil && prior?.backup.hotkeys?.commandAlternates == nil)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
