# Developing AutoHush

How AutoHush works and how its code is laid out, building and testing it,
its translations, contributing and releases. For using AutoHush, see the
[README](README.md); for every workflow as a flowchart,
[WORKFLOWS.md](WORKFLOWS.md).

## How it works

1. **Which apps have sound on.** AutoHush watches CoreAudio's list of audio processes with change listeners, plus a once-per-second resync that only asks the processes with audio running (each question is a round trip to the audio server). Helper processes are grouped under their app (Chrome's helpers count as "Google Chrome") using the process macOS holds responsible for them (`responsibility_get_pid_responsible_for_pid`, a private function resolved at runtime, with a fallback to the enclosing `.app`). Every Safari web app runs Safari's one "Web App" program, so a web app is named by the app it runs as (`NSRunningApplication`), not by its program. A process with no bundle ID of its own (a command-line player such as `afplay` or `mpv`) counts as the app responsible for it, e.g. Terminal; one no app owns, such as a system daemon, doesn't count.
2. **Whether they're actually audible.**
   - *Normal mode:* each app is metered through a private, unmuted CoreAudio **process tap** that computes only its peak level. Taps exist only while a level can change a decision (see the purple dot below); meanwhile an app is judged by AntiDot mode's rule when it's known to tell macOS it plays, so a paused VLC doesn't count just because it keeps its stream open for a minute.
   - *AntiDot mode ("What apps tell macOS"):* no taps. An app holding its own system-sleep **power assertion** (`IOPMCopyAssertionsByProcess`) counts as playing. An app seen doing that before but not now counts as paused, even with its output open. Apps that never hold one count as playing while their output is open. Assertions held on an app's behalf (by `coreaudiod` or `runningboardd`) are ignored. They're read at every tick while another app's output is open (not with Open audio streams only). The names of each app's assertions are remembered across launches. An app that uses one name for both a display-sleep and a system-sleep assertion announces only video: WebKit (Safari) keeps the display awake while a video with sound is visible, and the system while it's hidden, but announces nothing for sound without video. Its display assertion then counts too, and it counts as paused only after dropping its assertion while its output stayed open, for at most 10 s (WebKit closes its output 7.5 s after a pause), so its sound without video is still judged by its open output. An app with no display-sleep assertion, so showing no video, must play for 3 s instead of 0.5 s, because Chromium keeps its "Playing audio" assertion for about 2.5 s after even a short sound.
3. **Filtering.** System sounds are played by `systemsoundserverd`, which is excluded outright. An app must be audible for 0.5 s to count as playing (this filters out chat tones) and silent for 2 s to count as stopped (this bridges gaps between tracks).
4. **Deciding.** `PlaybackArbiter` pauses the chosen player when the first app starts, and resumes it as soon as the last one stops, but only if it paused the player itself and the player is still paused. A player found paused by the check an app's start calls for counts as paused by AutoHush when it stopped playing as that app started: the app paused it (VLC does). That's from 0.5 s before the app was first heard (the monitor hears an app a tick or two late) to 1 s after (an app that pauses others does it at once; VLC within 0.3 s), so a pause the user makes while the app isn't counted as playing yet (3 s for sound without video in AntiDot mode) stays theirs. A player read once a second reports its stop too late to place it that precisely, so its stops are never taken over. Pauses and resumes run on their own, so new events are handled even while playback fades. Each pause and play is checked to have taken (`PressCheck`): the player's state is read for up to 3 s, a press it missed is made once more, and one it still ignores fails (`pressIgnored`); a web app and an added app check their own. A resume the player doesn't answer, or doesn't follow, is tried twice more, a second apart. With **Resume playback** off (Settings → Behavior, on by default), no resume is made: once the apps stop, the pause becomes the user's (`keepPaused`, as with Stay paused after calls), a mute standing in for it turned into a real pause. When the Mac goes to sleep (`NSWorkspace.willSleepNotification`), a pause it holds is forgotten, and nothing is paused or resumed until the Mac is awake: other apps' sound stops as it falls asleep, and a web page can't be pressed then.
5. **Fading.** `VolumeFader` fades the player's own volume logarithmically, in 0.1 s steps: it falls at a steady rate in decibels to 50 dB below the user's volume over 1 s, then the player pauses and its volume is set back while paused; resuming plays from 50 dB below and rises back over 2 s. Each player's `VolumeCurve` turns decibels into its volume number (a cube law for Spotify, linear for Apple Music, both measured; a cube law for VLC, from its source). The user's volume is remembered when a fade starts, so an interrupted fade never leaves it lower: if the other app stops during the fade-out, playback comes back up without pausing; if you pause the player yourself, AutoHush leaves it to you; quitting mid-fade sets the volume straight back. Players without a readable volume pause and play directly.
   - **Leveling the music** (Settings → Behavior, off by default). `ResumeLevel` keeps the music's loudness before AutoHush's pause (the loudest 1 s RMS in the last 6 s it was heard, so the fade-out doesn't count) and the other apps' average RMS while heard during it, calls left out. As the music resumes, `AudioMonitor.resumeOffsetDB()` says how much quieter the apps were (Settings → Behavior's **Only when quieter by**, 2 dB by default, 1–10, and **Lower by at most**, 10 dB by default, 2–20), and `SystemVolumeLeveler` lowers the output's own volume by that much (`kAudioDevicePropertyVolumeDecibels`, each channel by the same, so the balance stays) before the player plays, so it isn't heard; at the next pause it glides back up over the fade-out. If the volume changed meanwhile (by more than 0.5 dB), also during the glide back up, it's the user's and stays; an output with no settable volume (HDMI, DisplayPort, AutoHush Loopback) is left alone; turning the setting off, quitting, or music that doesn't resume after all (a resume that gives up) puts it back at once, without waiting for a glide under way (one leveler serves the whole app, every pipeline included). What it lowered (the output, its volume before and after) is kept in the preferences until it's put back, so after a crash the next launch puts the volume back if it still reads the lowered value and was lowered less than an hour before. Off in AntiDot mode, which measures nothing.
   - **Outputs going away.** With **Pause on disconnect** (Settings → Behavior, off by default), `CoreAudioOutputDisconnectWatcher` follows the output in use (`kAudioHardwarePropertyDefaultOutputDevice`): it went away when it leaves the devices (`kAudioHardwarePropertyDevices`: Bluetooth, USB, AirPods, and on Apple silicon the headphone jack's "External Headphones") or its jack says it's unplugged (`kAudioDevicePropertyJackIsConnected`, older Macs); signs within 2 s are one disconnect, and choosing another output doesn't count. The arbiter (`handleOutputDisconnected`, with Auto-Pause on) then pauses music playing here at once (`VolumeFader.pauseNow`, no fade), and a pause of its own, held or fading out, becomes the user's: nothing resumes it.
   - **Calls.** An app whose input runs while it plays (`kAudioProcessPropertyIsRunningInput`) is in a call, told to the arbiter within a second. With **Pause for the microphone** (Settings → Behavior, off by default), apps with only their input running are read too (`activeProcesses(includingInputOnly:)`, one more property read for each process not playing), and an app with its microphone on counts as playing once it's been on for `microphoneStartConfirmation` (1 s, so apps that only touch it as they open don't count; sooner if its sound counts sooner), and as in a call; until it makes a sound, its `AudioSource` is `isMicrophoneOnly`, for the card's "is using the microphone". With **Stay paused after calls** (Settings → Behavior), a call during AutoHush's pause, or the one it began for, leaves the player paused when the apps stop.
6. **The players.** Spotify and Apple Music are both scripted with Apple events (`ScriptablePlayers`). Their state arrives as a distributed notification (`com.spotify.client.PlaybackStateChanged`, `com.apple.Music.playerInfo`) and is confirmed with an Apple event right before each pause or resume. Music posts each change twice, the old state first, so a notification that would end AutoHush's pause is checked with the player first. A player plays "on this Mac" only when its own process, or one of its helpers, has output running; otherwise it's on another device (Spotify Connect) and is left alone. VLC is scripted too (`VLCSupport`), with its own vocabulary: `play` toggles, so it's only sent from the opposite state; `playing` and `current time` (−1 without an item) tell playing, paused and stopped apart; and its `audio volume` goes from 0 to 512. QuickTime Player is scripted on its documents (`QuickTimeSupport`, a `ScriptedAppPlayer` with a fixed `ScriptSetup`, as an app added by its AppleScript is): a pause goes to each document playing, a play back to those it paused, never to another (with none paused, as after an update's relaunch hands a pause over, to the only document open); a document's `playing` tells the state, and with no document open it's stopped. It fades through each document's `audio volume` (`ScriptSetup.documentVolume`: 0–1, set on the documents playing, else those it fades or paused), which is linear. TIDAL and Apple Podcasts can't be scripted (`MenuPlayers`): AutoHush presses the first item of their playback menu (TIDAL's Playback, Podcasts' Controls) through Accessibility, found by its ⌘← and ⌘→ items since its title is translated (or, as Player Check finds Deezer's, by its first item on Space and ← and → under other modifiers), and only from the opposite state. It reads the state from that item's title, comparing it with the running app's own translations of Play and Pause (TIDAL's `app.asar`, Podcasts' `Localizable.loctable`). VLC, QuickTime Player, TIDAL and Podcasts announce nothing, so their state is read about once a second (`PolledStateObserver`).
7. **Safari web apps** (`WebAppPlayers`):
   - **Finding them.** Each is a template app, `com.apple.Safari.WebApp.<UUID>`, found in ~/Applications and /Applications. A tested site's web app (`TestedWebApp`) is one that starts on that site: its Info.plist's `Manifest.start_url` has the same host, with or without "www." (for Amazon Music, any of its country sites: `CountrySites`, which Add a Web App also offers by country); until one is found, the site is suggested, and any other web app is untested. The other-Spaces search tries the first 1,000 element numbers, and further (up to 100,000) only when none of them is a window and the app has one out of sight; it stops after 1 s, so a frozen web app can't hold AutoHush up, and every page element waits at most 0.5 s for an answer. Its sound comes from its own WebKit process, which macOS holds the web app responsible for, so it's the player's output like any player's own process. AutoHush reads and presses the site's Play/Pause button through Accessibility, which WebKit offers for every page.
   - **Learning the button.** The button is learned once (`PlayPauseLearner`), from two looks at the page: at **It's Playing** (only while the web app can be heard), and once it's paused. AutoHush pauses it itself: it presses the keyboard's Play/Pause key (`PlayPauseKey`, a system-defined `NSEvent` posted to the HID event tap, which needs Accessibility), which macOS sends to the app it counts as playing now ("Now Playing"), the web app while its song plays, and reads the page every 0.5 s for 3 s. First it asks which app that is (`NowPlayingApp`: MediaRemote's private `MRMediaRemoteNowPlayingResolvePlayerPath` on a player path with no client, one of the few questions it still answers without Apple's entitlement); since one process keeps getting MediaRemote's first answer, a fresh copy of AutoHush, started with `--now-playing`, answers and quits. When another app is Now Playing (WebKit's media process counts as its web app), or none is, the key isn't pressed and the user pauses it (`SelfPause.keyGoesElsewhere`); with no answer, it's pressed as before; a change is read again 0.5 s later, since a song's own button can change before the player bar's. Once learned, the learned button plays it again. With no change (the site ignores it, or the key went to another app the check couldn't see), the key is pressed again to undo it, and the step is marked failed: **Try Again** takes a new look while it plays and tries the key again; **Pause It Yourself** takes a new look, then the user pauses it and clicks **It's Paused**, within `LearningStatus.pauseWait` (a minute; then it starts over).
   - **Which button.** The buttons whose names changed between the two are candidates: the name while it played is the pause button's, the one after is the play button's. Nothing is guessed from the sound, so an ad before the song (YouTube Music's bar says "Play" meanwhile), a player bar that comes only once something plays, and a Mac slow to read the page don't matter, as they did when the button was learned by watching. The song's own button, a playlist's ("Play <playlist>") or a song's tile change along, so the buttons in sight win (a tile can be scrolled below the window), then those with a player's controls around them (a slider or progress bar within three elements up: SoundCloud's and YouTube Music's bars have one, tiles and rows don't; SoundCloud's bar says "Play current" while its tiles say "Play"), then the barest names, then the lowest button in the window, since players keep their controls at the bottom. While it learns, the page is read only at It's Playing, during the key's 3 s, and at It's Paused.
   - **Remembering it.** The recipe (`PlayPauseRecipe`) keeps the two names and where the button is: the kinds of element around it (not their names, which are translated) and its distance from the window's bottom. A reload makes every element new, so the button is found again by its names at that place, never by its names alone: another "Play" would start something else. **Learn Again** keeps the recipe, and keeps pressing its button, until It's Playing is taken (`LearningStatus.relearning`); it's forgotten then (and a mute standing in for a pause lifted), so nothing of a wrong one is kept, and closing the learning window before that keeps it (`keepLearned`).
   - **Windows and Spaces.** Each window has its own page, so two windows of a web app have two such buttons in the same place: the one saying it plays wins, and while the one in use says it's paused but the web app can be heard, the other windows are looked at again (every 2 s at most), so playback moved to another window is followed there. Windows on another Space aren't in Accessibility's window list, so they're reached through `_AXUIElementCreateWithRemoteToken`, a private function window managers use (`AccessibilityWindows`).
   - **Reading the state.** The state is read about once a second from the button's name, which the page has to answer, so while the web app is silent and its button says it isn't playing, only every 5 s (at once when its sound comes on, and always right before a pause or a resume); a press is checked to have changed it. With no window, the page is looked for again after 5 s, then twice as long each time, up to a minute, or at once when the web app's sound comes on.
   - **Add a Web App…** (`SafariWebAppMaker`) checks the address (`WebAddress`: http or https, a host with a dot, "https://" added when missing), asks the site with one HEAD request (GET when HEAD is refused; any answer but 404 or 410 counts), opens it in Safari and waits until the page has loaded. Safari makes the web app from the page it shows, so it then waits for the site itself (`WebAddress.isSameSite`: the host typed, with or without "www.", a part of a bare address typed, or the same service's site for another place: the same first two parts of the host followed only by com, a country's code alone or after co or com, such as "es", "co.uk" or "com.br", or the ending of a region or city, such as "cat" or "berlin"); another host of the same domain is the site asking something first (consent.youtube.com for music.youtube.com, accounts.spotify.com for open.spotify.com), looked at again every second while the user answers it. Then it waits for the user's **Add to Dock**, checks the page is still the site, brings Safari to the front (it opens its dialog only while it's the active app, and its menu is looked up again once it is: a menu item found before doesn't open it), and presses Safari's File menu item through Accessibility. The menu item and the dialog are found by their identifiers, the same in every language (`AddToDock`, which Safari 17 calls `generateWebAppForCurrentPage:`, `AddToDockFormAddButton`…); its address is set back to the one typed if the page moved, though Safari on macOS 27 ignores an address set through Accessibility. Then the user names the web app and clicks Add there: the dialog is looked at every 0.3 s until it closes (cancelling the add in AutoHush clicks its Cancel). Once it closes, the new web app gets 20 s to appear; none by then, it was closed with Cancel, and Add to Dock waits again (a web app that comes later is still taken at the next click). The new web app is used only once Safari has sealed it with its code signature, about 0.3 s after its Info.plist appears: macOS won't open it before. It's then chosen as the player; macOS may list it a little late, so it's looked for again up to 10 times, 0.5 s apart (a player the user picks meanwhile is kept). Still not listed, the window says it was added but can't be found yet, and takes it by itself once it's listed (looked for once a second meanwhile). macOS has no other way to make a web app.
   - **Muting.** A site that refuses to pause (its button disabled, as during an ad, or a press that doesn't take within 2 s) is muted instead with a Core Audio process tap muted while it's read, read by a private aggregate device whose IO block throws the samples away (`ProcessTapMuter`): macOS mutes nothing for a tap that nothing reads. Nothing is kept or rerouted, and removing it unmutes, on resume or when monitoring stops; should the reading stop, the sound comes back by itself. So is a site whose button says it's paused while it can be heard (YouTube Music's reads "Play" during an ad), when another app starts: since a paused page keeps its output open, silent, for seconds, the web app is first listened to for 0.5 s through level taps that exist only meanwhile (`ProcessTapLevelProbe`). While it's muted, its button is read about once a second; once it can pause (enabled, and saying it plays), it's pressed and the mute removed, so resuming goes on from there.
8. **Apps added with Add an App…** (`CheckedPlayers`):
   - **The check.** Add an App runs AutoHush's helper, playercheck (`Contents/Helpers`), in a process of its own (`PlayerCheckRun`), so a check that ends, is stopped or crashes takes its block on the mouse and keyboard with it. It finds the app's ways, presses each with the window in each state, and writes what worked (`CheckResult`). The user chooses one way, and Use keeps it in AutoHush's preferences as the app's `PlayerSetup` (`checkedPlayerSetups`); until then, for a day at most, the finished check is kept too (`KeptCheck`, forgotten once expired), so reopening AutoHush or closing the window doesn't cost another check. While a check runs, AutoHush leaves its own player as it is: one it paused stays paused until the check ends, never resumed in the check's gaps. The helper's interface is typed once, for AutoHush and the Player Check app alike: its command line, exit statuses and one-line answers in `PlayerCheckKit` (`CommandLineOptions`, `CheckExitStatus`, `NowPlayingListLine` and the other answers, `RunLogName`: Show Log opens only a check's log), and the lines of the report a check is followed by (its panel, its shade, the permission it lacks, the ways it found) as `CheckReportLine`s, which the helper writes and both read (`CheckProgress`); the panel and shade themselves are `CheckPanel`'s. The log and report leave out the account's name and what was playing (`PrivateText`). Its caches and logs go in AutoHush's folders (`~/Library/Caches/com.autohush.AutoHush/PlayerCheck`, `~/Library/Logs/AutoHush/Checks`); in AntiDot mode it taps no sound (`--no-taps`). The app is muted meanwhile by the helper's taps; when it can't be on its own (without Audio Recording, or in AntiDot mode), AutoHush mutes the Mac's output instead (`OutputMute`), unless it's muted already, and any output the sound moves to meanwhile, each put back; an output with no mute control stays audible. Which outputs it muted is kept in the preferences until they're unmuted: at the check's end, as AutoHush quits, or at its next launch, then only if it was muted less than an hour before (`restoreIfLeft`). A change the user makes to the mute during the check drops the record, so the output stays as they set it, and an output that's gone meanwhile (unplugged) keeps its record for the next launch.
   - **The ways.** The ways that worked are offered surest first: its AppleScript (`ScriptedAppPlayer`, as its own dictionary allows), its page's Play/Pause (a `SafariWebAppPlayer` on the app's page, through `PageAccess`), its playback menu (`MenuPlayer` with `MenuPlayerProfile.found`), and last its row in the menu bar's Now Playing panel (`PanelWay`: the panel shows on screen for about half a second and takes the keyboard). The setup keeps only the one the user chose, and a `CheckedPlayer` presses by it alone (a setup kept before that choice may hold several: each press goes to the first, and one that fails hands it to the next). It checks its own presses (`checksItsPresses`): a way that toggles (an AppleScript that only toggles, a row that doesn't follow its app) is checked by the app's state for up to 10 s (`PressCheck(isToggle:)`), never pressed again, which would undo it. It fades only when its way is an AppleScript with a volume, and hears of changes from that AppleScript's notification when it has one, else by reading its state once a second.
   - **Its state** is the surest sign that answers: its AppleScript state, its page's word (while current), its menu's item; then what it reported to Now Playing (`NowPlayingReports`: mediaremoted's lines in macOS's log, the last hour read once, then followed with one `log stream` from the first question on, which stops after a minute without one; only an administrator can read that log, and its wording is macOS's, not an API, so it's only an extra sign); else whether its sound output runs. A Chromium browser's web app plays through its browser, which holds one "Playing audio" assertion per playing page (`PlayingPages`): one more than its other pages' says the web app plays.
   - **The Now Playing panel.** Its icon is found in the windows MenuBarAgent keeps for each menu bar item, else Control Center's (both tried on every macOS), by the item's identifier, `com.apple.menuextra.now-playing` (`AccessibilityNowPlayingPanel`), whatever covers it; else by hit-testing along the menu bar, asking only those two apps, each with its own 0.25 s timeout. Each row's Play/Pause is known by its identifier (`play.fill`, `pause.fill`); on macOS 14, where the panel lists every row's text and buttons in one line, by its description, in any of the languages of Control Center's own `NowPlaying` table (`flatRows`). With Now Playing hidden by the user, it's shown for the moment of a press by writing Control Center's `NowPlaying` preference for this Mac (`NowPlayingSetting`; flag 8 hides it); the user's value is written back after, unless the preference no longer holds what AutoHush wrote (the user changed it meanwhile). The value to put back is kept until then, so a press cut short is put right by AutoHush at its next start, or by the helper as it stops (`restoreIfLeft`). A row that doesn't follow its app (`PlayerSetup.panelRowIsStale`: Qobuz's always shows paused) is pressed as a toggle, judged by the app's sound (`LateHearing`): it's listened to for half a second (`ProcessTapLevelProbe`) just before a pause or a resume, and during the check; in between, its keep-awake assertion tells whether it plays. That needs Audio Recording, so in AntiDot mode such a way can't be chosen, and an app set up so is kept out of it as a mute-only one is (`needsAudioLevels`).
   - **Muted instead of paused.** When no way works, **Mute It Instead** keeps a setup whose only way is `.mute`, a `MutedApp` (a `CheckedPlayer` only presses; both are `AddedAppPlayer`s, made by `CheckedPlayers.player(for:)`): while other apps play, the app is muted with a process tap (`ProcessTapMuter`, as a web app's ad is) and reads as paused, so the rest of AutoHush treats it as any paused player. Whether it plays is its keep-awake assertion once it has held one, else its open output. `MuteState` tells the user's own pause and play from a gap between songs: once the app has stopped for 3 s (`MuteState.stopTime`) and plays again, the mute is lifted and it reads as playing, a resume of the user's, which AutoHush leaves alone until the other apps stop. **Unmute** on the card does the same. After a sleep, the mute is lifted once the app has stopped for 3 s, never while it plays on. Quitting AutoHush lifts it, and AntiDot mode, which taps no sound, lifts it and leaves the app unable to be muted: it's then shown dimmed among the players.
   - **The page's switch.** An Electron, CEF or Flutter app's page, and a Chromium browser's web app's, shows in Accessibility only once its switch for assistive tools is on (Electron's `AXManualAccessibility`, or VoiceOver's `AXEnhancedUserInterface`, set on the browser for a web app). It stays on while the app is the player, and goes back off (`release()`) when another player is chosen or AutoHush quits; a browser's, shared by its web apps, only once none of them uses it (`SharedSwitches`).
   - **Reopening.** Chromium builds no page for a window out of sight, so an Electron app's page takes presses while covered or on another desktop only when the app was opened with `--disable-backgrounding-occluded-windows` (`PlayerSetup.launchOption`). Add an App's Reopen step reopens it so, after asking. Once it's the player, `needsReopen()` reads the running app's arguments; the card then says it needs reopening, and `reopen()` quits it as a person would (15 s, never by force) and opens it again in the background with the option.

**The purple dot:** taps exist only while `PlaybackArbiter` says levels can change a decision (auto-pause on, and the player playing here or paused by us), with a 2 s release delay. A source's process measured silent for 10 s loses its tap and counts as silent (`silentTapRelease`, `quietProcesses`: Qobuz keeps its output open while paused), until its output closes and opens again or it holds a playing assertion; one that holds a playing assertion all along (a call's quiet stretch) keeps its tap. The player itself is never tapped, except to prove the permission works when TCC can't be read, an added app judged by its sound, for half a second just before a pause or a resume, one whose Now Playing report says it isn't playing while its output is open, once per report (`CheckedPlayer.reported`), and, with Level the volume on, while another app is tapped anyway (its loudness before the pause).

**The audio permission:** macOS has no public API for it, and taps without it simply deliver silence. AutoHush reads it through the private `TCCAccessPreflight` / `TCCAccessRequest` (resolved at runtime, in `AutoHushKit/Utilities/PrivateAPI`), re-checks it every 5 s, and falls back to "any open output counts" when it's denied, judging apps as AntiDot mode does, with its waits (3 s for sound without video, 2 s for an app judged by its open output alone). If a future macOS removes those functions, it infers the permission from tapped samples instead.

## Architecture

The words used for the parts below are in the [glossary](GLOSSARY.md).

```text
AppDelegate ── lifecycle, choosing the player, the windows, wiring features to the engine
  ├── AppState ── the one AppStatus: what the menu and the windows show, written by AppDelegate only
  ├── UserSettings ── the user's settings (Auto-Pause and its snooze, the apps, timings, detection),
  │     stored in Preferences
  ├── StatusMenuController ── renders AppStatus into the menu bar item and its panel (MenuPanel)
  ├── SettingsWindowController ── a sidebar of SwiftUI pages backed by SettingsModel, which reads each part
  │     from its owner: AppState, UserSettings, UpdateController and PermissionCenter; Sound Sources'
  │     list is its AppListModel
  ├── UpdateController ── daily and manual checks against the latest GitHub release, then notifying,
  │     downloading (UpdateDownloads) or installing (UpdateInstaller), with notifications (UpdateNotifier);
  │     observable, so Settings follows its settings and status
  ├── PermissionCenter ── reads and asks for the permissions, for the chosen player (keeping its last
  │     read for the windows) and Add an App's app alike
  ├── AddAppFeature ── Add an App…: its model, windows, the check's panel and the Mac's output muted
  │     during a check; what it needs from the rest of AutoHush it asks of AppDelegate (AddAppHost)
  ├── AddWebAppFeature ── Add a Web App…: its model and window, making the web app and choosing it, one
  │     made but not listed yet; as Add an App, through AppDelegate (AddWebAppHost)
  └── PlayerSession ── the chosen player from its start until AutoHush quits: starts it (at launch, by
        │   itself after a failed start, when it opens), checks access again, keeps the held pauses and
        │   the hand-over
        └── MonitoringPipeline ── the engine's front door (AutoHushKit): one per start, started and torn down
                  as a unit; one a new player choice leaves mid-pause runs on in HeldPauses until it resumes
                  its player
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
                                                                      └── MusicPlayer (ScriptablePlayer, VLCPlayer
                                                                            and ScriptedAppPlayer: Apple events;
                                                                            MenuPlayer and SafariWebAppPlayer:
                                                                            Accessibility; CheckedPlayer and
                                                                            MutedApp: an added app, by the way
                                                                            the user chose, or muted)
```

AutoHush is a Swift package of several modules, so the compiler keeps the layers apart:

```text
AutoHush (executable: the entry point only)
  └─ AutoHushApp            the app: menu bar, Settings, updates, diagnostics, wiring
       ├─ AutoHushPlayers   the supported media players
       │    ├─ SpotifySupport, AppleMusicSupport, TidalSupport, PodcastsSupport, VLCSupport, QuickTimeSupport
       │    │                   one <App>Support module per player
       │    ├─ ScriptablePlayers   shared by the players scripted with Apple events
       │    ├─ MenuPlayers         shared by the players controlled through their playback menu
       │    ├─ WebAppPlayers       Safari web apps, controlled through the site's own Play/Pause button
       │    └─ CheckedPlayers      the apps added with Add an App…, controlled the way the user chose
       ├─ CheckedPlayers    also used directly: a check's result
       ├─ PlayerCheckKit    the helper's command line, exit statuses and answers, to run it, and the
       │                    report's lines and the progress they show
       ├─ CheckPanel        a check's panel and shade (Sources/CheckPanel), shown while it runs, and
       │                    the parts both apps draw in it (CheckRequestNote, CheckWindowStepView)
       └─ AutoHushKit       the engine, reached through MonitoringPipeline: no user interface, no specific player
measure-volume-curve (developer tool, in Tools/) → AutoHushPlayers, AutoHushKit
listen-to-fades (developer tool, in Tools/): records a loopback device, measures fades
PlayerCheckApp (Player Check, in Tools/) → PlayerCheckKit, CheckedPlayers, CheckPanel, AutoHushKit: playercheck
                            in a window, run through the same interface, panel and ToolRun as Add an App…
playercheck (AutoHush.app's helper, in Sources/PlayerCheck) → PlayerCheckKit, ScriptablePlayers, MenuPlayers,
                            WebAppPlayers, CheckedPlayers, AutoHushKit: how AutoHush can control an app;
                            Add an App… runs it (and Player Check, in Tools/, shows it in a window)
  └─ PlayerCheckKit         its parts that need no app to check (Sources/PlayerCheck/Kit), so tests reach them,
                            and its interface, which whoever runs it uses too
```

```text
Sources/
  AutoHush/              AutoHushMain (starts AutoHushApp)
  AutoHushApp/            by kind of code first, then by area
    App/                 AutoHushApplication, AppDelegate (wiring; its parts by topic in AppDelegate+Lifecycle,
                         +Player, +WebApps, +Permissions, +Updates, +AddApp (Add an App's host), …),
                         MainMenu (the Mac's standard menu bar, while a window is open)
    Models/              the app-wide state: AppState, which holds AppStatus (what the menu and the windows
                         show, with UpdateOffer), SettingsModel (what only the windows show, and their
                         actions), AppListModel (Sound Sources' list: its rows, order, search, selection
                         and removals; SettingsModel's), StatePresentation (the status's icons and text),
                         AppHealthState, StatusMenuModel (the menu's parts, MenuSection), MenuPlayerList (the menu's
                         players), KeyHighlight (the menu's and Settings' highlight, moved by the arrow
                         keys and the pointer), HighlightKey (the keys it takes, one mapping for both),
                         SettingsKeys (Settings' keys, its sidebar's and page's), AddWebAppModel,
                         PlayerOption (each player and whether it's installed), AppActions (what only
                         AppDelegate does), UpdateCommands (and what Settings reads of the updates),
                         SettingsNavigation (Settings' page), PermissionsState, ChecklistStep (a step of
                         the windows' checklists), DiagnosticsFacts, DiagnosticsSnapshot, AppRelease,
                         UpdateCheckResult, PreparedUpdate, KeptImage, UpdatePrompt, UpdateNotice,
                         LearningNote, LearningPauseMode, MonitoringSettings (what the monitoring follows),
                         LogsModel (the logs window's entries, time range, levels and search), AddAppModel
                         (Add an App's steps, from choosing the app to Use), CheckableApp, CheckPermissions
                         (its app's PermissionsState, as its rows) and CheckPermission (one of them),
                         PlayerCheckEnd (how it ended), KeptCheck (a finished
                         check not used yet), OtherAppProblem (why an app picked from the disk can't be
                         checked), CopiedFeedback (a Copy button's "Copied" for 2 s)
    Services/            what does the work, by area: App/ (WindowWatch, what the open windows show,
                         followed once a second; OtherInstances, quits the copies opened before it;
                         DockPresence, in the Dock while a window is open; MenuBarIconPlace, the icon
                         beside the system's), Playback/ (PlayerSession,
                         the chosen player from its start until AutoHush quits; HeldPauses), Settings/
                         (UserSettings, LaunchAtLoginController, ReopenChoices: the players reopened without
                         asking),
                         Permissions/ (PermissionCenter, for the chosen player and Add an App's app alike;
                         the chosen player's as last read, which the windows show),
                         Updates/ (UpdateController, observable for Settings; UpdateChecker,
                         UpdateInstaller: download, signature check, swap; UpdateDownloads, UpdateNotifier,
                         ReleaseNotes), WebApps/ (LearningSession, learning a web app's controls with the
                         user; AddWebAppHost, what Add a Web App needs from the rest of AutoHush;
                         FolderWatch), Diagnostics/ (DiagnosticsReport, Copy Report's text), Shortcuts/
                         (Shortcuts' actions and their choices, the two App Shortcuts, the Focus filter, and
                         FocusAutoPause, which notes Auto-Pause as a Focus starts and puts it back as it ends;
                         they reach Auto-Pause through AutoPauseControlling, registered at launch by
                         IntentDependencies), AddApp/ (PlayerCheckHelper and PlayerCheckRun: AutoHush's own
                         playercheck, and a check running in it, through CheckRunning; the ports of Add an
                         App's model: AppReading, the apps on the Mac (AppReader reads them live),
                         CheckHelping, the check's helper (PlayerCheckHelper), AddAppHost, what it needs from
                         the rest of AutoHush (AppDelegate), and AddAppPresenting, what it shows through
                         AddAppFeature; CheckableApps: the apps Add an App offers;
                         AppPlaying: whether the chosen app plays, by its level, or by its open output without
                         Audio Recording or in AntiDot mode)
    Controllers/         AppKit's window and menu controllers: StatusMenuController (with +Keys, the
                         keys as in macOS's menus, and +SideWindow, the side window), MenuPanel (the
                         menu's window, and its side window's), SettingsWindowController,
                         PlayerChooserWindowController (the welcome window), AddWebAppFeature (Add a Web
                         App: its model, its window and the add under way), AddWebAppWindowController,
                         LearningWindowController, HostedWindowController (their shared base),
                         LogsWindowController, AddAppFeature (Add an App: its model, its windows, the check's
                         panel and the Mac's output muted during a check), AddAppWindowController,
                         AppChooserWindowController (the apps to choose), CheckWarningWindowController (before
                         a check), CheckPanelController+AddApp (Add an App's view in the check's panel,
                         CheckPanel's)
    Views/               SwiftUI views, by area: Components/ (what several places show, one component and
                         its small parts per file: Font+AutoHush holds the text sizes, AppearanceStyle the
                         colors; ButtonStyles, Highlightable (the menu's and Settings' highlight tint),
                         Card, SectionHeading, SwitchRow, ChoiceChips, BottomBar, MainButton (a window's
                         main button), ChecklistStepRow, PermissionRow, CopyButton, NoteLabel, SearchField,
                         PlayerTiles, …), MenuBar/ (the menu's panel:
                         MenuPanelView; MenuScrollArea, what scrolls and whether more is below; StatusCardView, the
                         card; MenuMediaPlayerView and MenuPlayerListView, the Media Player part and its
                         players; MenuIgnoredAppsView, the Ignored Apps part; MenuSideRow, their rows;
                         MenuPartTitle, a part's title and a title inside it; MenuSidePanelView, the
                         side window they open; MenuActionRow and MenuSwitchRow, its rows that act and
                         those with a switch; MenuLine and MenuRowSymbol, its line between parts and a
                         row's symbol; SourceSwitchRow, an app's switch; SnoozeBarView, Turn
                         off for; PlayingAppsView, Playing Now and Recently Played; MenuSettingsView,
                         the settings; MenuToolbarView, the buttons; MenuSpacing, the space around its
                         parts; MenuRowButtonStyle, MenuContentWidth, and MenuBarIcon, drawn in code),
                         Settings/ (one per page, SettingsPageView, SettingsSidebar), Welcome/, WebApps/
                         (Add a Web App, the learning window and LearningSteps), Logs/ (LogsView),
                         AddApp/ (Add an App's window and its numbered steps, the app chooser, the warning
                         before a check, the check's panel, AddAppText: what they say)
    Utilities/           small helpers: AppVersion, ProjectInfo, AppIcon, InfoAlert, IgnoreAppsPicker
                         (the panel that picks apps to ignore, for Settings and the menu), …
  AutoHushKit/           the engine, by kind of code too
    Models/              values and settings: AutoPauseSetting (the setting and snoozes), PlaybackState,
                         DetectionMethod, DetectionMode, ActiveAudioReport (what Diagnostics shows),
                         AppConfiguration, TimingSettings, AppListOrder, AutomaticUpdates, LogEntry
    Services/            Audio/ (AudioMonitor, SourceActivityTracker, PlaybackSignals: AntiDot mode's judge;
                         ResumeLevel and SystemVolumeLeveler: leveling the music; OutputMute: the Mac's output
                         muted for a check; CoreAudio/: process list, taps, levels, SystemVolume and
                         CoreAudioOutputMute (both find the output sound plays through, and outputs by their
                         lasting IDs, through OutputDevices), CoreAudioProperty: reading and setting properties),
                         Playback/ (MonitoringPipeline: the engine for each start, which the app makes and
                         drives, so AudioMonitor and PlaybackArbiter stay internal; PlaybackArbiter,
                         VolumeFader, PauseHandover, PressCheck),
                         NowPlaying/ (NowPlayingReports: what apps report to Now Playing, from macOS's log,
                         administrators only, an extra sign)
    Players/             MusicPlayer (the interface), MusicPlayerError (why a player couldn't be
                         controlled), MusicPlayerCatalog, PlayerState, VolumeCurve,
                         PolledStateObserver (for players that announce nothing), WebAppMaking (making a
                         web app from an address, and the suggested ones), WebAddress (an address as
                         typed, and whether a page is its site), CountrySites (a service's site by
                         country), PlayerIconPlaceholder (a player's icon while it isn't installed)
    Permissions/         what's needed and where to grant it
    Storage/             Preferences, LogFile (AutoHush's own log, its last 24 hours)
    Utilities/           logging (AutoHushLogger) and small helpers: ToolRun (the one way a command-line
                         tool is run and waited for, with a timeout), DispatchQueue.run (blocking work off
                         Swift's shared threads), Polling (waiting on a thread until something holds, looking
                         every so often); PrivateAPI/ (TCC, ProcessResponsibility,
                         AccessibilityWindows, NowPlayingApp: undocumented macOS functions, resolved at
                         runtime with fallbacks, through PrivateSymbol; check them, and those listed under
                         Where things go, after every major macOS release)
  AutoHushPlayers/       SupportedPlayers (the catalog of supported players)
  PlayersSupport/        ScriptablePlayers and MenuPlayers (shared), SpotifySupport, AppleMusicSupport,
                         TidalSupport, PodcastsSupport, VLCSupport and QuickTimeSupport: each player's
                         profile or controller, and its placeholder icon; WebAppPlayers: Safari web apps
                         (finding them, learning their button, controlling them; with PageAccess, another
                         app's page too: Electron, CEF, Flutter and Chromium web apps, once their switch
                         for assistive tools is on, SharedSwitches keeping one switch for the pages that
                         share it; PlayingPages: a Chromium browser's playing pages). For an app without a module of
                         its own: ScriptingDictionary, ScriptSetup and ScriptedAppPlayer (an app controlled as
                         its own dictionary allows, documents too), MenuPlayerProfile.found with
                         PlayPauseWords.found (any app's menu and words); and CheckedPlayers: PlayerSetup
                         (the way the user chose, kept), CheckedPlayer (pressing by it, and checking its
                         presses), MutedApp (muted instead of paused), LateState and LateHearing (a
                         toggle's state, and a stale row's sound), MuteState, and the Now Playing panel
                         (NowPlayingPanel, AccessibilityNowPlayingPanel, PanelRows, PanelWay: the last way,
                         its row told by the clues its check found, PanelClues; NowPlayingSetting: showing it
                         for a press while hidden)
  CheckPanel/            CheckPanelController: a check's progress at the bottom right of every desktop, and the
                         screen's shade, for Add an App… and Player Check (each shows its own view in it)
  PlayerCheck/           playercheck: how AutoHush can control an app. build-app.sh puts it in the app, as
                         Contents/Helpers/playercheck, where Add an App… runs it (its own process: a check that
                         ends or stops takes its block on the mouse and keyboard with it); --result writes what
                         it found (CheckResult), --partial goes on without Audio Recording or Automation,
                         --logs and --caches put its logs and caches in AutoHush's folders, --no-taps taps no
                         sound (AntiDot mode); Kit/ is PlayerCheckKit, with the flags, exit statuses and
                         answers whoever runs it uses, and CheckReportLine (the report's lines AutoHush and
                         Player Check follow) and CheckProgress (how far a check has got, read from them)
Tests/                   a test module per module, mirroring its folders, plus AutoHushTestSupport (shared
                         fakes, a value behind a lock, a gate, a sleep the test ends) and PlayersTestSupport
                         (the players' stores and a scripted app's Apple events, in memory); PlayerCheckTests
                         runs the helper itself as a read-only check of Calculator;
                         only the players' code names a player (AutoHushPlayersTests checks the engine
                         and the helper, comments included), but any test may use real apps (VLC,
                         Spotify…) as test data
Tools/                   tools for measuring the fades and checking apps, never part of the app or its disk
                         image; each has a README.md saying what it does and how (Tools/README.md lists them)
  MeasureVolumeCurve/    measures a player's volume curve
  ListenToFades/         records a loopback device and measures the fades in it
  LoopbackDriver/        AutoHush Loopback, a test-only virtual audio device, with build, install and
                         uninstall scripts
  PlayerCheckApp/        Player Check, Sources/PlayerCheck in a window, with Play and Pause for the apps it
                         can control: the package's PlayerCheckApp product, made into an app by its build.sh
Resources/               Info.plist, entitlements, AutoHush.icon (the app icon), and Localization/ with the
                         String Catalogs, assembled into the .app by Scripts/build-app.sh
```

**Where things go:**

- **`AutoHushKit`** has no user interface (no windows or views; AppKit only for `NSRunningApplication`, the shared `running(_:)` helper) and knows no player by name; the app tells it which player was chosen. It can't import the app or a player module, and the compiler enforces that. The app reaches its monitoring only through `MonitoringPipeline`; `AudioMonitor` and `PlaybackArbiter` are internal to it.
- **`AutoHushApp`** is sorted by kind of code first, then by area: `App/` starts things and wires them together; `Models/` holds the app-wide state (`AppState`, holding the `AppStatus` that the menu and the windows show; `SettingsModel` for what only the windows show); `Services/` does the work; `Controllers/` are AppKit's window and menu controllers; `Views/` are SwiftUI's, with what several places show in `Views/Components/`; `Utilities/` are small helpers. A file holds one kind of code and is named after its main type; a large type is split by topic into `Type+Topic.swift` files beside it (`PlaybackArbiter+Pausing.swift`, `AppDelegate+Player.swift`).
- **A player module** (`<App>Support`, in `PlayersSupport/`) holds everything specific to one media app. Apps scripted with Apple events share `ScriptablePlayers`, so their module is just a `ScriptablePlayerProfile`; apps controlled through their playback menu share `MenuPlayers`, so theirs is a `MenuPlayerProfile` and a way to read their words for Play and Pause.
- **`Utilities/PrivateAPI/`** (in the engine) holds the undocumented macOS functions AutoHush calls. The only other undocumented parts of macOS it relies on: Control Center's `NowPlaying` preference and its flags (`NowPlayingSetting`, written), MenuBarAgent's windows for each menu bar item and `com.apple.menuextra.now-playing` (`AccessibilityNowPlayingPanel`), and the helper's SkyLight calls (`Desktops`) and `_AXUIElementGetWindow` (`WindowStates`). It also relies on one deprecated call, `NSApplication.activate(ignoringOtherApps:)` (deprecated since macOS 14): `becomeActive()` uses it to bring a window opened from the menu's panel forward, since macOS ignores `activate()` from a menu bar app that isn't active. Check all of them after every major macOS release.
- **Text people read** lives in the app, never in the engine: mostly in `Models/StatePresentation.swift`, while Diagnostics gets plain facts from the engine (`ActiveAudioReport`) and words them. Write it as `String(localized:)` or a SwiftUI text, with a `comment:` for translators when the context isn't obvious (see [Translations](#translations)). Logs stay in English.
- **Logging** goes through `AutoHushLogger` (`AutoHushLogger(category:)`, then `.info`, `.notice`, `.error` or `.debug`), written as with macOS's `Logger`: a value shows only when marked `privacy: .public` (numbers and Booleans unless marked `.private`), otherwise it reads `<private>`. Lines are in English and never translated: interpolate an error as `\(error)`, never its `localizedDescription` (in the user's language), and it's said in English (`LoggableError` for AutoHush's own errors; macOS's by domain and code). Every line but debug ones goes to AutoHush's own log, `~/Library/Logs/AutoHush/AutoHush.log` (`LogFile`: the last 24 hours, 4 MB at most), which Settings → Diagnostics → Show Logs… shows; macOS's log gets every line at the debug level only, so it keeps none: watch them live with `log stream --level debug --predicate 'subsystem == "com.autohush.AutoHush"'`.
- **Access:** types used across modules are marked `package`, visible inside AutoHush but to nothing outside it.

**Adding a media player:** most apps need no code. **Add an App…** checks the app with AutoHush's helper, [playercheck](Sources/PlayerCheck): it reads its scripting dictionary, playback menu, page and Now Playing panel row, tries pausing and playing it by each with its window in each state, and writes what worked (`CheckResult`). The user chooses one way, AutoHush keeps it as a `PlayerSetup` (`CheckedPlayers.keep`), and a `CheckedPlayer` controls the app by it. A module of its own is for a popular player that needs fades, its own words or quirks: check it first with the same [PlayerCheck](Sources/PlayerCheck) (or [Player Check](Tools/PlayerCheckApp), in a window), which says which kind of player it would be. The app and the engine only talk to players through the `MusicPlayer` protocol: its bundle ID and name, a permission check, its live state, `pause()` / `play()`, its volume (for fades; `nil` if it has none) and how that volume maps to loudness (`VolumeCurve`; linear if not given), and a `PlayerStateObserving` that reports state changes. A new player is:

1. a new module, `Sources/PlayersSupport/<App>Support/`, and its tests in `Tests/PlayersSupport/<App>SupportTests/` (both need a `path:` in `Package.swift`). If the app is scripted like Spotify and Music, the module is a `ScriptablePlayerProfile`: its bundle ID and name, the suite code of its pause and play commands (from the `.sdef` in its bundle), its state notification, and any quirk, such as Spotify's volume reading one less than it was set to. If it can't be scripted but has a playback menu with Play/Pause first and ⌘← and ⌘→ items, as TIDAL and Podcasts do, it's a `MenuPlayerProfile`: its bundle ID, name, menu name and how to read its own words for Play and Pause from its bundle. If its AppleScript is one an added app could have (QuickTime Player's acts on its documents), it's a `ScriptedAppPlayer` with a fixed `ScriptSetup`, as `QuickTime.player()` is. Otherwise it's a type implementing `MusicPlayer`, as `VLCPlayer` does;
2. an entry in `SupportedPlayers.catalog` (and a dependency of `AutoHushPlayers` in `Package.swift`), so it's offered in the menu, Settings and the welcome window;
3. its placeholder icon, a `PlayerIconPlaceholder` in its module (as `SpotifyIcon.swift`): its tile's colors and its mark drawn as a path on a 1000-point tile, shown while the app isn't installed. The catalog's tests check that every player has one;
4. its volume curve: linear until it's measured. The maintainer measures it before the player ships;
5. its name in the bug report form's player list (`.github/ISSUE_TEMPLATE/bug.yml`) and in the player request form's list of supported players (`player.yml`'s intro).

A website needs none of this: added to the Dock from Safari, it's offered as a player, and AutoHush learns its Play/Pause button. `MusicPlayerCatalog` takes such players besides the built-in ones (`found`) and the sites it suggests adding (`suggested`); a player that has to learn implements `LearningMusicPlayer`, whose status the app shows, and one that may mute itself implements `MutingMusicPlayer`. Once a website has been tested live, add it to `SupportedPlayers.testedWebApps`: its web app is then offered first and suggested until added, instead of being marked untested.

Defaults that aren't in Settings, such as tick rates, the gap tolerance and the excluded system processes, live in [`AppConfiguration.swift`](Sources/AutoHushKit/Models/AppConfiguration.swift). Any non-empty bundle ID that isn't excluded counts as a media app.

## Build and test

Developing AutoHush needs Xcode 27 or later, which runs on macOS 26.6 or later (the package's Swift tools are 6.4); AutoHush itself runs on macOS 14.4 and later. Any warning fails a build (`Package.swift`).

```bash
swift build      # build every module and the tools
swift test       # run the tests of every module
AUTOHUSH_QUICK_TESTS=1 swift test   # the same without the slow ones (real disk images)
AUTOHUSH_TEST_WAIT=90 swift test    # on a slow machine: each wait 90 s instead of 30 s (CI sets it)
bash Scripts/build-app.sh release   # build and sign AutoHush.app
```

The tests use mock CoreAudio, level meter, power assertion and player implementations, so they never create real taps, script a real player or trigger permission prompts. A suite's tests run at once unless it says why they can't (`.serialized`), and a suite whose tests wait at a gate has a time limit, as long as two waits, so a change that breaks one fails instead of hanging.

The package builds in Swift 6's language mode with five of Swift 7's rules on ahead of it (`Package.swift`): an async function that isn't isolated runs on its caller's actor, the main actor when the app calls it; a main-actor type's conformances are main-actor ones; a `weak` capture can't be reassigned; a protocol used as a type is written `any P`; and a file sees only the members of the modules it imports itself. So work that blocks (Accessibility, Apple events, Core Audio, the disk) goes through a queue of its own (`DispatchQueue.run`), the players are actors, and `@concurrent` marks only a function that blocks between its awaits (making a web app, preparing an update, listing the apps to check) or one a framework calls through Objective-C.

The app icon is `Resources/AutoHush.icon`, an Icon Composer document (Icon Composer comes with Xcode): one layer, `Assets/bars.svg`, on a background that changes with the light and dark appearance. `build-app.sh` compiles it with Xcode's `actool`; without Xcode the app builds with the generic icon. To preview a change without building, use Icon Composer's `ictool` (`Icon Composer.app/Contents/Executables/ictool AutoHush.icon --export-image …`).

`build-app.sh` also builds `playercheck`, the helper Add an App… runs, and puts it in `Contents/Helpers`, signed like the app (its entitlements, the identifier `com.autohush.AutoHush.playercheck`) before the app is signed around it. macOS counts what the helper does as AutoHush's, so its checks use AutoHush's permissions.

Shortcuts and System Settings' Focus filters find AutoHush's actions, App Shortcuts and Focus filter in `Contents/Resources/Metadata.appintents`, which Xcode writes and SwiftPM doesn't. So `build-app.sh`, after `swift build` and before signing, runs Xcode's `appintentsmetadataprocessor` on AutoHushApp: it reads them from the module's sources and the constant values the compiler recorded for them, so their texts must be literals, and lists the actions' summaries for the String Catalog. With Xcode, a build that writes no metadata fails; without it, the app builds without the actions, with a warning. macOS indexes the actions once the app has run, and runs them only for an app signed by a developer team (see [Signing and releases](#signing-and-releases)).

## Style guide

[STYLE_GUIDE.md](STYLE_GUIDE.md) describes how AutoHush looks and reads: its layout, text sizes, colors and shared components, how to write its text, and how to check a visible change. Follow it, and update it when a change adds a new pattern. It's the one place that describes the menu's and the windows' layout part by part: the code and the other docs point to it rather than draw it again.

## Translations

English is the source language and the fallback; [Language](README.md#language) lists the translations and how macOS picks one. They are every language macOS itself is translated into. Norwegian is `nb` (Bokmål), which macOS also offers to Nynorsk users. Four languages come in variants, and macOS picks the closest one for each country:

| Language | Variants |
|---|---|
| Spanish | `es` Spain · `es-419` Latin America (Mexico, Argentina, US Spanish…) |
| French | `fr` France (also Belgium and Switzerland) · `fr-CA` Canada, with Quebec's punctuation: no space before `;` `?` `!` |
| Portuguese | `pt` Brazil · `pt-PT` Portugal (also Angola and Mozambique) |
| Chinese | `zh-Hans` Simplified (mainland China, Singapore) · `zh-Hant` Traditional (Taiwan) · `zh-HK` Traditional for Hong Kong (also Macau and Cantonese) |

A variant must translate every string: a missing one shows in English, not in the other variant.

- **Where the text lives:** in `Resources/Localization/`. `Localizable.xcstrings` is a String Catalog with all of the app's text, keyed by the English text; `InfoPlist.xcstrings` has the permission prompts and the copyright line from `Info.plist`; `AppShortcuts.xcstrings` has the App Shortcuts' phrases, with `${applicationName}` where the app's name goes. The three names are fixed: `Localizable` is the table macOS reads by default, macOS translates `Info.plist` only from `InfoPlist`, and App Shortcuts' phrases only from `AppShortcuts`.
- **New text** needs no extra step: write it as `String(localized: "…", comment: "…")` or as a SwiftUI text. `build-app.sh` adds new strings to `Localizable.xcstrings` (the Shortcuts actions' summaries from the App Intents step) and marks those no longer used as stale, as Xcode does, then compiles each catalog into the app, one folder per language. Delete stale strings once you're sure they're gone for good: they are still translated and shipped. An App Shortcut's phrase is the exception: add it to `AppShortcuts.xcstrings` yourself.
- **Adding a language:** open the three catalogs in Xcode, add the language and translate (or edit the JSON), then build. Use the words macOS itself uses in that language (Ajustes, Einstellungen, Réglages…) and its typography (French spaces before `:` and `?`), and keep each `comment` in mind: it says where the text appears. Text not translated yet shows in English. The tests check that every translation keeps its placeholders (`%@`, `%lld`), that every App Shortcut phrase keeps `${applicationName}` (Siri runs a phrase only when it names the app), and that `InfoPlist.xcstrings` matches `Info.plist`.
- **Trying a language:** quit AutoHush, then start it with `AutoHush.app/Contents/MacOS/AutoHush -AppleLanguages '(es)'`.
- **Not translated:** logs, the measuring tools and the disk image's background stay in English.

## Contributing

Contributions are welcome. The repository has two branches:

- **`main`** holds the latest release. It only moves when a new version is published.
- **`dev`** is where development happens. Every change goes there first, from a branch of its own named as [Conventional Branch](https://conventionalbranch.org/) asks: `feature/…`, `fix/…` or `chore/…`, and the maintainer's `release/v<version>` (a release being prepared) and `hotfix/…` (an urgent fix to the latest release).

To propose a change, fork the repository and create a branch from `dev` named **`feature/…`** for something new or changed, **`fix/…`** for a bug fix, or **`chore/…`** for docs, translations, tests or tooling (for example `fix/vlc-resume` or `feature/qobuz`), in lowercase words joined by hyphens. Then open a pull request into **`dev`**, not `main`. I review every pull request before approving and merging it, and it reaches `main` with the next release. Before you open it, check that it builds and its tests pass (see [Build and test](#build-and-test)) and that it follows the [style guide](STYLE_GUIDE.md). A check on every pull request flags one whose branch name or target doesn't follow this, and another builds it and runs the tests (on each push to `dev` and to those branches too); [CONTRIBUTING.md](CONTRIBUTING.md) has it all in one place.

To report a problem or suggest something, [open an issue](https://github.com/hfustercabre/AutoHush/issues/new/choose): there's a form for a bug (with Diagnostics' report, from **Settings → Diagnostics → Copy Report**, and the logs, from **Show Logs…** beside it), a feature, a player you'd like AutoHush to support (when **Add an App…** found no way, with its check's log) and a translation fix. A security problem goes privately, as [SECURITY.md](SECURITY.md) says. Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).

## Signing and releases

macOS remembers permissions per signing certificate. An unsigned ("ad hoc") build looks like a new app every time, and users would have to grant everything again. So AutoHush is signed with a stable certificate and the hardened runtime.

Releases are signed with the maintainer's Apple Development certificate, under a designated requirement that names the app's bundle ID and the certificate's team, not the certificate itself. A renewed certificate has the same team, so macOS keeps the permissions and installed copies keep updating. The scripts add this requirement to any Apple identity, reading the team from its certificate.

Your own build doesn't need that certificate. A self-signed or ad hoc build works the same, except that Shortcuts actions don't run: macOS runs them only for an app signed with a team. The self-signed certificate below keeps your permissions across your own rebuilds.

**One-time setup** (a self-signed certificate for your builds):

```bash
bash Scripts/create-signing-certificate.sh
```

This creates the certificate (valid 10 years) in your login keychain. The first build asks to let `codesign` use the key: choose **Always Allow**. Then **back it up**: in Keychain Access, open **login → My Certificates**, right-click "AutoHush Self-Signed", choose **Export…** and save a password-protected `.p12`. If you lose it, a build signed with a new certificate counts as another app: macOS asks for the permissions again.

| Script | What it does |
|---|---|
| `Scripts/create-signing-certificate.sh` | Creates the self-signed certificate (once) |
| `Scripts/build-app.sh [release\|debug]` | Builds and signs `AutoHush.app` (`VERSION` / `BUILD_NUMBER` override the bundle version). A release is stripped of its local symbols (less than half the size); each build's dSYMs, for reading crash logs, are kept in `dist/dSYMs/<version>-<build>-<UUID>/`, which stays local |
| `Scripts/build-dmg.sh [version]` | Packages `dist/AutoHush-<version>.dmg`: a drag-to-Applications window in AutoHush's colours, with a first-launch note, drawn by `Scripts/lib/dmg-background.swift` and laid out by [dmgbuild](https://github.com/dmgbuild/dmgbuild) (`Scripts/lib/dmg-settings.py`), without Finder. dmgbuild is installed on first use into `.build/`, pinned and hash-checked (`Scripts/lib/dmgbuild-requirements.txt`); it needs Python 3.10 or later (`PYTHON` picks one) |
| `Scripts/release.sh <version>` | Prepares a release: a signed build and DMG, then version and changelog (a failed build changes neither), and release notes. It runs no tests (run the whole suite first), refuses any build not signed with AutoHush's developer team (another team, self-signed or ad hoc) and never commits, tags or publishes |
| `Scripts/update-tap.sh <version>` | Points the Homebrew tap at a published release: checks that the DMG on GitHub is the one in `dist/`, then commits the new version and checksum to the tap's cask and pushes it |

The signing identity is `SIGNING_IDENTITY` if set (`-` means ad hoc), otherwise an "Apple Development" identity in the keychain (AutoHush's team's if there is one; of several, the one valid longest), otherwise "AutoHush Self-Signed" if it exists, otherwise ad hoc. `SIGNING_KEYCHAIN` points to another keychain (for example on CI). Ad-hoc builds reset AutoHush's permissions so macOS asks again; `KEEP_PERMISSIONS=1` skips that.

**Publishing a release:** a release is prepared on a branch `release/v<version>` made from `dev`; an urgent fix to the latest release, on a `hotfix/…` branch made from `main`. Once the whole suite passes there (`swift test`, the slow tests too), run `bash Scripts/release.sh <version>` and follow the steps it prints: commit `Resources/Info.plist` and `CHANGELOG.md` and tag `v<version>` on that branch, move `main` to that commit and `dev` too (fast-forwards; a hotfix is merged into `dev` instead), push both and the tag, create the GitHub release titled `v<version>` with the DMG and the generated notes, then run `bash Scripts/update-tap.sh <version>` for Homebrew. Installed copies find the release at their next daily check: they compare its tag with their own version and install `AutoHush-<version>.dmg`. So the tag must match the app's version, and the DMG must keep its name and be signed with the same team.

The Mac App Store and Homebrew's official cask repository aren't options: both require Apple notarization, and the App Store would also reject the private functions AutoHush relies on.
