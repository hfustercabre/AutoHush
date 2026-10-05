<h1 align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/images/icon-dark.png">
    <img src=".github/images/icon-light.png" alt="" width="64" height="64">
  </picture>
  <br>AutoHush
</h1>
<p align="center"><strong>Your music steps aside when something else needs your ears.</strong></p>
<p align="center">
  <a href="https://github.com/hfustercabre/AutoHush/releases/latest"><img src="https://img.shields.io/github/v/release/hfustercabre/AutoHush?color=BD5FFF" alt="Latest release"></a>
  <a href="https://github.com/hfustercabre/AutoHush/releases"><img src="https://img.shields.io/github/downloads/hfustercabre/AutoHush/total?color=BD5FFF" alt="Downloads"></a>
  <a href="#install"><img src="https://img.shields.io/badge/macOS-15%2B-BD5FFF" alt="macOS 15 or later"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/hfustercabre/AutoHush?color=BD5FFF" alt="MIT license"></a>
</p>
<p align="center">
  <a href="https://buymeacoffee.com/hfustercabre"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-violet.png" alt="Buy me a coffee" height="40"></a>
</p>

## Meet AutoHush

AutoHush is a small menu bar app for macOS. When another app starts making sound (a YouTube video, a call, a game), it pauses your music. When that sound stops, it brings your music back. You don't have to touch anything.

- 🎵 **Automatic:** pauses your music when another app plays, resumes it about 2 seconds after that app goes quiet.
- 🎚️ **Gentle:** the music fades out over 1 second before pausing and fades back in over 2 seconds when it resumes, and your volume is always left as it was.
- 🙋 **Respects you:** if you pause, play or quit your music player yourself, AutoHush takes that as your decision and won't override it.
- 🔕 **Ignores the noise:** notification sounds, alert beeps and short chat tones don't interrupt your music.
- 📱 **Knows where you're listening:** if Spotify plays on your phone, speaker or TV (Spotify Connect), it's left alone.
- 🚫 **Your rules:** choose apps that should never pause your music, or turn auto-pause off for a while.
- 🟣 **AntiDot mode:** an option that never shows macOS's purple recording dot.
- 🔒 **Minds its own business:** no accounts, no analytics, no tracking. It never records or saves sound, and it only goes online to check GitHub for updates (more under [Privacy](#privacy)).
- 🪶 **Featherweight:** built to sip, not gulp: about 0.05 % CPU and 15 MB of memory while it waits or your music plays, and well under 1 % while it's working, so your battery won't notice it.

**Works with Spotify, Apple Music and TIDAL**: choose yours in the menu or in Settings. Support for more players, such as YouTube Music, is planned.

## Thanks to Background Music

AutoHush was inspired by [Background Music](https://github.com/kyleneideck/BackgroundMusic), the free, open-source audio utility by [Kyle Neideck](https://github.com/kyleneideck) and its contributors. Among many other things, it pauses your music while other apps play, and it did so long before AutoHush existed. My sincere thanks to Kyle for building it and sharing it with everyone: it showed me this could be done, and it's still well worth a look if you also want to set each app's volume.

So why write another one? To get your Mac's sound, Background Music routes it through a virtual audio device and reads it back from there, and macOS counts that as using a microphone. So while it runs, there's a yellow dot in the top-right corner of the screen and a yellow microphone icon in the menu bar, permanently. Nothing is being recorded, and macOS is right to point it out. Still, a yellow dot that never goes away tickles my 'tism in ways I couldn't ignore, so I built AutoHush with a different approach.

AutoHush leaves your sound where it is and only checks which apps are playing. It never uses the microphone, so the yellow dot never shows up. The only dot it ever shows is macOS's purple one, and only while another app plays over your music, which to my eyes is easier to ignore. If it still bothers you, [AntiDot mode](#the-purple-dot-and-antidot-mode) gets rid of it entirely, at the cost of slightly less precise detection.

Yes, this whole app exists because of a yellow dot.


## Contents

- [Install](#install)
- [First launch](#first-launch)
- [Using AutoHush](#using-autohush)
- [The purple dot and AntiDot mode](#the-purple-dot-and-antidot-mode)
- [Tips and troubleshooting](#tips-and-troubleshooting)
- [Privacy](#privacy)
- [Updates](#updates)
- [Uninstall](#uninstall)
- [Support AutoHush](#support-autohush)
- [For developers](#for-developers)

## Install

You need **macOS 15 or later** and **Spotify** (the desktop app), **Apple Music** (the Music app that comes with macOS) or **TIDAL** (the desktop app).

AutoHush is free and isn't sold through Apple. It's signed, but not *notarized* by Apple, because notarization needs a paid developer account. All that means for you is one extra confirmation the first time you open it. Homebrew handles that step for you.

### With Homebrew (easiest)

```bash
brew install --cask hfustercabre/tap/autohush
```

The cask lives in its own tap, [hfustercabre/homebrew-tap](https://github.com/hfustercabre/homebrew-tap); this command adds it for you.

### By hand

1. Download `AutoHush-<version>.dmg` from the [releases page](https://github.com/hfustercabre/AutoHush/releases).
2. Open it: a window shows AutoHush, an arrow and your Applications folder. Drag **AutoHush** onto **Applications**.
3. Open AutoHush. macOS will refuse the first time, which is expected.
4. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the AutoHush message. You only do this once: AutoHush installs later versions itself.

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

AutoHush appears as an icon in the menu bar; it has no Dock icon. The first time it opens, a small window asks which music player it should control. If only one is installed, it's already picked: just click **Continue**. AutoHush finds the players installed in /Applications, your own Applications folder (~/Applications) or /System/Applications; a copy elsewhere, such as on the disk image it came from, doesn't count. You can change it any time in the menu (**Music player**, on the card at the top) or in Settings. If you're updating from an earlier version, AutoHush keeps controlling Spotify and doesn't ask.

macOS will then ask for these permissions:

| Permission | What it's for | Needed? |
|---|---|---|
| **Control your music player** (Automation) | Pausing and resuming Spotify or Apple Music. macOS asks for each player the first time you choose it | Yes, for Spotify and Apple Music |
| **Accessibility** | Pausing and resuming TIDAL, which can't be scripted: AutoHush presses Play/Pause in its Playback menu, and nothing else | Only with TIDAL |
| **Record system audio** (Screen & System Audio Recording) | Telling apart an app that's *playing* from one that just has its sound switched on but is silent | Recommended; not used in AntiDot mode |
| **Notifications** | Telling you about updates (see [Updates](#updates)) | Optional |

The audio permission sounds scarier than it is: AutoHush only checks *how loud* other apps are, in memory, and never records or saves anything. See [Privacy](#privacy). Without it, AutoHush still works, but a paused video may keep your music paused until you close it.

If you said no by mistake, the menu shows a button that takes you to the right place in System Settings. Once you allow it there, AutoHush starts by itself within a few seconds.

**Start it automatically:** open the menu, choose **Settings…** and turn on **Launch at login**.

## Using AutoHush

Click the menu bar icon to see what's going on:

```text
╭──────────────────────────────────────────────────────╮
│ [icon] Spotify                                  (●)  │
│        Paused — Google Chrome is playing  Auto-Pause │
│ ──────────────────────────────────────────────────── │
│ Music player                     [icon] Spotify ⌄    │
╰──────────────────────────────────────────────────────╯
⚠ Allow Audio Recording Access…            (only when something needs fixing)
  Turn off for
  [5 min] [15 min] [30 min] [1 hr] [24 hr]
───────────────
  Playing now
  [icon] Google Chrome   Pauses your music               (●)
  [icon] VLC             Ignored — music keeps playing   ( )
───────────────
  Ignored Apps                         ▸ click an app to stop ignoring it
───────────────
  Install AutoHush 0.3.8…                  (once a newer version is found)
  [Settings]  [Updates]  [About]  [Quit]
```

- **The card** at the top shows your music player and what's happening, for example "Playing", "Paused — Google Chrome is playing" or "Playing on another device". Something that needs your attention is shown in orange, with a row under the card to fix it, or a **Retry** button when the player didn't answer.
- **Auto-Pause**, the switch on the card, turns everything on or off. Turning it off brings back music that AutoHush paused.
- **Music player** chooses the player AutoHush controls: click it to unfold the players under the card. A player that isn't on your Mac is shown dimmed. The one you don't choose counts like any other app: if it plays, it pauses your music, unless you ignore it.
- **Turn off for** pauses AutoHush itself for 5, 15 or 30 minutes, an hour, or 24 hours, in one click.
- **Playing now** lists the apps playing sound, each with a switch: turn it off if that app shouldn't interrupt your music, for example a game whose soundtrack you don't mind.
- **Ignored Apps** lists every app you've told to leave your music alone. Click one to undo.
- **The buttons at the bottom** open Settings, check for updates, show About AutoHush, and quit. AutoHush has no keyboard shortcuts.
- The **icon**, sound bars cut out of a rounded square, shows what's happening: bars while your music plays, a dot and a pause sign when AutoHush paused it for another app, three dots when nothing plays, an arrow when it plays on another device, hollow bars while starting, and "!" when something needs your attention. It's dimmed while auto-pause is off.

### Settings

| Tab | What you'll find |
|---|---|
| **General** | Launch at login · **Music:** Auto-Pause Music and your music player · **Privacy:** AntiDot mode (see [below](#the-purple-dot-and-antidot-mode)) · **Updates:** automatic checks, what happens when one finds an update (see [Updates](#updates)), and Check Now · a link to support AutoHush |
| **Apps** | Every app that has played sound, each with a **Pauses Music** switch. **Ignore Another App…** adds an app before it ever plays. Right-click an app to remove it, or use **Reset List…** to start over |
| **Advanced** | Fine-tuning, with sensible defaults · **Detection:** how long an app must play before your music pauses (0.5 s), how long it must be quiet before your music resumes (2 s, at least 1 s), and what counts as silence (-60 dB) · **Fades:** how long the music fades out before pausing (1 s) and back in when it resumes (2 s; 0 turns either off; dimmed with TIDAL, which can't fade) · **Restore Defaults** undoes your changes |
| **Diagnostics** | What AutoHush sees right now, kept up to date while the tab shows: every app with its sound on, how AutoHush judges it (playing, ignored, silent) and why (its sound level, or in AntiDot mode what it tells macOS), then the detection in effect, your music player, auto-pause and ignored apps. **Copy Report** puts it all on the clipboard, to send along with a bug report |

### Language

AutoHush speaks English, Spanish (Spain and Latin America), Catalan, German, French (France and Canada), Italian, Portuguese (Brazil and Portugal), Japanese, Korean and Chinese (Simplified and Traditional). It uses the first of your Mac's preferred languages that it has (System Settings → General → Language & Region), and English otherwise. To give AutoHush a language of its own, add it to the Applications list in that same pane.

> [!WARNING]
> Only English, Spanish (Spain) and Catalan have been checked by a native speaker. The other languages were translated automatically, so they may contain mistakes or odd wording. If you spot one, please [open an issue](https://github.com/hfustercabre/AutoHush/issues) with the text and a better wording.

## The purple dot and AntiDot mode

To hear whether another app is *really* playing, AutoHush has to listen to its sound level. Whenever an app does that, macOS shows a **purple dot** in the menu bar. It's a privacy feature that no app can hide, and that's a good thing.

AutoHush keeps the dot to a minimum: it only listens while the answer matters, that is while your music is playing on this Mac (or was paused by AutoHush) and another app has its sound on. Your music player itself is never listened to. So:

- Your music playing on its own, paused, or on another device: **no dot**.
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

- **Your music doesn't come back after VLC.** VLC has its own setting that pauses Spotify and Apple Music. Because AutoHush didn't pause it, it won't resume it. Turn it off in **VLC → Settings → Interface → Control external music players → Do nothing**, and let AutoHush do the job.
- **I paused my music myself and it stayed paused.** That's on purpose: AutoHush only resumes music that *it* paused.
- **Switched players?** Music that AutoHush was holding paused in the previous player stays paused. From then on, that player counts like any other app.
- **TIDAL pauses without fading.** AutoHush can't read or set TIDAL's volume, so it pauses and resumes it straight away. It notices when you pause or play TIDAL yourself within about a second. If a TIDAL update changes its Playback menu, AutoHush may not be able to control it until AutoHush is updated too.
- **Only one AutoHush runs at a time.** Opening another copy (a newer version you downloaded, a second install) quits the one that's running. If that one had your music paused for another app, the new one takes the pause over. Other copies stay where they are; delete the ones you don't use.
- **Music keeps playing during a video.** Check that the app isn't ignored (menu → Ignored Apps), and that auto-pause isn't turned off.
- **Music stays paused after a video ends.** Some apps keep their sound switched on after playback. Grant the audio permission, or in AntiDot mode close the app or tab.
- **Something looks off?** Open **Settings → Diagnostics**, or hold **⌥ (Option)** and click **Settings** at the bottom of the menu to go straight there. It lists every app with sound, what AutoHush thinks it's doing, and the current settings, and **Copy Report** copies it.
- **"Spotify is not running"** (or another player), a permission warning, or "not responding": fix it, and AutoHush starts by itself: when the player opens, within seconds of granting the permission, or once the player answers again (it keeps asking, less and less often, up to once a minute). When the player didn't answer, **Retry** on the menu's card tries again at once, and the menu stays open to show how it went.

## Privacy

- AutoHush **never records, saves or sends audio**, and never uses the microphone.
- With the audio permission, it reads other apps' sound only to work out how loud it is, in memory, and throws the rest away.
- In AntiDot mode it doesn't look at any sound at all.
- It only goes online to check GitHub for a new version once a day, and to download that version from GitHub. You can turn off both (see below). Neither leaves a cache or cookies on your Mac, and a downloaded update is kept for at most 7 days.
- Its only notifications are about updates.
- It controls only the music player you chose: Spotify and Apple Music through the standard macOS automation mechanism, TIDAL by pressing Play/Pause in its Playback menu.

## Updates

AutoHush checks GitHub for a new version once a day. What happens when it finds one is up to you (Settings → General → **When an update is found**):

| Choice | What happens |
|---|---|
| **Notify me** | A notification tells you, and the menu offers **Install AutoHush 0.3.8…** |
| **Download it and notify me** | AutoHush downloads it, then a notification tells you it's ready. Installing it takes a second |
| **Install it automatically** (the default) | AutoHush installs it at a moment when it isn't holding your music paused and none of its windows or menus are open, then a notification says it was updated |

Until it's installed, the menu shows **Install AutoHush 0.3.8…** above its buttons, and its **Updates** button turns blue. It opens a window that says which version you're running and which one is available or downloaded, and what's new in it. Its button says what it will do: **Download and Install**, or **Install and Relaunch** when the update is already downloaded. Clicking a notification opens that same window.

Installing swaps in the new version and restarts, which takes about a second. Your settings and permissions carry over. If AutoHush has your music paused for another app when you install, the new version takes that pause over: your music comes back when the other app stops.

AutoHush asks for permission to send notifications when it first starts (while automatic checks are on). While notifications are off, **Notify me** and **Download it and notify me** are unavailable, since they couldn't tell you anything, and Settings says so, with a button to turn notifications on. If one of them was your choice, AutoHush moves it to **Install it automatically** and turns automatic checks off, so it installs nothing until you turn them back on. If you reset AutoHush's notifications in System Settings (right-click it in the Notifications list, then **Reset Notifications…**), it asks again: at once while its Settings window is open, otherwise within the hour.

**Downloaded updates** are kept in `~/Library/Caches/com.autohush.AutoHush/Updates`, one at a time, and never for long. A download is deleted when:

- it's installed, or you update AutoHush another way;
- a newer version comes out (that one is downloaded instead), or the release is withdrawn;
- you choose another option or turn automatic checks off;
- it's been there for 7 days. Then it isn't downloaded again; the menu still offers it.

Automatic downloads wait while Low Data Mode is on.

Before installing, AutoHush makes sure that:

- the download matches the checksum GitHub lists for it;
- the app inside is signed with the same certificate as the copy you have, the check macOS itself uses to keep AutoHush's permissions, so nothing but a genuine AutoHush gets installed this way;
- it's the version GitHub announced;
- a kept download hasn't changed since it was downloaded (otherwise it's downloaded again).

**Updates** at the bottom of the menu, or **Check Now** in Settings, checks right away. Turn off automatic checks in Settings to only check when you ask.

AutoHush can only update itself from a folder it can write to, such as Applications on an administrator account. Settings tells you when it can't. To update by hand:

- Installed with Homebrew: `brew upgrade --cask autohush`
- Installed by hand: download the new version from the releases page and replace the old one.

Versions up to 0.2.0 can't update themselves yet: update those once by hand.

## Uninstall

1. In Settings, turn off **Launch at login**, then quit AutoHush.
2. Delete `/Applications/AutoHush.app`, or run `brew uninstall --cask autohush`.
3. Optional: also delete its settings and a downloaded update that may be waiting, and forget the permissions you granted:

```bash
defaults delete com.autohush.AutoHush
```

```bash
rm -rf ~/Library/Caches/com.autohush.AutoHush ~/Library/HTTPStorages/com.autohush.AutoHush
```

```bash
tccutil reset All com.autohush.AutoHush
```

   With Homebrew, `brew uninstall --zap --cask autohush` deletes the app, its settings and its caches in one go; the permissions still need the `tccutil` line.

4. Optional: to remove AutoHush from System Settings → Notifications, right-click it there and choose **Reset Notifications…**.

## Support AutoHush

AutoHush is free. If it saves your ears a few times a day and you'd like to say thanks, you can buy me a coffee. It helps me keep improving it. The link is also in **About AutoHush** and at the bottom of **Settings → General**.

<p align="center">
  <a href="https://buymeacoffee.com/hfustercabre"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-violet.png" alt="Buy me a coffee" height="40"></a>
</p>

---

## For developers

### How it works

1. **Which apps have sound on.** AutoHush watches CoreAudio's list of audio processes with change listeners, plus a once-per-second resync that only asks the processes with audio running (each question is a round trip to the audio server). Helper processes are grouped under their app (Chrome's helpers count as "Google Chrome") using the process macOS holds responsible for them (`responsibility_get_pid_responsible_for_pid`, a private function resolved at runtime, with a fallback to the enclosing `.app`).
2. **Whether they're actually audible.**
   - *Normal mode:* each app is metered through a private, unmuted CoreAudio **process tap** that computes only its peak level.
   - *AntiDot mode ("What apps tell macOS"):* no taps. An app holding its own system-sleep **power assertion** (`IOPMCopyAssertionsByProcess`) counts as playing. An app seen doing that before but not now counts as paused, even with its output open; these apps are remembered across launches. Apps that never hold one count as playing while their output is open. Assertions held on an app's behalf (by `coreaudiod` or `runningboardd`) and display-only assertions are ignored.
3. **Filtering.** System sounds are played by `systemsoundserverd`, which is excluded outright. An app must be audible for 0.5 s to count as playing (this filters out chat tones) and silent for 2 s to count as stopped (this bridges gaps between tracks).
4. **Deciding.** `PlaybackArbiter` pauses the chosen player when the first app starts, and resumes it as soon as the last one stops, but only if it paused the player itself and the player is still paused. Pauses and resumes run on their own, so new events are handled even while the music fades.
5. **Fading.** `VolumeFader` fades the player's own volume logarithmically, in 0.1 s steps: the level drops at a steady rate in decibels to 50 dB below the user's volume over 1 s, then the player pauses and its volume is set back while paused; resuming plays from 50 dB below and rises back over 2 s. Each player's `VolumeCurve` turns decibels into its volume number (Spotify's is a cube law, Apple Music's is linear, both measured with `swift run measure-volume-curve`). The user's volume is remembered when a fade starts, so an interrupted fade never leaves it lower. If the other app stops during the fade-out, the music comes back up without pausing; if you pause the player yourself during the fade-out, AutoHush leaves it to you; quitting mid-fade sets the volume straight back. It works with any player that reports its volume; others pause and play directly.
6. **The players.** Spotify and Apple Music are both scripted with Apple events (`ScriptablePlayers`). Their state arrives as a distributed notification (`com.spotify.client.PlaybackStateChanged`, `com.apple.Music.playerInfo`) and is confirmed with an Apple event right before each pause or resume. Music posts each change twice, the old state first, so a notification that would end AutoHush's pause is checked with the player first. A player plays "on this Mac" only when its own process, or one of its helpers, has output running; otherwise it's on another device (Spotify Connect) and is left alone. TIDAL can't be scripted (`TidalSupport`): AutoHush presses the first item of its Playback menu through Accessibility, found by its ⌘← and ⌘→ items since its title is translated, and only from the opposite state. It reads TIDAL's state from that item's title, comparing it with TIDAL's own translations of Play and Pause read from the app, and checks it about once a second, since TIDAL announces nothing.

**The purple dot:** taps exist only while `PlaybackArbiter` says levels can change a decision (auto-pause on, and the player playing here or paused by us), with a 2 s release delay. The player itself is never tapped, except to prove the permission works when TCC can't be read.

**The audio permission:** macOS has no public API for it, and taps without it simply deliver silence. AutoHush reads it through the private `TCCAccessPreflight` / `TCCAccessRequest` (resolved at runtime, in `AutoHushKit/PrivateAPI`), re-checks it every 5 s, and falls back to "any open output counts" when it's denied. If a future macOS removes those functions, it infers the permission from tapped samples instead.

### Architecture

```text
AppDelegate ── lifecycle, bootstrap (launch, automatic retries, player relaunch), wiring features to the engine
  ├── StatusMenuController ── renders AppStatus into the menu bar item and menu
  ├── SettingsWindowController ── SwiftUI tabs backed by SettingsModel
  ├── UpdateController ── daily and manual checks against the latest GitHub release, then notifying, downloading (UpdateDownloads) or installing (UpdateInstaller), with notifications (UpdateNotifier)
  └── MonitoringPipeline ── one per bootstrap, started and torn down as a unit
        PlayerStateObserving ── the player's state (distributed notification, quit) ─┐
        AudioMonitor                                                                 │
          ├── HALAudioProcessSnapshotProvider: process list + is-running listeners   │
          ├── ProcessTapLevelMeter: per-app peak level (normal mode)                 │
          ├── IOKitPowerAssertionReader: who says "I'm playing" (AntiDot mode)       │
          ├── SourceActivityTracker: start confirmation + stop grace                 │
          └── ordered source events + "music plays on this Mac" ────┐                │
                                                                    ▼                ▼
                                                              PlaybackArbiter
                                                                ├── pauses the player on the first app
                                                                ├── resumes after all apps stop
                                                                ├── VolumeFader: logarithmic fades around both
                                                                └── MusicPlayer (ScriptablePlayer: Apple events)
```

AutoHush is a Swift package of several modules, so the compiler keeps the layers apart:

```text
AutoHush (executable: the entry point only)
  └─ AutoHushApp            the app: menu bar, Settings, updates, diagnostics, About, wiring
       ├─ AutoHushPlayers   the supported music players
       │    ├─ SpotifySupport, AppleMusicSupport, TidalSupport   one <App>Support module per player
       │    └─ ScriptablePlayers   shared by the players scripted with Apple events
       └─ AutoHushKit       the engine: no user interface, no specific player
measure-volume-curve (developer tool, in Tools/) → AutoHushPlayers, AutoHushKit
```

```text
Sources/
  AutoHush/              AutoHushMain (starts AutoHushApp)
  AutoHushApp/
    Main/                AutoHushApplication, AppDelegate (wiring), MonitoringPipeline (builds the
                         engine for each start), AppStatus (what the app shows), StatusPresentation
                         (icons and text for the engine's states and choices), AppHealthState,
                         OtherInstances (quits other running copies at launch)
    MenuBar/             StatusMenuController (the menu), StatusMenuModel (what its views show),
                         Views/ (the card, the duration buttons, the playing apps, the buttons at
                         the bottom), MenuBarIcon (the icon for each state, drawn in code)
    PlayerChoice/        PlayerOption (each player and whether it's installed), PlayerChooserWindowController
                         (the welcome window that asks for the music player)
    Settings/            SettingsWindowController, SettingsModel, LaunchAtLoginController,
                         Views/ (General, Apps, Advanced, Diagnostics, PlayerPopUp, RadioChoices)
    Updates/             UpdateController, UpdateChecker, UpdateInstaller (download, signature check, swap),
                         UpdateDownloads (the kept download), UpdateNotifier, UpdatePrompt and ReleaseNotes
                         (the update window), UpdateOffer (what the menu offers)
    Diagnostics/         DiagnosticsReport (what Settings → Diagnostics shows, and Copy Report's text)
    About/               AboutPanel
    General/             InfoAlert, ProjectInfo, AppIcon, NoteLabel, SystemSettingsPane+Open
  AutoHushKit/
    AudioDetection/      AudioMonitor, SourceActivityTracker, AudioSourceIdentifier,
                         PowerAssertionReader, PlaybackSignals (AntiDot mode's judge),
                         ActiveAudioReport (what Diagnostics shows), DetectionMethod (your choice),
                         DetectionMode (in effect), CoreAudio/ (process list, process taps and levels,
                         HAL helpers)
    Playback/            PlaybackArbiter, VolumeFader, PlaybackState, AutoPause (setting and snooze)
    MusicPlayers/        MusicPlayer (the interface), MusicPlayerCatalog (the players to choose from),
                         PlayerState, VolumeCurve, MusicPlayerError
    Permissions/         Permission (what's needed and where to grant it), AudioCapturePermission,
                         SystemSettingsPane
    PrivateAPI/          TCC, ProcessResponsibility: undocumented macOS functions, resolved at
                         runtime with fallbacks; check them after every major macOS release
    Configuration/       AppConfiguration, TimingSettings, AutomaticUpdates (the update choice)
    Storage/             Preferences
    General/             Logging, Comparable+Clamped
  AutoHushPlayers/       SupportedPlayers (the catalog of supported players)
  PlayersSupport/        one module per music player, plus what they share:
    ScriptablePlayers/   ScriptablePlayer (+AppleEvents): controls an app scripted with Apple events,
                         as its profile describes; PlayerStateObserver (its state notification)
    SpotifySupport/      Spotify's profile: codes, notification, volume quirk and curve
    AppleMusicSupport/   Apple Music's profile
    TidalSupport/        TidalPlayer: TIDAL through its Playback menu (Accessibility), TidalMenu,
                         TidalLabels (its own words for Play and Pause), TidalStateObserver
Tests/
  AutoHushAppTests/  AutoHushKitTests/  AutoHushPlayersTests/
  PlayersSupport/ScriptablePlayersTests/  SpotifySupportTests/  AppleMusicSupportTests/  TidalSupportTests/
                         (each mirrors its module; only the player modules' tests name a player)
  AutoHushTestSupport/   fakes and fixed dates shared by the test modules
Tools/
  MeasureVolumeCurve/    the volume-curve measuring tool (never part of the app)
Resources/               Info.plist, entitlements and AutoHush.icon (the app icon, an Icon Composer
                         document), assembled into the .app by Scripts/build-app.sh
  Localization/          the String Catalogs: Localizable.xcstrings (the app's text) and
                         InfoPlist.xcstrings (the permission prompts), in every language
```

**Where things go:**

- **`AutoHushKit`** is the engine. It has no user interface (no AppKit or SwiftUI) and knows no player by name; the app tells it which player was chosen. It can't import the app or a player module, and the compiler enforces that.
- **`AutoHushApp`** holds what you see and use, grouped by feature, plus `Main/`, which starts things, wires the features to the engine and owns the app-wide `AppStatus`. Features may use the engine and `General/`, not each other.
- **A player module** (`<App>Support`, in `PlayersSupport/`) holds everything specific to one music app. Apps scripted with Apple events share `ScriptablePlayers`, so their module is just a `ScriptablePlayerProfile`.
- **`PrivateAPI/`** is the only place that calls undocumented macOS functions.
- **Text people read** lives in the app, never in the engine: the text for the engine's states and choices is mostly in `Main/StatusPresentation.swift`, and Diagnostics gets plain facts from the engine (`ActiveAudioReport`) that the app words. Write it as `String(localized:)` or a SwiftUI text, with a `comment:` for translators when the context isn't obvious (see [Translations](#translations)). Logs stay in English.
- **`General/`** folders stay small: only helpers several parts of a module need.
- **Access:** types used across modules are marked `package`, visible inside AutoHush but to nothing outside it.
- **Tests** mirror their module's folders; `AutoHushAppTests/Localization/` checks the String Catalogs.

**Adding a music player:** the app and the engine only talk to players through the `MusicPlayer` protocol: its bundle ID and name, a permission check, its live state, `pause()` / `play()`, its volume (for fades; `nil` if it has none) and how that volume maps to loudness (`VolumeCurve`; linear if not given), and a `PlayerStateObserving` that reports state changes. A new player is:

1. a new module, `Sources/PlayersSupport/<App>Support/`, and its tests in `Tests/PlayersSupport/<App>SupportTests/` (both need a `path:` in `Package.swift`). If the app is scripted like Spotify and Music, the module is a `ScriptablePlayerProfile`: its bundle ID and name, the suite code of its pause and play commands (from the `.sdef` in its bundle), its state notification, and any quirk, such as Spotify's volume reading one less than it was set to. Otherwise it's a type implementing `MusicPlayer`, as `TidalPlayer` does;
2. an entry in `SupportedPlayers.catalog` (and a dependency of `AutoHushPlayers` in `Package.swift`), so it's offered in the menu, Settings and the welcome window;
3. its volume curve, measured with `swift run measure-volume-curve <bundle-id>`.

Defaults that aren't in Settings, such as tick rates, the gap tolerance and the excluded system processes, live in [`AppConfiguration.swift`](Sources/AutoHushKit/Configuration/AppConfiguration.swift). Any non-empty bundle ID that isn't excluded counts as a media app.

### Build and test

```bash
swift build      # build every module and the measuring tool
swift test       # run the tests of every module
bash Scripts/build-app.sh release   # build and sign AutoHush.app
swift run measure-volume-curve      # measure the first player's volume curve (or pass a bundle ID)
```

The tests use mock CoreAudio, level meter, power assertion and player implementations, so they never create real taps, script a real player or trigger permission prompts.

The app icon is `Resources/AutoHush.icon`, made of one layer (`Assets/bars.svg`) on a background that changes with the light and dark appearance. Edit it in Icon Composer (it comes with Xcode) or by hand. `build-app.sh` compiles it with Xcode's `actool`; without Xcode the app builds with the generic icon. To preview a change without building, render it with Icon Composer's `ictool`, which is inside the Icon Composer app bundle (`Icon Composer.app/Contents/Executables/ictool AutoHush.icon --export-image …`).

`measure-volume-curve [bundle-id] [volume …]` measures how a supported player's volume number maps to loudness, for its `VolumeCurve`, using the engine's own tap meter. It plays the music for about 50 seconds at changing volumes, prints a table in decibels and the best-fitting curve, then puts the volume and play state back. It needs permission to record system audio.

### Translations

AutoHush is translated into Spanish, Catalan, German, French, Italian, Portuguese, Japanese, Korean and Chinese; English is the source language and the fallback (see [Language](#language) for how macOS picks one). Four languages come in two variants, and macOS picks the closer one for each country:

| Language | Variants |
|---|---|
| Spanish | `es` Spain · `es-419` Latin America (Mexico, Argentina, US Spanish…) |
| French | `fr` France (also Belgium and Switzerland) · `fr-CA` Canada, with Quebec's punctuation: no space before `;` `?` `!` |
| Portuguese | `pt` Brazil · `pt-PT` Portugal (also Angola and Mozambique) |
| Chinese | `zh-Hans` Simplified (mainland China, Singapore) · `zh-Hant` Traditional (Taiwan, Hong Kong) |

A variant must translate every string: a missing one shows in English, not in the other variant.

- **Where the text lives:** in `Resources/Localization/`. `Localizable.xcstrings` is a String Catalog with all of the app's text, keyed by the English text; `InfoPlist.xcstrings` has the permission prompts and the copyright line from `Info.plist`. Both names are fixed: `Localizable` is the table macOS reads by default, and macOS translates `Info.plist` only from `InfoPlist`.
- **New text** needs no extra step: write it as `String(localized: "…", comment: "…")` or as a SwiftUI text. While building, the compiler lists every such string; `build-app.sh` adds new ones to `Localizable.xcstrings` and marks those no longer used as stale, as Xcode does, then compiles each language into the app (`<language>.lproj`). Delete stale strings once you're sure they're gone for good: they are still translated and shipped.
- **Adding a language:** open both catalogs in Xcode, add the language and translate (or edit the JSON), then build. Use the words macOS itself uses in that language (Ajustes, Einstellungen, Réglages…) and its typography (French spaces before `:` and `?`), and keep each `comment` in mind: it says where the text appears. Text not translated yet shows in English. The tests check that every translation keeps its placeholders (`%@`, `%lld`) and that `InfoPlist.xcstrings` matches `Info.plist`.
- **Trying a language:** quit AutoHush, then start it with `AutoHush.app/Contents/MacOS/AutoHush -AppleLanguages '(es)'`.
- **Not translated:** logs, the measuring tool and the disk image's background stay in English.

### Signing and releases

macOS remembers permissions per signing certificate. An unsigned ("ad hoc") build looks like a new app every time, and users would have to grant everything again. So AutoHush is signed with a stable self-signed certificate, **"AutoHush Self-Signed"**, and the hardened runtime.

**One-time setup:**

```bash
bash Scripts/create-signing-certificate.sh
```

This creates the certificate (valid 10 years) in your login keychain. The first build asks to let `codesign` use the key: choose **Always Allow**. Then **back it up**: in Keychain Access, open **login → My Certificates**, right-click "AutoHush Self-Signed", choose **Export…** and save a password-protected `.p12`. If you lose it, installed copies refuse to update themselves to a version signed with another certificate. Everyone would have to update by hand once, and grant the permissions again.

| Script | What it does |
|---|---|
| `Scripts/create-signing-certificate.sh` | Creates the signing certificate (once) |
| `Scripts/build-app.sh [release\|debug]` | Builds and signs `AutoHush.app` (`VERSION` / `BUILD_NUMBER` override the bundle version) |
| `Scripts/build-dmg.sh [version]` | Packages `dist/AutoHush-<version>.dmg`, which opens as a drag-to-Applications window in AutoHush's colours, with a first-launch note, and mounts as a disk with the app's icon. The background is drawn by `Scripts/lib/dmg-background.swift` with the app's own menu bar mark. Laying out the window scripts Finder (asks once for permission); `PLAIN_DMG=1` skips it |
| `Scripts/release.sh <version>` | Prepares a release: version and changelog, tests, signed build, DMG and release notes. It refuses unsigned builds and never commits, tags or publishes |
| `Scripts/update-tap.sh <version>` | Points the Homebrew tap at a published release: checks that the DMG on GitHub is the one in `dist/`, then commits the new version and checksum to the tap's cask and pushes it |

The signing identity is `SIGNING_IDENTITY` if set (`-` means ad hoc), otherwise "AutoHush Self-Signed" if it exists, otherwise ad hoc. `SIGNING_KEYCHAIN` points to another keychain (for example on CI). Ad-hoc builds reset AutoHush's permissions so macOS asks again; `KEEP_PERMISSIONS=1` skips that.

**Publishing a release:**

```bash
bash Scripts/release.sh 0.2.0
```

Then follow the printed steps: commit `Resources/Info.plist` and `CHANGELOG.md`, tag `v0.2.0` and push, then create the GitHub release with the DMG and the generated notes. Installed copies find the release at their next daily check and install its DMG themselves. That is why the DMG must keep its name, `AutoHush-<version>.dmg`, and be signed with the same certificate.

Last, point the Homebrew tap at the new release, for new Homebrew installs:

```bash
bash Scripts/update-tap.sh 0.2.0
```

The Mac App Store and Homebrew's official cask repository aren't options: both require Apple notarization, and the App Store would also reject the private functions AutoHush relies on.

## License

[MIT](LICENSE)
