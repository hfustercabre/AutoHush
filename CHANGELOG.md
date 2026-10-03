# Changelog

All notable changes to AutoHush are documented here.
This project follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Changed

- **Spanish and Catalan**: AutoHush now speaks English, Spanish and
  Catalan, following your Mac's language: it uses the first of your
  preferred languages that it has, and English otherwise. Every text it
  shows (the menu, Settings, alerts, Diagnostics, VoiceOver labels and the
  permission prompts) comes from String Catalogs in `Resources/`. Each build
  adds new text from the code to the catalog by itself, as Xcode does, and
  the engine now hands Diagnostics plain facts that the app words.
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
