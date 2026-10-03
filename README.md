# AutoHush

**Your music steps aside when something else needs your ears.**

AutoHush is a small menu bar app for macOS. When another app starts making sound (a YouTube video, a call, a game), it pauses your music. When that sound stops, it brings your music back. You don't have to touch anything.

- 🎵 **Automatic:** pauses your music when another app plays, resumes it about 2 seconds after that app goes quiet.
- 🎚️ **Gentle:** the music fades out over 1 second before pausing and fades back in over 2 seconds when it resumes, and your volume is always left as it was.
- 🙋 **Respects you:** if you pause, play or quit your music player yourself, AutoHush takes that as your decision and won't override it.
- 🔕 **Ignores the noise:** notification sounds, alert beeps and short chat tones don't interrupt your music.
- 📱 **Knows where you're listening:** if Spotify plays on your phone, speaker or TV (Spotify Connect), it's left alone.
- 🚫 **Your rules:** choose apps that should never pause your music, or turn auto-pause off for a while.
- 🟣 **AntiDot mode:** an option that never shows macOS's purple recording dot.

**Works with Spotify** today. Support for more players, such as Apple Music, YouTube Music and Tidal, is planned.


## Contents

- [Install](#install)
- [First launch](#first-launch)
- [Using AutoHush](#using-autohush)
- [The purple dot and AntiDot mode](#the-purple-dot-and-antidot-mode)
- [Tips and troubleshooting](#tips-and-troubleshooting)
- [Privacy](#privacy)
- [Updates](#updates)
- [Uninstall](#uninstall)
- [For developers](#for-developers)

## Install

You need **macOS 15 or later** and the **Spotify desktop app**.

AutoHush is free and isn't sold through Apple. It's signed, but not *notarized* by Apple, because notarization needs a paid developer account. All that means for you is one extra confirmation the first time you open it. Homebrew handles that step for you.

### With Homebrew (easiest)

```bash
brew tap hfustercabre/autohush https://github.com/hfustercabre/AutoHush
brew install --cask autohush
```

### By hand

1. Download `AutoHush-<version>.dmg` from the [releases page](https://github.com/hfustercabre/AutoHush/releases).
2. Open it: a window shows AutoHush, an arrow and your Applications folder. Drag **AutoHush** onto **Applications**.
3. Open AutoHush. macOS will refuse the first time, which is expected.
4. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the AutoHush message. You only do this once per version.

Prefer the Terminal? This does the same as step 4:

```bash
xattr -dr com.apple.quarantine /Applications/AutoHush.app
```

### From the source code

```bash
git clone https://github.com/hfustercabre/AutoHush.git
cd AutoHush
bash Scripts/build-app.sh release
cp -R AutoHush.app /Applications/
open /Applications/AutoHush.app
```

## First launch

AutoHush appears as an icon in the menu bar; it has no Dock icon or window. macOS will ask for two permissions:

| Permission | What it's for | Needed? |
|---|---|---|
| **Control Spotify** (Automation) | Pausing and resuming Spotify | Yes |
| **Record system audio** (Screen & System Audio Recording) | Telling apart an app that's *playing* from one that just has its sound switched on but is silent | Recommended; not used in AntiDot mode |

The audio permission sounds scarier than it is: AutoHush only checks *how loud* other apps are, in memory, and never records or saves anything. See [Privacy](#privacy). Without it, AutoHush still works, but a paused video may keep Spotify paused until you close it.

If you said no by mistake, the menu shows a button that takes you to the right place in System Settings.

**Start it automatically:** open the menu, choose **Settings…** and turn on **Launch at login**.

## Using AutoHush

Click the menu bar icon to see what's going on:

```text
Music paused — Google Chrome is playing
───────────────
[icon] Google Chrome                ▸ Never Pause Music for Google Chrome
[icon] VLC   Ignored — music keeps playing
───────────────
✓ Auto-Pause Music
  Turn Off For                      ▸ 15 Minutes · 1 Hour · Until Tomorrow
  Ignored Apps                      ▸ click an app to stop ignoring it
───────────────
⚠ Allow Audio Recording Access…        (only when something needs fixing)
  Update Available: 0.3.0…             (only when a newer version exists)
  Settings…                     ⌘,     (hold ⌥ for Diagnostics…)
───────────────
  About AutoHush
  Check for Updates…
  Quit AutoHush             ⌘Q
```

- **The first line** tells you what's happening, for example "Music is playing", "Music paused — Google Chrome is playing" or "Music is playing on another device".
- **Playing apps** are listed with their icons. Open an app's submenu and choose **Never Pause Music for …** if that app shouldn't interrupt your music, for example a game whose soundtrack you don't mind.
- **Auto-Pause Music** switches everything on or off. Turning it off brings back music that AutoHush paused.
- **Turn Off For** pauses AutoHush itself for 15 minutes, an hour, or until 8:00 tomorrow.
- **Ignored Apps** lists every app you've told to leave your music alone. Click one to undo.
- The **icon** shows your music's state, and is dimmed while auto-pause is off.

### Settings

| Tab | What you'll find |
|---|---|
| **General** | Launch at login · **Auto-Pause Music** · **AntiDot mode** (see [below](#the-purple-dot-and-antidot-mode)) · update checks |
| **Apps** | Every app that has played sound, each with a **Pauses Music** switch. **Ignore Another App…** adds an app before it ever plays. Right-click an app to remove it, or use **Reset List…** to start over |
| **Advanced** | Fine-tuning, with sensible defaults: how long an app must play before your music pauses (0.5 s), how long it must be quiet before it counts as stopped (2 s), an extra wait before resuming (0.2 s), how long the music fades out before pausing (1 s) and back in when it resumes (2 s; 0 turns either off), and what counts as silence (-60 dB). **Restore Defaults** undoes your changes |

## The purple dot and AntiDot mode

To hear whether another app is *really* playing, AutoHush has to listen to its sound level. Whenever an app does that, macOS shows a **purple dot** in the menu bar. It's a privacy feature that no app can hide, and that's a good thing.

AutoHush keeps the dot to a minimum: it only listens while the answer matters, that is while Spotify is playing on this Mac (or was paused by AutoHush) and another app has its sound on. Spotify itself is never listened to. So:

- Spotify playing on its own, paused, or on another device: **no dot**.
- Another app playing over your music: the dot shows while that app has its sound on, plus 2 seconds.

**If the dot bothers you, turn on AntiDot mode** (Settings → General). AutoHush then never listens to any sound, so the dot never appears. Instead, it goes by what apps tell macOS: most players and browsers say "I'm playing, don't go to sleep" while they play, and stop saying it when you pause. AutoHush needs no extra permission for this, and treats every app the same way.

The catch is that it's a little less precise:

| | Normal mode | AntiDot mode |
|---|---|---|
| Purple dot | Sometimes, while needed | Never |
| Music comes back after you pause Chrome | ~2 s | ~5 s |
| …after you pause Safari or QuickTime | ~2 s | ~7–12 s (they don't say when they're playing, so AutoHush waits for them to switch their sound off) |
| An app that never says it's playing and keeps its sound on while paused | Music comes back | Music stays paused until you close that app |
| An app playing muted | Music comes back | May keep your music paused |

AntiDot mode offers two ways to detect playing apps:

- **What apps tell macOS** (recommended): as described above.
- **Open audio streams only:** any app with its sound switched on counts as playing, even when paused. Simpler, but stricter.

## Tips and troubleshooting

- **Spotify doesn't come back after VLC.** VLC has its own setting that pauses Spotify. Because AutoHush didn't pause it, it won't resume it. Turn it off in **VLC → Settings → Interface → Control external music players → Do nothing**, and let AutoHush do the job.
- **I paused Spotify myself and it stayed paused.** That's on purpose: AutoHush only resumes music that *it* paused.
- **Music keeps playing during a video.** Check that the app isn't ignored (menu → Ignored Apps), and that auto-pause isn't turned off.
- **Music stays paused after a video ends.** Some apps keep their sound switched on after playback. Grant the audio permission, or in AntiDot mode close the app or tab.
- **Something looks off?** Hold **⌥ (Option)** while the menu is open and choose **Diagnostics…**. It lists every app with sound, what AutoHush thinks it's doing, and the current settings.
- **"Spotify is not running"** or a permission warning: fix it and choose **Retry**. AutoHush also restarts by itself when Spotify is opened.

## Privacy

- AutoHush **never records, saves or sends audio**, and never uses the microphone.
- With the audio permission, it reads other apps' sound only to work out how loud it is, in memory, and throws the rest away.
- In AntiDot mode it doesn't look at any sound at all.
- The only thing it sends over the internet is an optional, once-a-day check for a new version on GitHub (see below).
- It controls Spotify through the standard macOS automation mechanism, and no other app.

## Updates

AutoHush checks GitHub for a new version once a day (you can turn this off in Settings → General). If there's one, **Update Available** appears in the menu; there are no pop-ups. You can also check yourself with **Check for Updates…**.

- Installed with Homebrew: `brew upgrade --cask autohush`
- Installed by hand: download the new version from the releases page and replace the old one.

## Uninstall

1. In Settings, turn off **Launch at login**, then quit AutoHush.
2. Delete `/Applications/AutoHush.app`, or run `brew uninstall --cask autohush`.
3. Optional: also forget the permissions you granted:

```bash
tccutil reset All com.autohush.AutoHush
```

---

## For developers

### How it works

1. **Which apps have sound on.** AutoHush watches CoreAudio's list of audio processes, with change listeners plus a once-per-second resync. Helper processes are grouped under their app (Chrome's helpers count as "Google Chrome") using the process macOS holds responsible for them (`responsibility_get_pid_responsible_for_pid`, a private function resolved at runtime, with a fallback to the enclosing `.app`).
2. **Whether they're actually audible.**
   - *Normal mode:* each app is metered through a private, unmuted CoreAudio **process tap** that computes only its peak level.
   - *AntiDot mode ("What apps tell macOS"):* no taps. An app holding its own system-sleep **power assertion** (`IOPMCopyAssertionsByProcess`) counts as playing. An app seen doing that before but not now counts as paused, even with its output open; these apps are remembered across launches. Apps that never hold one count as playing while their output is open. Assertions held on an app's behalf (by `coreaudiod` or `runningboardd`) and display-only assertions are ignored.
3. **Filtering.** System sounds are played by `systemsoundserverd`, which is excluded outright. An app must be audible for 0.5 s to count as playing (this filters out chat tones) and silent for 2 s to count as stopped (this bridges gaps between tracks).
4. **Deciding.** `PlaybackArbiter` pauses Spotify when the first app starts, and resumes it 0.2 s after the last one stops, but only if it paused Spotify itself and Spotify is still paused.
5. **Fading.** `VolumeFader` fades the player's own volume logarithmically, in 0.1 s steps: the level drops at a steady rate in decibels to 50 dB below the user's volume over 1 s, then the player pauses and its volume is set back while paused; resuming plays from 50 dB below and rises back over 2 s. Each player's `VolumeCurve` turns decibels into its volume number (Spotify's is a cube law, measured with `Scripts/measure-volume-curve.swift`). The user's volume is remembered when a fade starts, so an interrupted fade never leaves it lower. If the other app stops during the fade-out, the music comes back up without pausing. It works with any player that reports its volume; others pause and play directly.
6. **Spotify.** Its state arrives as a push notification (`com.spotify.client.PlaybackStateChanged`) and is confirmed with an Apple event right before each pause or resume. Spotify plays "on this Mac" only when its own process has output running; otherwise it's on a Spotify Connect device and is left alone.

**The purple dot:** taps exist only while `PlaybackArbiter` says levels can change a decision (auto-pause on, and Spotify playing here or paused by us), with a 2 s release delay. Spotify itself is never tapped, except to prove the permission works when TCC can't be read.

**The audio permission:** macOS has no public API for it, and taps without it simply deliver silence. AutoHush reads it through the private `TCCAccessPreflight` / `TCCAccessRequest` (resolved at runtime), re-checks it every 5 s, and falls back to "any open output counts" when it's denied. If a future macOS removes those functions, it infers the permission from tapped samples instead.

### Architecture

```text
AppDelegate ── lifecycle, bootstrap (launch, Retry, Spotify relaunch), menu and Settings actions
  ├── StatusMenuController ── renders AppStatus into the menu bar item and menu
  ├── SettingsWindowController ── SwiftUI tabs backed by SettingsModel
  └── MonitoringPipeline ── one per bootstrap, started and torn down as a unit
        PlayerStateObserving ── the player's state (Spotify: distributed notification, quit) ┐
        AudioMonitor                                                                │
          ├── HALAudioProcessSnapshotProvider: process list + is-running listeners  │
          ├── ProcessTapLevelMeter: per-app peak level (normal mode)                 │
          ├── IOKitPowerAssertionReader: who says "I'm playing" (AntiDot mode)       │
          ├── SourceActivityTracker: start confirmation + stop grace                 │
          └── ordered source events + "Spotify plays on this Mac" ──┐                │
                                                                    ▼                ▼
                                                              PlaybackArbiter
                                                                ├── pauses Spotify on the first app
                                                                ├── resumes after all apps stop
                                                                └── MusicPlayer (Spotify: SpotifyPlayer, Apple events)
```

```text
Sources/AutoHush/
  App/        main, AppDelegate (+Updates), MonitoringPipeline, Preferences, AppConfiguration,
              TimingSettings, UpdateChecker, AppHealthState, AutoHushError,
              SystemSettingsPane, Logging
  MenuBar/    AppStatus (what the menu shows), StatusMenuController, StatusPresentation
  Settings/   SettingsWindowController, SettingsModel, SettingsViews, LaunchAtLoginController
  Audio/      AudioMonitor, AudioProcessSnapshotProvider, ProcessTapLevelMeter,
              PowerAssertionReader, SourceActivityTracker, AudioSourceIdentifier,
              AudioCapturePermission, DetectionMethod (your choice),
              DetectionMode (what's in effect), CoreAudioProperty
  Playback/   PlaybackArbiter, PlaybackState, AutoPause
  MusicPlayers/  MusicPlayer (the interface every player implements), PlayerState
    Spotify/     SpotifyPlayer (+AppleEvents), SpotifyPlaybackObserver
Tests/AutoHushTests/   same folders, plus Support/ for shared mocks
Resources/  Info.plist and entitlements, assembled into the .app by Scripts/build-app.sh
```

**Adding a music player:** everything outside `MusicPlayers/` talks to the player through the `MusicPlayer` protocol: its bundle ID and name, a permission check, its live state, `pause()` / `play()`, its volume (for fades; `nil` if it has none) and how that volume maps to loudness (`VolumeCurve`, measured with `Scripts/measure-volume-curve.swift`; linear if not given), and a `PlayerStateObserving` that reports state changes. A new player gets its own subfolder, `MusicPlayers/<App>/` in both `Sources` and `Tests`, with a type implementing the protocol, plus its bundle ID in `SupportedPlayers` so its own audio never counts as another app playing.

Defaults that aren't in Settings, such as tick rates, the gap tolerance and the excluded system processes, live in [`AppConfiguration.swift`](Sources/AutoHush/App/AppConfiguration.swift). Any non-empty bundle ID that isn't excluded counts as a media app.

### Build and test

```bash
swift build      # build
swift test       # run the tests
bash Scripts/build-app.sh release   # build and sign AutoHush.app
```

The tests use mock CoreAudio, level meter, power assertion and Spotify implementations, so they never create real taps, script Spotify or trigger permission prompts.

### Signing and releases

macOS remembers permissions per signing certificate. An unsigned ("ad hoc") build looks like a new app every time, and users would have to grant everything again. So AutoHush is signed with a stable self-signed certificate, **"AutoHush Self-Signed"**, and the hardened runtime.

**One-time setup:**

```bash
bash Scripts/create-signing-certificate.sh
```

This creates the certificate (valid 10 years) in your login keychain. The first build asks to let `codesign` use the key: choose **Always Allow**. Then **back it up**: in Keychain Access, open **login → My Certificates**, right-click "AutoHush Self-Signed", choose **Export…** and save a password-protected `.p12`. If you lose it, every user has to grant the permissions again after the next update.

| Script | What it does |
|---|---|
| `Scripts/create-signing-certificate.sh` | Creates the signing certificate (once) |
| `Scripts/build-app.sh [release\|debug]` | Builds and signs `AutoHush.app` (`VERSION` / `BUILD_NUMBER` override the bundle version) |
| `Scripts/build-dmg.sh [version]` | Packages `dist/AutoHush-<version>.dmg`, which opens as a drag-to-Applications window with a first-launch note. Laying out the window scripts Finder (asks once for permission); `PLAIN_DMG=1` skips it |
| `Scripts/measure-volume-curve.swift [bundle-id] [volume …]` | Measures how a player's volume number maps to loudness (dB), for its `VolumeCurve`. Plays the music for about 50 s at changing volumes, then restores it; needs permission to record system audio |
| `Scripts/release.sh <version>` | Prepares a release: version and changelog, tests, signed build, DMG, cask checksum and release notes. It refuses unsigned builds and never commits, tags or publishes |

The signing identity is `SIGNING_IDENTITY` if set (`-` means ad hoc), otherwise "AutoHush Self-Signed" if it exists, otherwise ad hoc. `SIGNING_KEYCHAIN` points to another keychain (for example on CI). Ad-hoc builds reset AutoHush's permissions so macOS asks again; `KEEP_PERMISSIONS=1` skips that.

**Publishing a release:**

```bash
bash Scripts/release.sh 0.3.0
```

Then follow the printed steps: commit `Resources/Info.plist`, `CHANGELOG.md` and `Casks/autohush.rb`, tag `v0.3.0` and push, then create the GitHub release with the DMG and the generated notes. The cask in this repository then points at it, so `brew upgrade` picks it up.

The Mac App Store and Homebrew's official cask repository aren't options: both require Apple notarization, and the App Store would also reject the private functions AutoHush relies on.

## License

[MIT](LICENSE)
