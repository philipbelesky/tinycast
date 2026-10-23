# Music

## Invariants

- `AppCore` owns `MusicStore`, `MusicPlaybackService` and `MusicCoordinator`. Closing Music, Settings or the palette leaves playback monitoring and the gadget listener running; quitting Tinycast stops them.
- Monitoring, listening-history capture and incoming gadget connections are separate, default-off, per-Mac grants. Settings imports, iCloud sync and `settings.json` cannot enable them. The selected gadget player and command customizations can appear in `settings.json`.
- Native automation targets a running player. Multiple TVTunes copies are refused rather than selecting an arbitrary version. Connecting requests macOS Automation permission. Permission failures and missing scripting support require a deliberate reconnect; other failures retry state reads after ten seconds. Recovery never replays a playback command.
- All playback effects share one bounded serial command boundary. Disconnecting invalidates queued operations and late results. An uncertain command is never replayed automatically.
- Gadget command IDs retain the most recent 256 results, including failures, across connections and source changes for one Tinycast process. A reused ID with a different command is refused. This deduplication does not survive a Tinycast restart; the firmware must retain its existing no-replay-on-reconnect behavior.
- Listening history stores observed track starts, not completed listens or audio-output confirmation. Pause/resume does not duplicate a track. Recording requires a connected player and the explicit history switch. The latest 1,000 entries are stored locally; they are neither synced nor included in backups.
- Album navigation history is separate from listening history, partitioned by player and limited to 100 albums for the process lifetime. Previous walks back; Next walks forward before choosing a different random library album. History advances only after the selected album is observed playing or paused.
- Pairing tokens live in the channel's login Keychain scope and never appear in URLs, logs, settings files or history. Reset Pairing disconnects existing clients. The current firmware uses plaintext WebSockets, so the listener is explicitly intended for a trusted LAN.

## Surfaces

Open **Music Controls** from the launcher, its configurable alias/hotkey, or Tinycast's menu. Players shows both Apple Music and TVTunes with track/album navigation and transport. Selecting the gadget player changes which app gadget commands address; it does not start or pause either app. Listening History is searchable by track, artist, album and player.

**Settings → Music** holds the connection switches, local history capture, gadget enablement, target selection and pairing token. The launch-at-login setting remains Tinycast's existing General preference. Debug uses port **8797**, independently of the installed app's **8796**, so testing cannot take over an installed gadget endpoint.

## Playback boundary

`Service/MusicAutomationRunner.swift` implements the injected `MusicPlayerControlling` boundary. TVTunes uses its `TVtn` scripting suite and stable media IDs, added in the TVTunes repository by commit `07be23d`. Apple Music uses its scripting interface and the user's saved library. Its queue playlists are named `Tinycast <session>`; only a previous playlist owned by this service instance may be deleted. Albums contain only saved library tracks, ordered by disc then track number. Same-title albums by the same album artist can merge; singles and EPs count as albums.

`MusicPlaybackService` owns sequencing, periodic state reads, album selection and command results. `MusicStore` owns channel-local preferences and `music-history.json` under `AppPaths.applicationSupport()`. A damaged or oversized history file is preserved until an explicit Clear History action. Model types do not import UI frameworks or perform I/O.

## Gadget protocol

The existing Hermes Gadget album remote can connect to `ws://<Mac IP>:8796/device` with the revealed token. The listener negotiates `album-remote-v1`, requires an authenticated JSON hello within five seconds, refuses browser-origin handshakes, bounds messages to 4 KiB and admits four concurrent connections. It uses macOS 26's `NetworkListener` and structured connection tasks; stopping or resetting pairing cancels them.

Commands are `toggle`, `pause`, `previous_album`, `next_album`, `previous_track` and `next_track`. State uses the existing `type`, `source`, `status`, `album`, `artist`, `track`, `error`, `can_previous` and optional `ack` fields. A `toggle` reply waits up to one second for the player's status to change, because Apple Music answers play/pause before its state flips; the gadget treats that reply as the confirmed glyph. Authenticated battery telemetry updates the settings readout. State continues to be sent while a player command is pending; writes and unauthenticated handshakes have deadlines. There is no HTTP management panel and no Python runtime dependency.

## Verification

`music-test` covers album navigation, listening-history identity and the wire schema. `music-service-test` uses an injected player and clock to exercise serialized playback, duplicate and conflicting IDs, failure deduplication, delayed recovery of state reads without command replay or permission requests, explicit reconnect after denial, source changes, history persistence, damaged-history preservation and disconnects during a pending read. `music-remote-test` connects real WebSocket clients to an ephemeral loopback listener and checks authentication, handshake deadlines, acknowledgements, telemetry, malformed/oversized commands and repeated reconnects. `music-confirmation-test` exercises delayed album changes, transient fallback, matching tracks in an unrelated queue, and toggle replies that precede the player's status change. None of the harnesses controls a personal music player or reads pairing secrets.

Live acceptance additionally needs the signed Tinycast app's Automation permissions, one updated TVTunes instance with a loaded Plex/Jellyfin library, Apple Music library playback, and the physical gadget provisioned with Tinycast's endpoint/token. Headphone output, Mac sleep/wake and the gadget's physical controls require separate acceptance.

## Acceptance record: 21 October 2026

A fresh signed Debug build passed, with no new compiler or Music lint warnings. The full suite passed 105 of 107 harnesses; `file-search-test` (undeclared file type) and `form-input-test` (native rendering) also fail on an untouched snapshot of the starting commit. All four Music harnesses pass, including a real loopback listener with authentication failures, handshake timeout, oversized payloads and six reconnects.

The running Dev app was visually inspected in Players, Listening History and Settings. Live Apple Music checks covered metadata, random library albums, confirmed queue changes, Previous album, pause and observed-track history. A delayed queue update found during that check was fixed and verified in the final app. Playback was left paused. Closing Music Settings leaves the Music window running, and closing windows does not quit the service.

Only the updated TVTunes development copy is now running, with its library visibly loaded. The installed Tinycast successfully reads both players, including live Apple Music metadata and TVTunes's stopped state. Both connection switches, local history and the LAN listener were enabled by the owner and persisted to the stable channel's preferences.

The physical gadget `7C:0C:5F:42:33:38` was provisioned over USB with `ws://192.168.1.100:8796/device` and the stable Tinycast Keychain token; secret bytes and serial echoes were suppressed. The console confirmed both setting saves and `music_connected=true`, and Tinycast visibly reported one authenticated device. The current gadget target is Apple Music. TVTunes playback, physical controls/acknowledgements, sleep/wake and headphone output remain separate acceptance checks.

The separate machine-wide CFPreferences failure was recovered: the user agent had 511 descriptors against a 512 limit, including 503 directory handles to TextFlow Dev's preferences container, and logged “Too many open files.” After backing up Tinycast's disk and cached preferences and restarting only that user agent, disposable-domain write/read/delete and a normal Tinycast Dev quit/relaunch passed. The selected TVTunes target survived relaunch. The underlying descriptor-leak trigger remains unproven and is recorded in the existing TextFlow Papercut `@rl4qbs`. No preference domains, permissions or limits were reset. History-file persistence also works.

The Developer ID Release archive and export passed, and `Scripts/build-dmg.sh` installed and relaunched `/Applications/Tinycast.app`, produced `build/Tinycast-0.1.0.dmg` and copied it to the usual iCloud Resources folder. `Scripts/verify-signature.sh /Applications/Tinycast.app` passed. The signed review app, previous installed app and build/test/lint/package evidence are retained under the ignored `build/music-verification-20261021/` directory. The Dev review process was quit after installation so the stable app owns final setup.

A subsequent gadget report exposed a cached Apple Music timeout: a manual reconnect immediately read the current playing track, but the old service stopped polling after every error. The service regression test reproduced that failure before the fix. Recovery now retries only state reads after ten seconds, preserves command-result deduplication and keeps permission/unsupported-scripting failures blocked until explicit reconnect.

The recovery build passed all Music tests, a fresh Debug build with no new compiler warnings, and lint with no new Music warnings. The full suite again passed 105 of 107 harnesses with the same two baseline failures. The signed Release was installed and its DMG refreshed in iCloud Resources. After that normal app replacement/relaunch, the production UI showed both monitoring grants, history and the listener still enabled, live Apple Music metadata (Hex / Trunkline, paused), TVTunes stopped, and one authenticated gadget without re-entering its token. Philip confirmed the gadget displayed metadata after the manual reconnect. Recovery logs are retained as `recovery-*.log` beside the earlier evidence.
