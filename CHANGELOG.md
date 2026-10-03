# Changelog

All notable changes to AutoHush are documented here.
This project follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added

- **Fading** (`VolumeFader`): the music fades out over 2 s before pausing
  and fades back in over 3 s after resuming, by moving the player's own
  volume logarithmically: a steady rate in decibels, down to 50 dB below the
  user's volume, in 0.1 s steps. Each player declares how its volume number
  maps to loudness (`VolumeCurve`); Spotify's is a cube law, measured with the
  new `Scripts/measure-volume-curve.swift` (half volume ≈ −18 dB; 10 or less is
  silent). The volume is set back right after pausing,
  and the user's volume is remembered when a fade starts, so an interrupted
  fade never leaves it lower. An app that stops during the fade-out leaves
  the music playing. Works with any `MusicPlayer` that reports its volume
  (Spotify: `sound volume`, corrected for Spotify reporting one less than it
  was set to). Both durations are in Settings → Advanced (0–5 s each; 0
  turns that fade off).
- **Audio level detection**: other apps are metered through private CoreAudio
  process taps (`ProcessTapLevelMeter`), so only *audible* output counts.
  Spotify now resumes about 2 s after a browser or call app goes silent, instead
  of waiting for it to close its output stream (often 10 s or more, sometimes never).
  Requires the System Audio Recording permission (`NSAudioCaptureUsageDescription`).
- **Level-detection verification and fallback**: taps without permission deliver
  silence, so level detection is trusted only after a non-zero sample. Until then,
  or when Spotify plays but its tap stays silent, open output streams count as
  playing (the 0.2 behaviour). The menu shows the active detection mode and links
  to the Audio Recording settings when needed.
- **Hysteresis** (`SourceActivityTracker`): a source must be audible for 1 s
  before Spotify pauses (notification sounds are ignored) and silent for 2 s
  before it counts as stopped (gaps between tracks or videos are bridged).
- **Spotify state notifications** (`SpotifyPlaybackObserver`): Spotify's
  `PlaybackStateChanged` distributed notification and NSWorkspace quit events
  replace the once-per-second AppleScript polling.
- **New menu:**
  - **Auto-Pause Spotify** toggle and **Turn Off For** (15 minutes, 1 hour,
    until tomorrow 8:00), persisted across launches. The icon dims while it
    is off. Turning it off resumes a Spotify that AutoHush paused.
  - **Playing apps** listed by name and icon. Helper processes are grouped
    under their app (`AudioSourceIdentifier`).
  - **Never Pause Spotify for …** per app, and an **Ignored Apps** submenu to
    undo it. Ignored apps stay visible but never pause Spotify.
  - Only actionable warnings are shown (Automation or Audio Recording access).
  - **Diagnostics…** (hold ⌥ on Settings…) replaces the "Show Active Audio"
    alert.
- **Settings window**, with General, Apps and Advanced tabs in a toolbar,
  built in SwiftUI:
  - **General:** launch at login, with errors shown inline instead of
    degrading the app's health; auto-pause; update checks.
  - **Apps:** every app that has played audio, plus ignored apps, with a
    *Pauses Spotify* switch, *Ignore Another App…*, *Remove from List* and
    *Reset List…* (asks first; forgets every app and un-ignores them all).
  - **Advanced:** start confirmation, stop grace, resume delay and silence
    threshold, applied live without restarting monitoring.
- **About AutoHush** (the standard About panel) and **Check for
  Updates…**, which compares the version with the latest GitHub release.
  There is an optional daily automatic check that only adds an
  *Update Available* menu item, and Homebrew installs get the
  `brew upgrade` command.
- **AntiDot mode** (Settings → General): no visual signs of AutoHush
  working. It never captures audio, so macOS never shows the purple recording
  indicator. Playing apps are detected from **what they tell macOS**, the
  same way for every app, with no list of supported apps and nothing asked:
  an app holding a "don't sleep" power assertion counts as playing
  (`PowerAssertionReader`). Players and browsers hold one while playing and
  drop it on pause, even with their audio open (measured: Chrome, VLC). Apps
  seen announcing playback are remembered, so a paused one stops counting as
  playing. Apps that never announce fall back to their open audio stream
  (Safari and QuickTime Player close theirs 5–10 s after a pause).
  Alternatively, **open audio streams only** can be chosen. It replaces the
  earlier "Measure audio levels" switch; a saved "off" becomes "open audio
  streams only".
- **Less audio capture, so the recording indicator shows less often:** other
  apps are measured only while it can change a decision. That means auto-pause
  is on, Spotify plays on this Mac or is paused by AutoHush, and another
  app has audio open. Taps are released 2 s after they stop being needed.
  Spotify itself is no longer tapped (whether it plays here comes from its
  output stream), so listening to Spotify alone never shows the indicator.
- While Spotify plays alongside an app that started before it, the status now
  says "Spotify is playing" instead of "Spotify idle".
- **System sounds ignored by process:** notification banner sounds, alert
  beeps and system sound effects are played by `systemsoundserverd` for every
  app (measured on macOS 27). That process is now excluded, so these sounds
  never pause Spotify, regardless of timing. The default start confirmation
  drops from 1 s to 0.5 s, since it now only has to filter short sounds that
  apps play themselves.
- **Spotify Connect awareness**: Spotify is only paused when its audio plays on
  this Mac. When it plays on another device, its process has no running
  output, so it is left alone and the menu shows "Spotify is playing on
  another device".

### Fixed

- A resume is no longer abandoned when Spotify doesn't answer in time:
  a timed-out state query was taken as the user changing Spotify, so the
  music stayed paused. It is now retried twice, a second apart. With
  auto-pause turned off, music AutoHush paused also comes back while other
  apps still play.
- Right after Spotify launches, the startup check is retried (3 times, 2 s
  apart) while Spotify is not ready to answer, instead of showing an error
  until Retry. A Spotify that doesn't answer an Apple event in time is now
  reported as "Spotify is not responding".
- The menu no longer rebuilds while it is open, which could collapse an open
  submenu; only the status line updates, and the rest follows once it closes.
- In AntiDot mode, a "keep awake" assertion could be credited to the wrong
  app after macOS reused a process ID; cached process owners are now checked
  against the process's executable.
- The arbiter logs why it did not pause Spotify when Spotify's live state
  was not "playing", instead of skipping silently.
- Players that keep their output stream open while paused (VLC and others)
  could stay "playing" until stopped or quit. That happened whenever level
  detection was not yet verified, for example after the permission was reset
  or before any app had made sound. The System Audio Recording permission is
  now read from TCC (`AudioCapturePermission`):
  - **Granted:** audio levels are used from launch.
  - **Undecided:** the prompt is shown at launch, instead of blocking audio
    monitoring when the first tap is created.
  - **Denied:** no taps are created, and the settings link is shown immediately.
  - The permission is re-checked every 5 s.
  - Sample-based inference remains the fallback.
- Spotify is now controlled with raw Apple events (`NSAppleEventDescriptor.sendEvent`,
  5 s timeout) instead of `NSAppleScript`. NSAppleScript is main-thread only; on
  the controller's background queue it pumped an event loop and could trap
  (EXC_BREAKPOINT in BoardServices). Events target Spotify's process ID, so they
  can never launch Spotify, and the startup check requests Automation consent
  through `AEDeterminePermissionToAutomateTarget`.
- Process monitoring listened to `kAudioProcessPropertyIsRunningOutput`, which
  never posts change notifications; it now listens to `kAudioProcessPropertyIsRunning`.
- Source events reached the arbiter through one unordered `Task` each; they now
  flow through a single ordered stream.
- A replaced arbiter could still fire a pending resume after a re-bootstrap;
  arbiters are now shut down with their pipeline, and overlapping bootstraps
  are discarded.
- `AppDelegateTests` ran the real bootstrap, which scripted the running Spotify
  (and could pause it) from the test process and crashed it with a SIGTRAP.
  Bootstrap is now injectable and stubbed in tests.
- HAL listeners now use block-based APIs, so no unretained `self` pointer is
  handed to CoreAudio.

### Changed

- **Music player interface** (`MusicPlayer`, `PlayerStateObserving`): the
  arbiter, monitor, pipeline and app talk to the music player only through
  it, so more players can be added one type at a time. Spotify is its first
  implementation (`SpotifyPlayer`, formerly `SpotifyController`). States,
  errors and messages are player-neutral (`PlayerState`, `playerNotRunning`,
  "<player> is not running"), and the player's own audio is excluded through
  `SupportedPlayers` instead of a hard-coded Spotify entry.

- **Project structure**: sources and tests are grouped by feature (`App`,
  `MenuBar`, `Settings`, `Audio`, `Playback`, `Spotify`); multi-type files are split.
  `AppDelegate` keeps lifecycle and bootstrap. Menu construction and rendering
  moved to `StatusMenuController` with a testable `AppStatus` value, and
  pipeline wiring moved to `MonitoringPipeline`.
- Menu status updates are delivered through one ordered stream instead of one
  `Task` per update, so they can no longer be applied out of order.
- Unified logging uses the bundle identifier (`com.autohush.AutoHush`)
  as its subsystem.
- `AutoHushError.appleScriptExecution` is now `.spotifyCommandFailed`;
  `AudioProcessInfo.isRunningOutput` is a `Bool`; CoreAudio property reads share
  one helper (`CoreAudioProperty`).
- `Package.swift` drops an unused `RELEASE_BUILD` define and redundant explicit
  framework links; `Info.plist` gains `LSApplicationCategoryType` and
  `NSHumanReadableCopyright`; Settings uses `NSApp.activate()`.
- `PlaybackArbiter`: `syncSpotifyState()` and `reconcileOnStartup(activeSources:)`
  are removed. Spotify state is pushed via `handleSpotifyStateChange(_:)`, and
  sources already playing at launch go through the normal hysteresis path.
- `Scripts/build-app.sh` also resets the System Audio Recording permission on
  each (ad-hoc signed) build, alongside Automation.

### Distribution

- Builds are signed with a self-signed certificate, "AutoHush Self-Signed",
  created once by `Scripts/create-signing-certificate.sh`. macOS then identifies
  the app by its certificate rather than its content hash, so users keep the
  Automation and System Audio Recording permissions across updates.
- Every build uses the **hardened runtime**. `SIGNING_IDENTITY` and
  `SIGNING_KEYCHAIN` override the identity and keychain.
- Privacy permissions are reset only for ad-hoc builds (`KEEP_PERMISSIONS=1`
  skips that too).
- `Scripts/release.sh <version>` prepares a release: version and CHANGELOG,
  tests, signed build, DMG, cask SHA-256 and release notes. It refuses ad-hoc
  releases and publishes nothing.
- `Scripts/build-dmg.sh` builds a compressed DMG with `diskutil` that opens
  as an installer window: the app, an arrow to an Applications shortcut, and
  a note on the one-time "Open Anyway" step. The background is drawn at
  build time (`Scripts/lib/dmg-background.swift`, 1× and 2×) and the layout
  is set through Finder; `PLAIN_DMG=1`, or a failure to script Finder, builds
  a plain DMG instead.
- The Homebrew cask (`Casks/autohush.rb`) is back for installing from this
  repository as a tap. It is kept up to date by the release script and
  removes the download quarantine after installing, since the app is not
  notarized.

### Removed

- The unused launchd LaunchAgent plist. Launch at login is handled solely by
  `SMAppService`, which avoids launching the app twice.
- Documentation for the `install-launchd.sh` / `uninstall-launchd.sh` scripts,
  which never existed.

---

## [0.2.0] — 2026-09-28

### Added

- **Spotify relaunch detection** — the app now watches for `com.spotify.client` via
  `NSWorkspace.didLaunchApplicationNotification` and automatically re-runs bootstrap
  when Spotify is restarted. Previously the monitor would silently stop working until
  the next AutoHush restart.
- **`AppDelegateTests`** — unit tests covering Spotify relaunch detection, non-Spotify
  app launches, and nil bundle identifier handling.
- **`SpotifyControllerTests`** — unit tests for AppleScript error mapping (`-1743`
  automation denial vs. generic execution errors), including missing-key fallback
  behaviour. `AutoHushError` now conforms to `Equatable`.
- **Expanded `AudioMonitorTests`** — 5 new tests covering excluded bundle IDs, full
  start→stop lifecycle, stop→restart re-emission, `debugSnapshot` accuracy, and
  `sweepAndSync` → `syncSpotifyState` wiring. Suite grew from 5 to 10 tests.

### Fixed

- **User-intent protection** — `syncSpotifyState()` now clears `pausedByUs` when
  Spotify is no longer paused, preventing spurious resumes after the user manually
  resumes, stops, or changes tracks while an external source is active.
- **Pre-resume guard** — `resumeIfStillPending()` checks live Spotify state immediately
  before calling `play()`, closing the timing gap that existed during the debounce
  window when the user interacted with Spotify.
- **Swift 6 strict concurrency** — all actor-isolation warnings and region-isolation
  data-race errors resolved. `NSWorkspace` notification closure now extracts the
  `Sendable` bundle ID string before hopping to `@MainActor` via `Task { @MainActor in }`,
  eliminating the `sending` risk.

### Changed

- `PlaybackArbiter` reconciles Spotify state on every periodic sweep via
  `sweepAndSync()`, replacing the earlier one-shot startup reconciliation.
- `SpotifyController.runScript` delegates error-dict parsing to the new pure static
  `mapScriptError(_:)` function.
- `AppDelegate.statusModel` and `handleApplicationDidLaunch(bundleIdentifier:)` relaxed
  from `private` to `internal` to support `@testable import` test hooks without
  breaking encapsulation.

---

## [0.1.0] — 2026-09-01

### Added

- Initial release.
- CoreAudio HAL process-list monitoring via `AudioMonitor`.
- Automatic Spotify pause when a foreign audio source starts, with debounced resume
  when all sources stop.
- AppleScript bridge (`SpotifyController`) for Spotify state, pause, and play.
- Menu bar status item with SF Symbol icons reflecting real-time playback state.
- Launch-at-login support via `SMAppService` (`SettingsWindowController`).
- Ad-hoc code signing and `hdiutil`-based DMG packaging (`Scripts/build-dmg.sh`).
- launchd LaunchAgent install/uninstall scripts.
