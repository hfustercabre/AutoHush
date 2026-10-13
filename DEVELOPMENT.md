# Developing AutoHush

How AutoHush works and how its code is laid out, building and testing it,
its translations, contributing and releases. For using AutoHush, see the
[README](README.md).

## How it works

1. **Which apps have sound on.** AutoHush watches CoreAudio's list of audio processes with change listeners, plus a once-per-second resync that only asks the processes with audio running (each question is a round trip to the audio server). Helper processes are grouped under their app (Chrome's helpers count as "Google Chrome") using the process macOS holds responsible for them (`responsibility_get_pid_responsible_for_pid`, a private function resolved at runtime, with a fallback to the enclosing `.app`). Every Safari web app runs Safari's one "Web App" program, so a web app is named by the app it runs as (`NSRunningApplication`), not by its program. A process with no bundle ID of its own (a command-line player such as `afplay` or `mpv`) counts as the app responsible for it, e.g. Terminal; one no app owns, such as a system daemon, doesn't count.
2. **Whether they're actually audible.**
   - *Normal mode:* each app is metered through a private, unmuted CoreAudio **process tap** that computes only its peak level. Taps exist only while a level can change a decision (see the purple dot below); meanwhile an app is judged by AntiDot mode's rule when it's known to tell macOS it plays, so a paused VLC doesn't count just because it keeps its stream open for a minute.
   - *AntiDot mode ("What apps tell macOS"):* no taps. An app holding its own system-sleep **power assertion** (`IOPMCopyAssertionsByProcess`) counts as playing. An app seen doing that before but not now counts as paused, even with its output open. Apps that never hold one count as playing while their output is open. Assertions held on an app's behalf (by `coreaudiod` or `runningboardd`) are ignored. The names of each app's assertions are remembered across launches. An app that uses one name for both a display-sleep and a system-sleep assertion announces only video: WebKit (Safari) keeps the display awake while a video with sound is visible, and the system while it's hidden, but announces nothing for sound without video. Its display assertion then counts too, and it counts as paused only after dropping its assertion while its output stayed open, for at most 10 s (WebKit closes its output 7.5 s after a pause), so its sound without video is still judged by its open output. An app with no display-sleep assertion, so showing no video, must play for 3 s instead of 0.5 s, because Chromium keeps its "Playing audio" assertion for about 2.5 s after even a short sound.
3. **Filtering.** System sounds are played by `systemsoundserverd`, which is excluded outright. An app must be audible for 0.5 s to count as playing (this filters out chat tones) and silent for 2 s to count as stopped (this bridges gaps between tracks).
4. **Deciding.** `PlaybackArbiter` pauses the chosen player when the first app starts, and resumes it as soon as the last one stops, but only if it paused the player itself and the player is still paused. A player found paused by the check an app's start calls for counts as paused by AutoHush when it stopped playing as that app started: the app paused it (VLC does). That's from 0.5 s before the app was first heard (the monitor hears an app a tick or two late) to 1 s after (an app that pauses others does it at once; VLC within 0.3 s), so a pause the user makes while the app isn't counted as playing yet (3 s for sound without video in AntiDot mode) stays theirs. A player read once a second reports its stop too late to place it that precisely, so its stops are never taken over. Pauses and resumes run on their own, so new events are handled even while playback fades. A resume the player doesn't answer, or doesn't follow, is tried twice more, a second apart. When the Mac goes to sleep (`NSWorkspace.willSleepNotification`), a pause it holds is forgotten, and nothing is paused or resumed until the Mac is awake: other apps' sound stops as it falls asleep, and a web page can't be pressed then.
5. **Fading.** `VolumeFader` fades the player's own volume logarithmically, in 0.1 s steps: it falls at a steady rate in decibels to 50 dB below the user's volume over 1 s, then the player pauses and its volume is set back while paused; resuming plays from 50 dB below and rises back over 2 s. Each player's `VolumeCurve` turns decibels into its volume number (a cube law for Spotify, linear for Apple Music, both measured; a cube law for VLC, from its source). The user's volume is remembered when a fade starts, so an interrupted fade never leaves it lower: if the other app stops during the fade-out, playback comes back up without pausing; if you pause the player yourself, AutoHush leaves it to you; quitting mid-fade sets the volume straight back. Players without a readable volume pause and play directly.
6. **The players.** Spotify and Apple Music are both scripted with Apple events (`ScriptablePlayers`). Their state arrives as a distributed notification (`com.spotify.client.PlaybackStateChanged`, `com.apple.Music.playerInfo`) and is confirmed with an Apple event right before each pause or resume. Music posts each change twice, the old state first, so a notification that would end AutoHush's pause is checked with the player first. A player plays "on this Mac" only when its own process, or one of its helpers, has output running; otherwise it's on another device (Spotify Connect) and is left alone. VLC is scripted too (`VLCSupport`), with its own vocabulary: `play` toggles, so it's only sent from the opposite state; `playing` and `current time` (−1 without an item) tell playing, paused and stopped apart; and its `audio volume` goes from 0 to 512. TIDAL and Apple Podcasts can't be scripted (`MenuPlayers`): AutoHush presses the first item of their playback menu (TIDAL's Playback, Podcasts' Controls) through Accessibility, found by its ⌘← and ⌘→ items since its title is translated, and only from the opposite state. It reads the state from that item's title, comparing it with the running app's own translations of Play and Pause (TIDAL's `app.asar`, Podcasts' `Localizable.loctable`). VLC, TIDAL and Podcasts announce nothing, so their state is read about once a second (`PolledStateObserver`).
7. **Safari web apps** (`WebAppPlayers`):
   - **Finding them.** Each is a template app, `com.apple.Safari.WebApp.<UUID>`, found in ~/Applications and /Applications. A tested site's web app (`TestedWebApp`) is one that starts on that site: its Info.plist's `Manifest.start_url` has the same host, with or without "www." (for Amazon Music, any of its country sites: `CountrySites`, which Add a Web App also offers by country); until one is found, the site is suggested, and any other web app is untested. The other-Spaces search tries the first 1,000 element numbers, and further (up to 100,000) only when none of them is a window and the app has one out of sight; it stops after 1 s, so a frozen web app can't hold AutoHush up, and every page element waits at most 0.5 s for an answer. Its sound comes from its own WebKit process, which macOS holds the web app responsible for, so it's the player's output like any player's own process. AutoHush reads and presses the site's Play/Pause button through Accessibility, which WebKit offers for every page.
   - **Learning the button.** The button is learned once (`PlayPauseLearner`), from two looks at the page: at **It's Playing** (only while the web app can be heard), and once it's paused. AutoHush pauses it itself: it presses the keyboard's Play/Pause key (`PlayPauseKey`, a system-defined `NSEvent` posted to the HID event tap, which needs Accessibility), which macOS sends to the app it counts as playing now ("Now Playing"), the web app while its song plays, and reads the page every 0.5 s for 3 s. First it asks which app that is (`NowPlayingApp`: MediaRemote's private `MRMediaRemoteNowPlayingResolvePlayerPath` on a player path with no client, one of the few questions it still answers without Apple's entitlement); since one process keeps getting MediaRemote's first answer, a fresh copy of AutoHush, started with `--now-playing`, answers and quits. When another app is Now Playing (WebKit's media process counts as its web app), or none is, the key isn't pressed and the user pauses it (`SelfPause.keyGoesElsewhere`); with no answer, it's pressed as before; a change is read again 0.5 s later, since a song's own button can change before the player bar's. Once learned, the learned button plays it again. With no change (the site ignores it, or the key went to another app the check couldn't see), the key is pressed again to undo it, and the step is marked failed: **Try Again** takes a new look while it plays and tries the key again; **Pause It Manually** takes a new look, then the user pauses it and clicks **It's Paused**, within `LearningStatus.pauseWait` (a minute; then it starts over).
   - **Which button.** The buttons whose names changed between the two are candidates: the name while it played is the pause button's, the one after is the play button's. Nothing is guessed from the sound, so an ad before the song (YouTube Music's bar says "Play" meanwhile), a player bar that comes only once something plays, and a Mac slow to read the page don't matter, as they did when the button was learned by watching. The song's own button, a playlist's ("Play <playlist>") or a song's tile change along, so the buttons in sight win (a tile can be scrolled below the window), then those with a player's controls around them (a slider or progress bar within three elements up: SoundCloud's and YouTube Music's bars have one, tiles and rows don't; SoundCloud's bar says "Play current" while its tiles say "Play"), then the barest names, then the lowest button in the window, since players keep their controls at the bottom. While it learns, the page is read only at It's Playing, during the key's 3 s, and at It's Paused.
   - **Remembering it.** The recipe (`PlayPauseRecipe`) keeps the two names and where the button is: the kinds of element around it (not their names, which are translated) and its distance from the window's bottom. A reload makes every element new, so the button is found again by its names at that place, never by its names alone: another "Play" would start something else. **Learn Again** keeps the recipe, and keeps pressing its button, until It's Playing is taken (`LearningStatus.relearning`); it's forgotten then (and a mute standing in for a pause lifted), so nothing of a wrong one is kept, and closing the learning window before that keeps it (`keepLearned`).
   - **Windows and Spaces.** Each window has its own page, so two windows of a web app have two such buttons in the same place: the one saying it plays wins, and while the one in use says it's paused but the web app can be heard, the other windows are looked at again (every 2 s at most), so playback moved to another window is followed there. Windows on another Space aren't in Accessibility's window list, so they're reached through `_AXUIElementCreateWithRemoteToken`, a private function window managers use (`AccessibilityWindows`).
   - **Reading the state.** The state is read about once a second from the button's name, which the page has to answer, so while the web app is silent and its button says it isn't playing, only every 5 s (at once when its sound comes on, and always right before a pause or a resume); a press is checked to have changed it. With no window, the page is looked for again after 5 s, then twice as long each time, up to a minute, or at once when the web app's sound comes on.
   - **Add a Web App…** (`SafariWebAppMaker`) checks the address (`WebAddress`: http or https, a host with a dot, "https://" added when missing), asks the site with one HEAD request (GET when HEAD is refused; any answer but 404 or 410 counts), opens it in Safari and waits until the page has loaded. Safari makes the web app from the page it shows, so it then waits for the site itself (`WebAddress.isSameSite`: the host typed, with or without "www.", a part of a bare address typed, or the same service's site for another place: the same first two parts of the host followed only by com, a country's code alone or after co or com, such as "es", "co.uk" or "com.br", or the ending of a region or city, such as "cat" or "berlin"); another host of the same domain is the site asking something first (consent.youtube.com for music.youtube.com, accounts.spotify.com for open.spotify.com), looked at again every second while the user answers it. Then it waits for the user's **Add to Dock**, checks the page is still the site, brings Safari to the front (it opens its dialog only while it's the active app, and its menu is looked up again once it is: a menu item found before doesn't open it), and presses Safari's File menu item through Accessibility. The dialog is found by its identifiers, the same in every language (`AddToDock`, `AddToDockFormAddButton`…); its address is set back to the one typed if the page moved, though Safari on macOS 27 ignores an address set through Accessibility. Then the user names the web app and clicks Add there: the dialog is looked at every 0.3 s until it closes (cancelling the add in AutoHush clicks its Cancel). Once it closes, the new web app gets 20 s to appear; none by then, it was closed with Cancel, and Add to Dock waits again (a web app that comes later is still taken at the next click). The new web app is used only once Safari has sealed it with its code signature, about 0.3 s after its Info.plist appears: macOS won't open it before. macOS has no other way to make a web app.
   - **Muting.** A site that refuses to pause (its button disabled, as during an ad, or a press that doesn't take within 2 s) is muted instead with a Core Audio process tap muted while it's read, read by a private aggregate device whose IO block throws the samples away (`ProcessTapMuter`): macOS mutes nothing for a tap that nothing reads. Nothing is kept or rerouted, and removing it unmutes, on resume or when monitoring stops; should the reading stop, the sound comes back by itself. So is a site whose button says it's paused while it can be heard (YouTube Music's reads "Play" during an ad), when another app starts: since a paused page keeps its output open, silent, for seconds, the web app is first listened to for 0.5 s through level taps that exist only meanwhile (`ProcessTapLevelProbe`). While it's muted, its button is read about once a second; once it can pause (enabled, and saying it plays), it's pressed and the mute removed, so resuming goes on from there.

**The purple dot:** taps exist only while `PlaybackArbiter` says levels can change a decision (auto-pause on, and the player playing here or paused by us), with a 2 s release delay. The player itself is never tapped, except to prove the permission works when TCC can't be read.

**The audio permission:** macOS has no public API for it, and taps without it simply deliver silence. AutoHush reads it through the private `TCCAccessPreflight` / `TCCAccessRequest` (resolved at runtime, in `AutoHushKit/PrivateAPI`), re-checks it every 5 s, and falls back to "any open output counts" when it's denied. If a future macOS removes those functions, it infers the permission from tapped samples instead.

## Architecture

The words used for the parts below are in the [glossary](GLOSSARY.md).

```text
AppDelegate ── lifecycle, choosing the player, the windows, wiring features to the engine
  ├── AppState ── the one AppStatus: what the menu and the windows show, written by AppDelegate only
  ├── StatusMenuController ── renders AppStatus into the menu bar item and menu
  ├── SettingsWindowController ── a sidebar of SwiftUI pages backed by SettingsModel, which reads AppState
  ├── UpdateController ── daily and manual checks against the latest GitHub release, then notifying, downloading (UpdateDownloads) or installing (UpdateInstaller), with notifications (UpdateNotifier)
  └── PlayerSession ── the chosen player from its start until AutoHush quits: starts it (at launch, by itself after a failed start, when it opens), checks access again, keeps the held pauses and the hand-over
        └── MonitoringPipeline ── one per start, started and torn down as a unit; one a new player choice leaves mid-pause runs on in HeldPauses until it resumes its player
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
                                                                      └── MusicPlayer (ScriptablePlayer: Apple events; MenuPlayer and SafariWebAppPlayer: Accessibility)
```

AutoHush is a Swift package of several modules, so the compiler keeps the layers apart:

```text
AutoHush (executable: the entry point only)
  └─ AutoHushApp            the app: menu bar, Settings, updates, diagnostics, wiring
       ├─ AutoHushPlayers   the supported media players
       │    ├─ SpotifySupport, AppleMusicSupport, TidalSupport, PodcastsSupport, VLCSupport
       │    │                   one <App>Support module per player
       │    ├─ ScriptablePlayers   shared by the players scripted with Apple events
       │    ├─ MenuPlayers         shared by the players controlled through their playback menu
       │    └─ WebAppPlayers       Safari web apps, controlled through the site's own Play/Pause button
       └─ AutoHushKit       the engine: no user interface, no specific player
measure-volume-curve (developer tool, in Tools/) → AutoHushPlayers, AutoHushKit
listen-to-fades (developer tool, in Tools/): records a loopback device, measures fades
playercheck (tool, in Tools/) → ScriptablePlayers, MenuPlayers, WebAppPlayers, VLCSupport, AutoHushKit:
                            could AutoHush control an app? (Player Check shows it in a window)
```

```text
Sources/
  AutoHush/              AutoHushMain (starts AutoHushApp)
  AutoHushApp/
    Main/                AppDelegate (wiring; its web app, permission and Diagnostics parts in
                         AppDelegate+WebApps, +Permissions and +Diagnostics), PlayerSession (the chosen
                         player from its start until AutoHush quits), MonitoringPipeline
                         (the engine for each start), the app-wide state: AppState, which holds AppStatus (what
                         the menu and the windows show, with UpdateOffer), and SettingsModel (what only
                         Settings and the other windows show, and their actions), then
                         StatusPresentation (the status's icons and text), AppHealthState, PermissionCenter
                         (reads and asks for the permissions), OtherInstances (quits the copies opened before it),
                         MainMenu (the Mac's standard menu bar, while a window is open), HeldPauses (a player
                         left mid-pause keeps its monitoring until that pause ends)
    MenuBar/             StatusMenuController, StatusMenuModel and Views/ (the menu), MenuBarIcon (drawn in code)
    PlayerChoice/        the welcome window, Learning (the window for a player AutoHush learns, a Safari
                         web app) and AddWebApp (the Add a Web App window)
    Settings/            SettingsWindowController (the window, its pages and their sidebar),
                         LaunchAtLoginController, DiagnosticsReport (the Diagnostics page, and Copy Report's
                         text), Views/ (one per page: General, Apps, Detection, Fades, Diagnostics, Updates,
                         About; SettingsSidebar)
    Updates/             UpdateController, UpdateChecker, UpdateInstaller (download, signature check, swap),
                         UpdateDownloads (the kept download), UpdateNotifier, the update window
    General/             what several features show: PlayerOption (each player and whether it's installed),
                         PlayerTiles (the players as tiles), WebAppsHeading (the web apps' heading, its badges
                         and note), LearningSteps (the steps of learning a player, in the windows, and the
                         Controls row of the menu's card and Settings), PermissionButton, ChecklistStep,
                         CardStyles (the look the menu and Settings share), HostedWindowController and
                         WindowHeader (the welcome, learning and Add a Web App windows, in Settings' look),
                         DockPresence (in the Dock while a window is open), AppVersion, AppIcon, InfoAlert, …
  AutoHushKit/
    AudioDetection/      AudioMonitor, SourceActivityTracker, PlaybackSignals (AntiDot mode's judge),
                         ActiveAudioReport (what Diagnostics shows), CoreAudio/ (process list, taps, levels)
    Playback/            PlaybackArbiter, VolumeFader, PlaybackState, AutoPause (the setting and snoozes)
    MusicPlayers/        MusicPlayer (the interface), MusicPlayerCatalog, PlayerState, VolumeCurve,
                         PolledStateObserver (for players that announce nothing), WebAppMaking (making a
                         web app from an address, and the suggested ones), WebAddress (an address as
                         typed, and whether a page is its site), CountrySites (a service's site by
                         country), PlayerIconPlaceholder (a player's icon while it isn't installed)
    Permissions/         what's needed and where to grant it
    PrivateAPI/          TCC, ProcessResponsibility, AccessibilityWindows, NowPlayingApp: undocumented macOS
                         functions, resolved at runtime with fallbacks; check them after every major macOS
                         release
    Configuration/       AppConfiguration, TimingSettings, AutomaticUpdates
    Storage/, General/   Preferences; logging and small helpers
  AutoHushPlayers/       SupportedPlayers (the catalog of supported players)
  PlayersSupport/        ScriptablePlayers and MenuPlayers (shared), SpotifySupport, AppleMusicSupport,
                         TidalSupport, PodcastsSupport and VLCSupport: each player's profile or controller,
                         and its placeholder icon; WebAppPlayers: Safari web apps (finding them, learning
                         their button, controlling them)
Tests/                   a test module per module, mirroring its folders (only the player modules' tests
                         name a player), plus AutoHushTestSupport (shared fakes)
Tools/                   tools for measuring the fades and checking apps, never part of the app or its disk
                         image; each has a README.md saying what it does and how (Tools/README.md lists them)
  MeasureVolumeCurve/    measures a player's volume curve
  ListenToFades/         records a loopback device and measures the fades in it
  LoopbackDriver/        AutoHush Loopback, a test-only virtual audio device, with build, install and
                         uninstall scripts
  PlayerCheck/           playercheck: whether and how AutoHush could control an app
  PlayerCheckApp/        Player Check, the same in a window, with Play and Pause for the apps it can control
Resources/               Info.plist, entitlements, AutoHush.icon (the app icon), and Localization/ with the
                         String Catalogs, assembled into the .app by Scripts/build-app.sh
```

**Where things go:**

- **`AutoHushKit`** has no user interface (no AppKit or SwiftUI) and knows no player by name; the app tells it which player was chosen. It can't import the app or a player module, and the compiler enforces that.
- **`AutoHushApp`** holds what you see and use, grouped by feature, plus `Main/`, which starts things, wires the features to the engine and owns the app-wide state (`AppState`, holding the `AppStatus` that the menu and the windows show; `SettingsModel` for what only the windows show). Features may use the engine, `General/` and that state, not each other: what several of them show lives in `General/`.
- **A player module** (`<App>Support`, in `PlayersSupport/`) holds everything specific to one media app. Apps scripted with Apple events share `ScriptablePlayers`, so their module is just a `ScriptablePlayerProfile`; apps controlled through their playback menu share `MenuPlayers`, so theirs is a `MenuPlayerProfile` and a way to read their words for Play and Pause.
- **`PrivateAPI/`** is the only place that calls undocumented macOS functions.
- **Text people read** lives in the app, never in the engine: mostly in `Main/StatusPresentation.swift`, while Diagnostics gets plain facts from the engine (`ActiveAudioReport`) and words them. Write it as `String(localized:)` or a SwiftUI text, with a `comment:` for translators when the context isn't obvious (see [Translations](#translations)). Logs stay in English.
- **`General/`** folders hold only what several parts of a module need.
- **Access:** types used across modules are marked `package`, visible inside AutoHush but to nothing outside it.

**Adding a media player:** first check that the app can be controlled, and how: [PlayerCheck](Tools/PlayerCheck) (or [Player Check](Tools/PlayerCheckApp), in a window) reads its scripting dictionary, playback menu and page, tries pausing and playing it, and says which kind of player it would be. The app and the engine only talk to players through the `MusicPlayer` protocol: its bundle ID and name, a permission check, its live state, `pause()` / `play()`, its volume (for fades; `nil` if it has none) and how that volume maps to loudness (`VolumeCurve`; linear if not given), and a `PlayerStateObserving` that reports state changes. A new player is:

1. a new module, `Sources/PlayersSupport/<App>Support/`, and its tests in `Tests/PlayersSupport/<App>SupportTests/` (both need a `path:` in `Package.swift`). If the app is scripted like Spotify and Music, the module is a `ScriptablePlayerProfile`: its bundle ID and name, the suite code of its pause and play commands (from the `.sdef` in its bundle), its state notification, and any quirk, such as Spotify's volume reading one less than it was set to. If it can't be scripted but has a playback menu with Play/Pause first and ⌘← and ⌘→ items, as TIDAL and Podcasts do, it's a `MenuPlayerProfile`: its bundle ID, name, menu name and how to read its own words for Play and Pause from its bundle. Otherwise it's a type implementing `MusicPlayer`, as `VLCPlayer` does;
2. an entry in `SupportedPlayers.catalog` (and a dependency of `AutoHushPlayers` in `Package.swift`), so it's offered in the menu, Settings and the welcome window;
3. its placeholder icon, a `PlayerIconPlaceholder` in its module (as `SpotifyIcon.swift`): its tile's colors and its mark drawn as a path on a 1000-point tile, shown while the app isn't installed. The catalog's tests check that every player has one;
4. its volume curve: linear until it's measured. The maintainer measures it before the player ships.

A website needs none of this: added to the Dock from Safari, it's offered as a player, and AutoHush learns its Play/Pause button. `MusicPlayerCatalog` takes such players besides the built-in ones (`found`) and the sites it suggests adding (`suggested`); a player that has to learn implements `LearningMusicPlayer`, whose status the app shows, and one that may mute itself implements `MutingMusicPlayer`. Once a website has been tested live, add it to `SupportedPlayers.testedWebApps`: its web app is then offered first and suggested until added, instead of being marked untested.

Defaults that aren't in Settings, such as tick rates, the gap tolerance and the excluded system processes, live in [`AppConfiguration.swift`](Sources/AutoHushKit/Configuration/AppConfiguration.swift). Any non-empty bundle ID that isn't excluded counts as a media app.

## Build and test

```bash
swift build      # build every module and the tools
swift test       # run the tests of every module
AUTOHUSH_QUICK_TESTS=1 swift test   # the same without the slow ones (real disk images)
bash Scripts/build-app.sh release   # build and sign AutoHush.app
```

The tests use mock CoreAudio, level meter, power assertion and player implementations, so they never create real taps, script a real player or trigger permission prompts.

The app icon is `Resources/AutoHush.icon`, an Icon Composer document (Icon Composer comes with Xcode): one layer, `Assets/bars.svg`, on a background that changes with the light and dark appearance. `build-app.sh` compiles it with Xcode's `actool`; without Xcode the app builds with the generic icon. To preview a change without building, use Icon Composer's `ictool` (`Icon Composer.app/Contents/Executables/ictool AutoHush.icon --export-image …`).

## Style guide

[STYLE_GUIDE.md](STYLE_GUIDE.md) describes how AutoHush looks and reads: its layout, text sizes, colors and shared components, how to write its text, and how to check a visible change. Follow it, and update it when a change adds a new pattern.

## Translations

English is the source language and the fallback; [Language](README.md#language) lists the translations and how macOS picks one. They are every European language and the most spoken other languages that macOS itself is translated into. Norwegian is `nb` (Bokmål), which macOS also offers to Nynorsk users. Four languages come in variants, and macOS picks the closest one for each country:

| Language | Variants |
|---|---|
| Spanish | `es` Spain · `es-419` Latin America (Mexico, Argentina, US Spanish…) |
| French | `fr` France (also Belgium and Switzerland) · `fr-CA` Canada, with Quebec's punctuation: no space before `;` `?` `!` |
| Portuguese | `pt` Brazil · `pt-PT` Portugal (also Angola and Mozambique) |
| Chinese | `zh-Hans` Simplified (mainland China, Singapore) · `zh-Hant` Traditional (Taiwan) · `zh-HK` Traditional for Hong Kong (also Macau and Cantonese) |

A variant must translate every string: a missing one shows in English, not in the other variant.

- **Where the text lives:** in `Resources/Localization/`. `Localizable.xcstrings` is a String Catalog with all of the app's text, keyed by the English text; `InfoPlist.xcstrings` has the permission prompts and the copyright line from `Info.plist`. Both names are fixed: `Localizable` is the table macOS reads by default, and macOS translates `Info.plist` only from `InfoPlist`.
- **New text** needs no extra step: write it as `String(localized: "…", comment: "…")` or as a SwiftUI text. `build-app.sh` adds new strings to `Localizable.xcstrings` and marks those no longer used as stale, as Xcode does, then compiles each language into the app. Delete stale strings once you're sure they're gone for good: they are still translated and shipped.
- **Adding a language:** open both catalogs in Xcode, add the language and translate (or edit the JSON), then build. Use the words macOS itself uses in that language (Ajustes, Einstellungen, Réglages…) and its typography (French spaces before `:` and `?`), and keep each `comment` in mind: it says where the text appears. Text not translated yet shows in English. The tests check that every translation keeps its placeholders (`%@`, `%lld`) and that `InfoPlist.xcstrings` matches `Info.plist`.
- **Trying a language:** quit AutoHush, then start it with `AutoHush.app/Contents/MacOS/AutoHush -AppleLanguages '(es)'`.
- **Not translated:** logs, the measuring tools and the disk image's background stay in English.

## Contributing

Contributions are welcome. The repository has two branches:

- **`main`** holds the latest release. It only moves when a new version is published.
- **`wip`** is where development happens. Every change goes there first.

To propose a change, fork the repository and create a branch from `wip` whose name starts with what it is: **`fix-`** for a bug fix, **`feature-`** for something new, or **`change-`** for a change to how something already works (for example `fix-vlc-resume` or `feature-qobuz`). Then open a pull request into **`wip`**, not `main`. I review every pull request before approving and merging it, and it reaches `main` with the next release. Before you open it, check that it builds and its tests pass (see [Build and test](#build-and-test)) and that it follows the [style guide](STYLE_GUIDE.md). A check on every pull request flags one whose branch name or target doesn't follow this, and another builds it and runs the tests; [CONTRIBUTING.md](CONTRIBUTING.md) has it all in one place.

To report a problem or suggest something, [open an issue](https://github.com/hfustercabre/AutoHush/issues/new/choose): there's a form for a bug (with Diagnostics' report, from **Settings → Diagnostics → Copy Report**), a feature, a player you'd like AutoHush to support (with [Player Check](Tools/PlayerCheckApp)'s report) and a translation fix. A security problem goes privately, as [SECURITY.md](SECURITY.md) says.

## Signing and releases

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
| `Scripts/build-dmg.sh [version]` | Packages `dist/AutoHush-<version>.dmg`: a drag-to-Applications window in AutoHush's colours, with a first-launch note, drawn by `Scripts/lib/dmg-background.swift` and laid out by [dmgbuild](https://github.com/dmgbuild/dmgbuild) (`Scripts/lib/dmg-settings.py`), without Finder. dmgbuild is installed on first use into `.build/`, pinned and hash-checked (`Scripts/lib/dmgbuild-requirements.txt`); it needs Python 3.10 or later (`PYTHON` picks one) |
| `Scripts/release.sh <version>` | Prepares a release: tests, version and changelog, signed build, DMG and release notes. It refuses unsigned builds and never commits, tags or publishes |
| `Scripts/update-tap.sh <version>` | Points the Homebrew tap at a published release: checks that the DMG on GitHub is the one in `dist/`, then commits the new version and checksum to the tap's cask and pushes it |

The signing identity is `SIGNING_IDENTITY` if set (`-` means ad hoc), otherwise "AutoHush Self-Signed" if it exists, otherwise ad hoc. `SIGNING_KEYCHAIN` points to another keychain (for example on CI). Ad-hoc builds reset AutoHush's permissions so macOS asks again; `KEEP_PERMISSIONS=1` skips that.

**Publishing a release:** releases are made on the `wip` branch. Run `bash Scripts/release.sh <version>` there and follow the steps it prints: commit `Resources/Info.plist` and `CHANGELOG.md` and tag `v<version>` on `wip`, move `main` to that commit (a fast-forward), push both branches and the tag, create the GitHub release with the DMG and the generated notes, then run `bash Scripts/update-tap.sh <version>` for Homebrew. Installed copies find the release at their next daily check: they compare its tag with their own version and install `AutoHush-<version>.dmg`. So the tag must match the app's version, and the DMG must keep its name and be signed with the same certificate.

The Mac App Store and Homebrew's official cask repository aren't options: both require Apple notarization, and the App Store would also reject the private functions AutoHush relies on.
