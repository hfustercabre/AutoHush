# Changelog

All notable changes to AutoHush are documented here.
This project follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added

- **Notifications about updates**: AutoHush now tells you when a new
  version is available, downloaded, or installed ("AutoHush was updated to
  0.3.8"), and when an automatic install fails. It asks for permission the
  first time it has news.
- **Choose what happens when an update is found** (Settings → General):
  **Notify me**, **Download it and notify me**, or **Install it
  automatically** (the default, as before). A downloaded update is kept for
  at most 7 days, is replaced when a newer version comes out, and is deleted
  once installed or no longer wanted. Automatic downloads wait while Low Data
  Mode is on.
- **The update window shows what's new**, and says which version you're
  running and which one is available or downloaded. Its button tells you
  whether it will **Download and Install** or just **Install and Relaunch**.

### Changed

- Once an update is found, **Check for Updates…** in the menu becomes
  **Install AutoHush 0.3.8…**, which opens the update window. It replaces
  the separate "Update Available" item.
- If you had turned off "Install updates automatically", your choice is now
  **Notify me**.

## [0.3.7] — 2026-10-04

### Changed

- **Buy Me a Coffee** has left the menu: it's now a line in **About
  AutoHush** and at the bottom of **Settings → General**, "Would you like to
  support me?", with the link.

## [0.3.6] — 2026-10-04

### Added

- **Buy Me a Coffee** in the menu opens AutoHush's Buy Me a Coffee page, if
  you'd like to support it.

## [0.3.5] — 2026-10-04

### Changed

- **Updates keep working on future macOS versions**: macOS 27 deprecates
  the `hdiutil` commands AutoHush used to open a downloaded update. It now
  opens it with `diskutil image`, which macOS recommends instead, and falls
  back to `hdiutil` on macOS 15, which doesn't have it.

## [0.3.4] — 2026-10-04

### Changed

- **Installing with Homebrew takes one command**:
  `brew install --cask hfustercabre/tap/autohush`. The cask moved from this
  repository to its own tap,
  [hfustercabre/homebrew-tap](https://github.com/hfustercabre/homebrew-tap),
  which Homebrew adds by itself. Copies installed with the earlier two-line
  command keep updating themselves as before.

## [0.3.3] — 2026-10-04

### Fixed

- **Updating no longer leaves your music paused**: if you chose **Install
  and Relaunch** while AutoHush had your music paused for another app, the
  new version didn't know that pause was its own, so your music stayed
  paused. Now AutoHush notes the pause as it quits to update, and the new
  version takes it over. Your music comes back when the other app stops,
  or within a couple of seconds if nothing is playing any more. Automatic
  updates still wait until AutoHush isn't holding your music paused.

## [0.3.2] — 2026-10-04

### Fixed

- **Restarting after an update**: AutoHush installed the new version but
  then failed to restart. The old version stayed running, unresponsive,
  until it was force-quit, and only then did the new one open. The cause
  was its quit: it had to wait for work that couldn't run until the quit
  itself finished. AutoHush now quits from the main run loop, and the
  one-second safety limit on quitting is a timer that always fires.
  0.3.0 and 0.3.1 still have the problem when they install the next
  version: force-quit AutoHush once afterwards (or log out), and the new
  version opens.

## [0.3.1] — 2026-10-04

### Changed

- **One setting for when the music comes back**: Settings → Advanced no
  longer has **Resume music after**. It only added a fixed wait after
  **Treat an app as stopped after**, which already decides when the music
  resumes, and it was too short for any sound to call the resume off. The
  music now resumes as soon as the last app counts as stopped: 2 s of
  silence by default, 0.2 s sooner than before. A value you had set for
  it is no longer used.
- **Treat an app as stopped after** is now at least 1 second. Below that,
  the music came back in every short pause between tracks or videos;
  shorter values you had set become 1 second.

## [0.3.0] — 2026-10-04

### Added

- **Updates itself**: when the daily check finds a new version, AutoHush
  downloads it from GitHub, installs it and restarts. It waits for a moment
  when it isn't holding your music paused and none of its windows or menus
  are open.
  - **Checks first:** the download must match GitHub's SHA-256 checksum, and
    the app inside must be the announced version, signed with the same
    certificate as the copy you have. That is the check macOS uses to keep
    AutoHush's permissions, so nothing else can be installed this way.
  - **To turn it off:** Settings → General → **Install updates
    automatically**. The menu's **Update Available** then offers **Install
    and Relaunch**.
  - **When it can't:** AutoHush can't update itself from a folder it can't
    write to, and Settings says so.
  - **Earlier copies:** versions up to 0.2.0 still need one update by hand.
- The Homebrew cask now declares that AutoHush updates itself
  (`auto_updates`), so `brew upgrade` leaves it to AutoHush.

## [0.2.0] — 2026-10-04

### Changed

- **Lighter on the battery**: AutoHush now wakes the Mac about once a
  second when idle instead of about 30 times, and uses half the CPU or less
  (measured: 0.18 % idle, 0.26 % with the music playing, 0.35 % while
  measuring another app; Energy Impact 0.2–0.4). Its once-a-second check
  only asks the processes with audio running, instead of every audio
  process on the Mac.
- **Turn Off For** now offers 5, 15 and 30 minutes, 1 hour and 24 hours.
  24 hours replaces Until Tomorrow, which ended at 8:00 the next day: up to
  31 hours when chosen after midnight.
- **Eleven languages**: AutoHush now speaks English, Spanish (Spain and
  Latin America), Catalan, German, French (France and Canada), Italian,
  Portuguese (Brazil and Portugal), Japanese, Korean and Chinese (Simplified
  and Traditional), following your Mac's language: it uses the first of your
  preferred languages that it has, and English otherwise. Every text it
  shows (the menu, Settings, alerts, Diagnostics, VoiceOver labels and the
  permission prompts) comes from String Catalogs in
  `Resources/Localization/`. Each build adds new text from the code to the
  catalog by itself, as Xcode does, and the engine now hands Diagnostics
  plain facts that the app words.
- **A redesigned installer**: the disk image window now uses AutoHush's
  colours and mark, the mounted disk shows the app's icon, and the window
  leaves room for Finder's tab and path bars, so the first-launch note is
  never cut off. The volume's hidden files stay out of sight even when Finder
  shows hidden files.
- **An app icon**: the menu bar's sound bars in purple, on a background that
  follows your Mac's appearance (light, dark, clear or tinted on macOS 26 and
  later). Made in Icon Composer and compiled into the app; macOS 15 gets a
  flat version.
- **A menu bar icon of its own**: sound bars cut out of a rounded square,
  replacing eight unrelated system symbols. Every state uses the same tile:
  the bars play, become a dot and a pause sign when AutoHush pauses your
  music, drop to three dots when nothing plays, point away when the music
  plays on another device, show hollow while starting, and make room for "!"
  when something needs your attention. Drawn in code, so it stays sharp at any
  size.

- **Modular project structure**, following Apple's sample apps (Food Truck,
  Backyard Birds) and popular open-source Mac apps (AeroSpace, Ice, Stats):
  - `AutoHushKit`: the engine (audio detection, playback decisions, fades,
    the `MusicPlayer` interface, permissions, configuration, storage). It has
    no user interface and knows no player by name; the compiler keeps it
    from depending on the app or a player.
  - `AutoHushApp`: the app, grouped by feature (MenuBar, Settings, Updates,
    Diagnostics, About), with `Main/` wiring them to the engine. Update
    checks, the Diagnostics text and the About panel moved out of
    `AppDelegate` (`UpdateController`, `DiagnosticsReport`, `AboutPanel`).
  - `AutoHush`: a one-file executable that only starts the app.
  - `SpotifySupport`: everything Spotify-specific; each new player gets its
    own `<App>Support` module, listed in `AutoHushPlayers`. Player modules
    and their tests live in `PlayersSupport/` folders.
  - `AutoHushKit/PrivateAPI`: the only place calling undocumented macOS
    functions (TCC, `responsibility_get_pid_responsible_for_pid`).
  - `AutoHushKit/Permissions`: what each permission is for and where it is
    granted; the menu's warning is now the missing `Permission`.
  - Types shared between modules use `package` access. Tests are split per
    module, with shared fakes in `AutoHushTestSupport`. `AutoHushError` is
    now `MusicPlayerError`.
- **`measure-volume-curve` is a package tool** (`swift run
  measure-volume-curve`, in `Tools/`) that uses the engine's tap meter
  (which now also reports the average level) and the supported players,
  replacing `Scripts/measure-volume-curve.swift`.
- The engine no longer uses AppKit: opening System Settings moved to the app.
- **Simpler code**, with no change in behaviour:
  - `AudioMonitor` hands AntiDot mode's judging to `PlaybackSignals` and
    what Diagnostics shows to `ActiveAudioReport`.
  - Menu and Settings text for the engine's states and choices lives in the
    app, with one row per state for its icon, label and status line.
  - Long functions are split into named steps (the menu, the measuring
    tool), repeated code is shared (process caches, Spotify commands,
    the auto-pause display), and every type has a doc comment.
  - Repetitive tests are parameterized.
  - Unused code is gone: the menu's "monitoring" look and "until Thursday"
    snooze text (never shown, yet translated into every language),
    options nothing used (opening Settings on a given tab, a custom status
    bar, a second check that audio output is running), and test helpers
    copied between files (fixed dates, the fake GitHub answer).
- Less duplicated code: the timing defaults are defined once (in
  `TimingSettings`), and each supported player is listed once.

### Fixed

- An app that stops while the music fades out now brings the music back up
  at once, without pausing it. Before, the pause always finished first (the
  fade held up every later event), then the music resumed. This showed with
  a fade-out at least as long as "Treat an app as stopped after".
- Turning auto-pause off no longer holds up player updates while the music
  fades back in.
- Music paused just as the other app stopped (after the fade-out, while the
  volume was being set back) stayed paused, and faded down. It now resumes.
- `measure-volume-curve` no longer crashes when the music goes silent during
  a measurement, and gives the player its volume and play state back when it
  stops early.
- Turning auto-pause back on (or a snooze ending) no longer pauses the music
  for a moment because of an app that only has its sound output open, such as
  a muted call or a paused video. While auto-pause is off nothing is
  measured, so such apps count as playing; AutoHush now measures them again
  before pausing, which takes about 2.5 s.
- A snooze that ends the next day no longer reads "until tomorrow 22:00"
  after midnight: the menu and Settings now say "until 22:00".
- Clicking Check Now twice, or checking while the automatic check runs, no
  longer asks GitHub twice and shows the answer twice.

### Security

- The update check only ever opens one of AutoHush's release pages on
  github.com: an answer pointing anywhere else (another site, a file, a
  network share, another app) is refused.

## [0.1.0] — 2026-10-03

The first release of AutoHush: a macOS menu bar app that pauses your music
while other apps play audio, and brings it back afterwards. It works with
Spotify and needs macOS 15 or later.

### Pausing and resuming

- **Automatic:** the music pauses when another app has been making sound for
  0.5 s, and resumes 0.2 s after every other app has been quiet for 2 s, so
  gaps between tracks or videos don't bounce it.
- **Fading:** the music fades out over 1 s before pausing and back in over 2 s
  after resuming, at a steady rate in decibels (a logarithmic fade) down to
  50 dB below your volume. Your volume is always left as it was, even when a
  fade is interrupted, the other app stops halfway, or AutoHush quits.
- **Respects you:** if you pause, play or quit the music player yourself while
  another app is playing, AutoHush takes that as your decision and won't
  resume it later. It only ever resumes music it paused.
- **Ignores the noise:** notification banner sounds, alert beeps and system
  sound effects (played by `systemsoundserverd` for every app) never pause the
  music, and neither do short sounds apps play themselves.
- **Knows where you're listening:** music playing on another device through
  Spotify Connect is left alone.
- **Reliable:** the player is asked for its live state right before every
  pause and resume; a resume is retried when the player doesn't answer in
  time, and the startup check is retried while a just-launched player isn't
  ready yet. AutoHush restarts monitoring by itself when the player opens.

### Detecting other apps' sound

- **Audio levels:** each app with its sound on is measured through a private
  CoreAudio process tap (peak level only, in memory, nothing recorded), so a
  paused video that keeps its sound switched on doesn't keep the music paused.
  Apps are grouped by the app that owns them (Chrome's helpers count as
  Google Chrome).
- **Purple recording dot kept to a minimum:** other apps are measured only
  while it can change a decision (auto-pause on, the music playing on this Mac
  or paused by AutoHush), and the music player itself is never measured.
- **System Audio Recording permission:** read and requested through TCC; when
  it's denied, AutoHush falls back to "any app with its sound on is playing"
  and the menu links to the right place in System Settings.
- **AntiDot mode** (Settings → General): never measures sound, so macOS never
  shows the purple dot. Apps are judged by what they tell macOS: an app that
  keeps the Mac awake for playback counts as playing, one seen doing that
  before but not now counts as paused, and the rest count while their sound
  is on. Alternatively, any app with its sound on can count as playing.

### Menu bar

- A status line ("Music paused — Google Chrome is playing"), the playing apps
  with their icons and a **Never Pause Music for …** option each, **Auto-Pause
  Music**, **Turn Off For** (15 minutes, 1 hour, until 8:00 tomorrow) and
  **Ignored Apps**.
- One actionable warning when a permission is missing, **Retry** after a
  failed start, and **Diagnostics…** (hold ⌥) listing every app with its sound
  on and how AutoHush judges it.
- **About AutoHush**, **Check for Updates…** and **Update Available** when a
  newer release exists.

### Settings

- **General:** launch at login, Auto-Pause Music, AntiDot mode and its
  detection choice, and update checks.
- **Apps:** every app that has played sound, each with a **Pauses Music**
  switch; **Ignore Another App…**, **Remove from List** and **Reset List…**.
- **Advanced:** how long an app must play before the music pauses, how long it
  must be quiet before it counts as stopped, the extra wait before resuming,
  the fade-out and fade-in times, and the silence threshold, with **Restore
  Defaults**. Changes apply immediately.

### Updates

- A daily check (optional) and a manual one against the latest GitHub release;
  only the release's tag and page are read. Homebrew installs are told to run
  `brew upgrade --cask autohush`.

### Distribution

- Signed with the self-signed "AutoHush Self-Signed" certificate and the
  hardened runtime, so permissions survive updates; not notarized by Apple.
- A DMG that opens as a drag-to-Applications window with a note on the
  one-time "Open Anyway" step, and a Homebrew cask (`autohush`) installed from
  this repository's tap, which removes the download quarantine.
- Scripts to create the signing certificate, build the app and DMG, prepare a
  release, and measure a music player's volume curve.

### For developers

- Music players sit behind one interface (`MusicPlayer`), so more can be
  added one at a time under `MusicPlayers/<App>/`; Spotify is the first.
- Swift 6 with strict concurrency; the test suite (Swift Testing) uses mock
  CoreAudio, level meter, power assertion and player implementations, so it
  never taps real audio or scripts a real player.
