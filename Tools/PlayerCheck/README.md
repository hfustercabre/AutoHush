# PlayerCheck

Says whether AutoHush could control an app (pause it while another app
plays, then play it again), and which kind of player it would be, so it
could be added as the README's [Adding a media player](../../README.md#architecture)
says. It reads the app's scripting dictionary, its playback menu, where its
sound comes from, whether it's Now Playing and the Play/Pause button of its
page: a web page in its windows (a Safari web app's, or any app's), an
Electron or Chromium Embedded Framework app's (Deezer and TIDAL; Spotify),
or a Flutter app's interface (Spotube). Then it
tests each way to control it, pausing the app and playing it again by each
(asking you to start it first if it isn't playing), with the app's window
in each state a player's window can be in while AutoHush controls it:
visible, covered, on another desktop, covered there, full screen,
minimised and hidden. It ends with a checklist of what worked, and in
which states. It can also just play or pause the app. [Player Check](../PlayerCheckApp) does all of this from a
window.

It's a target of AutoHush's package and runs AutoHush's own code wherever
the two do the same thing, so what it finds holds for AutoHush. That code covers:
- Apple events (`ScriptablePlayer`, `AppleEventChannel`, `AutomationPermission`);
- VLC's states (`VLCPlayer`);
- menus and their words (`AccessibilityPlaybackMenu`, `MenuPlayer`, `PlayPauseWords`);
- learning a page's Play/Pause (`PlayPauseLearner`, `PlayPauseRecipe`, `AccessibilityWebPage`);
- sound (`OwnedAudioProcesses`, `ProcessTapLevelProbe`, `IOKitPowerAssertionReader`);
- windows on other desktops (`AccessibilityWindows`);
- Now Playing (`NowPlayingApp`).

What AutoHush doesn't do yet stays PlayerCheck's own:
- documents (QuickTime);
- menus on other arrows;
- Electron, CEF, Flutter and Tauri pages;
- what apps report to Now Playing;
- the Now Playing panel.

## Use

```bash
swift build -c release --product playercheck   # from the repository; writes .build/release/playercheck
cd .build/release
./playercheck Spotify                    # by name, bundle ID or path: checks it and tests each way
./playercheck Spotify --read-only        # checks it without pressing anything
./playercheck Spotify --pause            # just pauses it (--play: plays it), by the first way that works
./playercheck Deezer --play --via page   # by that way only: script, menu, page or panel
./playercheck --now-playing-list         # the apps macOS keeps in Now Playing now
./playercheck --now-playing-list --since 1760180000   # only what changed since then (apps gone: Removed)
./playercheck --now-playing-reasons /Applications/Spotify.app   # why each app can be in Now Playing, its framework and switches (Player Check's list)
./playercheck --launch-option Deezer     # the launch option it needs (Electron's apps) and whether it runs with it
./playercheck --relaunch Deezer          # quits it, then opens it again with that option, in the background
./playercheck --window-state Deezer      # the state its window is in now: visible, covered, on another desktop, …
```

The options may come before or after the app's name (`--via page Deezer`
is a way and an app). Or `swift run playercheck Spotify`. Whatever runs it
(Terminal, say) needs:
- **Accessibility**, for the menu and page checks, and to put the app's
  window in each state (the pointer and keyboard events for the desktops).
- **Automation**, which macOS asks for once per app before the first Apple
  event, as AutoHush asks when a player is chosen.
- **System Audio Recording**, asked at the first check to measure how loud the
  app is, as AutoHush does; macOS shows its recording indicator while it
  listens. Without it, sound is judged by what the app tells macOS and its
  open output.

The app must be running for everything but its scripting dictionary, and
nothing it does launches an app.

Each check or press is also logged, in a file of its own in
`~/Library/Logs/PlayerCheck/` named by its time, the app and what it did
("2026-10-11 21.46.20.016 Deezer read-only.log"; "… Deezer pause via
page.log"): the arguments, then every line with its time, including what a
press does quietly, and "(ended)" or "(stopped)". The last 50 are kept, so
a run that went wrong can be read afterwards (Console opens them too).
`--now-playing-list` and `--now-playing-reasons` aren't logged.

Example, Spotify (macOS 27, 2026-10-12; the window states and the
results are from a later run, with Spotify playing at the start):

```
Spotify 1.3.4.258 (com.spotify.client)
Scripting dictionary
  commands: pause (spfyPaus), playpause (spfyPlPs), play (spfyPlay)
  player state (pPlS): yes, values stopped/playing/paused: yes
  sound volume (pVol): yes, so it can fade
  pause and play share suite 'spfy'
Playback menu
  'Playback': first item 'Pause', enabled
  its own words for Play and Pause weren't found in its bundle: its item is read with this tool's list
Sound and Now Playing
  sound output running now: Spotify (com.spotify.client, pid 401)
  its level: measured as AutoHush measures it (process taps; macOS shows its recording indicator meanwhile)
  heard now: yes
  keeps the Mac awake: 'Video Wake Lock' (display only)
  Now Playing: this app (until another app reports playing)
Window states
  each way is tested with its window in each state: visible, covered, on another desktop, covered on another desktop, full screen, minimised, hidden; it's put back as it is now: visible
  visible now: its page is read in view, and the test starts there
Page buttons
  built with Chromium (CEF): its page shows once a switch for assistive tools is on (Electron's switch, else VoiceOver's switch)
  Electron's switch (AXManualAccessibility): not taken
  VoiceOver's switch on: its page showed 167 buttons after 0.4 s (one read, as AutoHush reads a web app: 35 ms)
  Play/Pause: 'Pause', 56 pt from the window's bottom, with a player's slider around it
Press test
  State 1 of 7: visible
  Automation for Spotify: allowed
  by script (pause, play): before, menu 'Pause', state playing, page 'Pause', sound on, heard
    after the pause: menu 'Play', state paused, page 'Pause', sound on → it paused
    announced: paused (com.spotify.client.PlaybackStateChanged)
    volume ('sound volume'): 100; set to 99, it reads 98: reads 1 less than set (as Spotify, one less): the profile needs readVolume; put back to 100
    learned its page's Play/Pause, as AutoHush learns a web app's: 'Pause' while it plays, 'Play' while paused, 56 pt from the window's bottom (the button this tool found)
    after playing again: menu 'Pause', state playing, page 'Play', sound on → it plays
    announced: playing (com.spotify.client.PlaybackStateChanged)
  by its menu: …
  by its page's learned button: …
  by the Now Playing panel: …
  State 2 of 7: covered
  …
  State 7 of 7: hidden
  …
  its window put back as it was (visible)
  notification: com.spotify.client.PlaybackStateChanged [… Player State …]

Ways to control it
  ✓ AppleScript: 'pause' and 'play' paused and played it, as Spotify and Apple Music (all 7 window states)
  ✓ Playback menu 'Playback': pressing it paused and played it (all 7 window states)
  ⚠ Page button, with VoiceOver's switch on: 'Pause' / 'Play', learned as AutoHush learns it: pressing it paused and played it, in 2 of 7 window states
      ✗ on another desktop: its page didn't show with VoiceOver's switch on
      ✗ covered on another desktop: its page didn't show with VoiceOver's switch on
      ✗ full screen: its page didn't show with VoiceOver's switch on
      ✗ minimised: its page didn't show with VoiceOver's switch on
      ✗ hidden: its page didn't show with VoiceOver's switch on
  ✓ Now Playing panel: pressing its row ('I Worry Too Much, Egotist – I Worry Too Much') paused and played it (all 7 window states)

Verdict
  Scriptable, like Spotify and Apple Music: a ScriptablePlayerProfile with suite fourCharCode("spfy").
  It has a volume: measure its curve (swift run measure-volume-curve com.spotify.client).
  State notification: com.spotify.client.PlaybackStateChanged, which announced each pause and play (the profile's stateNotification).
  With VoiceOver's switch on, its page's Play/Pause works: it could be a player that learns that button, …
  It works with its window visible, covered; not on another desktop, covered on another desktop, full screen, minimised, hidden.

(VoiceOver's switch set back to off, as it was.)
```

The page's word may lag the state by a moment (above: 'Pause' just after the
pause), so a sure sign judges each test. With Spotify's window on another
desktop, its page's word lags a whole state, and the lines say so:
`page 'Pause' (out of sight: its word lags)`, and "its page's Play/Pause not
learned: its window is out of sight, …".

Deezer's app (7.1.340, Electron 38.4.0), opened as usual, while it plays
(2026-10-12; the trials' lines left out):

```
Window states
  each way is tested with its window in each state: visible, covered, on another desktop, covered on another desktop, full screen, minimised, hidden; it's put back as it is now: visible
  visible now: its page is read in view, and the test starts there

Page buttons
  built with Electron 38.4.0: its page shows once a switch for assistive tools is on (Electron's switch)
  opened with --disable-backgrounding-occluded-windows: no: its page takes no presses while its window is covered or on another desktop (the Player Check app can relaunch it with it)
  Electron's switch on: its page showed 118 buttons after 2.3 s (one read, as AutoHush reads a web app: 25 ms)
  Play/Pause: 'Pause', 51 pt from the window's bottom, with a player's slider around it

Press test
  State 1 of 7: visible
  …
  State 7 of 7: hidden
  …
  its window put back as it was (visible)

Ways to control it
  ✗ AppleScript: no scripting dictionary
  ✗ Playback menu 'Play' (found by ⇧← ⇧→, not ⌘← ⌘→): pressing it changed nothing (in every window state tested)
  ⚠ Page button, with Electron's switch on: 'Pause' / 'Play', learned as AutoHush learns it: pressing it paused and played it, in 1 of 7 window states
      ✗ covered: Chromium neither builds nor presses a page whose window is fully out of view; Deezer wasn't opened with --disable-backgrounding-occluded-windows
      ✗ on another desktop: (the same)
      ✗ covered on another desktop: (the same)
      ✗ full screen: (the same)
      ✗ minimised: pressing it changed nothing
      ✗ hidden: pressing it changed nothing
  ✓ Now Playing panel: pressing its row ('Don't Stop Me Now, Queen – Jazz') paused and played it (all 7 window states)

Verdict
  Its menu has Play/Pause, but pressing it didn't take (as Deezer's menu): not controllable that way.
  With Electron's switch on, its page's Play/Pause works: it could be a player that learns that button,
  as Safari web apps (WebAppPlayers), with no fades; AutoHush has no such player for apps yet.
  It works with its window visible; not covered, on another desktop, covered on another desktop, full screen, minimised, hidden.
  Opened with --disable-backgrounding-occluded-windows, Chromium keeps its page taking presses while its window is covered
  or on another desktop: relaunch it with it (the Player Check app's Relaunch) and check again.
```

Relaunched with the option (`--relaunch Deezer`), the page passed 5 of 7
states: all but minimised and hidden. SoundCloud's Safari web app (a WebKit
page) passed all 7 by its page and by the panel.

Checked on macOS 27 (2026-10-11) against the players AutoHush supports:
Spotify (`spfy`) and Apple Music (`hook`) come out as scriptable, TIDAL and
Apple Podcasts as menu players, VLC as a menu player whose scripting
doesn't fit, YouTube Music and SoundCloud as web apps, Safari and TextEdit
as neither.

## What it checks

Everything is read from outside the app, as AutoHush itself would:

- **Scripting:** the `.sdef` file the app's Info.plist names, else one in
  its resources, read as it is; else `/usr/bin/sdef` prints the dictionary
  (from an aete, or the old `.scriptSuite` files, VLC's), but only while the
  app runs, since `sdef` opens an app to ask it. The app is asked its state, the name of its
  current track (or VLC's `name of current item`) and its commands by Apple events, built and sent as AutoHush
  builds and sends them (`ScriptablePlayer`'s events): to the running
  process (an event can never launch the app), waiting 5 s for the reply,
  once macOS allows Automation (asked before the first event; an answer
  other than allowed or denied, as from an app still starting, is asked
  again before the next); errors are worded as AutoHush words them, with
  the app's own message. Its `player state` is read as AutoHush reads it,
  so Music's fast forwarding and rewinding count as playing. AutoHush's
  `ScriptablePlayers` need pause and play in the app's own suite
  (`<suite>Paus`, `<suite>Play`), the `player state` property (`pPlS`) with
  stopped, playing and paused (`kPSS`, `kPSP`, `kPSp`), and `sound volume`
  (`pVol`) for fades, all read from the application's own properties. An
  app whose application has a true/false `playing` property instead (VLC's)
  has its state read from that. One whose play and pause act on a document
  (QuickTime Player's: "pause document 1"), each with its own `playing`, is
  read and controlled through its documents: it plays while one does, a
  pause pauses every one playing, a play plays those the test paused, else
  the front one (a press). Asked of the app, its `playing` doesn't exist
  (-1728), and play or pause with no document fails (-1701). With
  `playing` false, VLC's `current time` tells stopped (-1: no item) from
  paused, as AutoHush's VLCPlayer tells them. Its **state notification** is
  followed as AutoHush follows a scriptable player's:
  - the usual names (`<bundle ID>.PlaybackStateChanged`, `.playerInfo`, …) are listened to, and their "Player State" read;
  - each test says what they announced after the pause and after the play (Music posts each change twice, the state before, then the new one);
  - the verdict names the one that announced both, the profile's `stateNotification`;
  - a press confirms by it as soon as it comes.

  Its **volume** is checked as fades need it, once, while the first test has
  the app paused (silent): its `sound volume`, else its `audio volume`
  (VLC's, 0–512), set one step away, read back, then put back, however the
  change went (one refused or not read back may still have taken). It
  reports whether it reads back as set, or reads another number (Spotify
  reads one less, so its profile needs `readVolume`). It waits a moment
  between changes, since Music drops a change that follows another at once.
- **Playback menu:** through Accessibility, the menu whose items include ⌘←
  and ⌘→ (items that say ⌘ alone: one that gives no modifiers counts here,
  but AutoHush wouldn't find it, and the tool says so), with Play/Pause
  first, as `AccessibilityPlaybackMenu` finds it whatever the app's
  language; such a menu is read and pressed through
  `AccessibilityPlaybackMenu` itself (0.5 s to answer). Its item tells the
  state as AutoHush's `MenuPlayer` reads it: disabled, stopped (nothing to
  play); else by the app's own words for Play and Pause, read from its
  bundle as AutoHush's menu players read theirs:
  - the texts of its translation tables whose English is "Play" or "Pause" (a `.loctable`, as Podcasts'; `*.lproj/*.strings`, as Music's);
  - in an Electron app's `app.asar`, every text of the keys whose text is "Play" or "Pause" (as TIDAL's "t-play").

  They're kept per copy and version in
  `~/Library/Caches/PlayerCheck/words.json`, and the tool's own list is
  used when none are found. Failing that, a menu whose first item is on
  Space and that has ← and → under other modifiers: Deezer's Play menu
  (Space, ⇧← ⇧→), which AutoHush wouldn't find as it is, and the tool says
  so. (Every arrow shortcut of a menu counts: TIDAL has ⌘← for Previous and
  ⇧⌘← for Seek back.)
- **Sound:** Core Audio's process objects with output running that the app
  owns, as AutoHush finds a player's (`OwnedAudioProcesses`: the app, or a
  process it's responsible for, so WebKit's media process counts for a web
  app). Its **level**, through process taps, as AutoHush hears it
  (`ProcessTapLevelProbe`: half a second of listening, AutoHush's threshold),
  once System Audio Recording is allowed. Its **keep-awake assertions**, as
  AntiDot mode reads them (`IOKitPowerAssertionReader`):
  - Holding its own "keep the Mac awake" assertion, it plays; seen holding one while its sound was on, but not now, it's paused (VLC's "VLC media playback", Music's).
  - Deezer keeps its assertion while paused, so a surer sign decides for it.
- **Now Playing:** MediaRemote's player path, read only, as AutoHush asks
  it (`NowPlayingApp`). A process asks MediaRemote once and keeps its first
  answer, so each question runs a fresh copy of the tool, found by its own
  path (`proc_pidpath`).
- **Page buttons:** a web page in the app's windows is open to
  Accessibility as it is: a Safari web app's, or any app's (a Tauri app's,
  in Safari's WebKit, as Pake's YouTube Music; a Qt WebEngine app's, in
  Chromium, not tried yet). WebKit
  fills it in only once something first asks for it (YouTube Music, just
  opened: no buttons at the first look, 36 a few seconds later), so the
  tool waits until the count of buttons holds. The buttons are read as
  AutoHush reads a Safari web app's: each window's `AXWebArea` (up to 16
  levels down; at most 2,000 of a window's elements are read looking for
  one, and never inside a list or table, so a native app's song list isn't
  walked), then `AXUIElementsForSearchPredicate`, each button named by its
  description, else its title. The windows are those on the current
  desktop, else, as AutoHush finds them, those on another (macOS's window
  list holds only the current desktop's; the undocumented HIServices
  function `_AXUIElementCreateWithRemoteToken` reaches the rest).
- **Interfaces kept out of Accessibility:** three frameworks show their
  interface only once an assistive tool sets a switch (an attribute) on the
  app, found by the framework in `Contents/Frameworks`:

  | Framework | Its interface | Switches tried, in turn |
  |---|---|---|
  | Electron (`Electron Framework`: Deezer, TIDAL) | a web page | `AXManualAccessibility`, Electron's own and documented (electronjs.org, Accessibility) |
  | Chromium Embedded Framework (`Chromium Embedded Framework`: Spotify) | a web page | none of its own (each app decides): Electron's, then `AXEnhancedUserInterface`, which CEF's sample app listens to (Spotify takes only that one) |
  | Flutter (`FlutterMacOS`: Spotube) | the window's own elements, not a web page | `AXEnhancedUserInterface` only (Flutter's engine listens for it) |

  `AXEnhancedUserInterface` is VoiceOver's: window managers misbehave while
  it's on (the reason Electron made its own), so it's tried only for CEF and
  Flutter apps, after Electron's, and turned back off at the end. Each
  switch gets 4 s for the page to show (Deezer's: about 2 s; Spotify's:
  0.4 s). A Flutter app's buttons are the items it marks pressable
  (`AXPress`): its buttons, and texts and images, named by their
  description, title or value. Spotube's do show, but not its player bar's
  Previous, Pause and Next, which have no names.
- **Which button is the player's:** as AutoHush's learning ranks them:
  named Play or Pause, alone or first (SoundCloud's bar says "Pause
  current"; in English, Spanish, Catalan and a few more: the `playWords`
  and `pauseWords` lists), in sight and not covered, with a slider or
  progress bar around it, then the lowest. In sight means a real size
  inside the window (Electron squeezes what's scrolled out of the window to
  no height at its edge); not covered means macOS's hit test at its middle,
  within the app, finds it (song tiles under Deezer's and SoundCloud's
  player bars sit lower than the bar's button, but under it). Chromium
  answers a hit test from its last one at first, then precisely a moment
  later (Spotify's bar button, behind other windows: a group elsewhere,
  then the button), so the misses are asked again together, once, 0.2 s
  later, and only when one of them could change which button wins (being
  lower than the first uncovered one with a player bar). A window that
  isn't on screen (on another desktop, minimised, or its app hidden) isn't
  hit-tested.
- **The switches, set back:** a page readable already (an assistive tool
  asked for it before) still gets its switch, so the app keeps it up to
  date. A switch the tool turned on is turned back off at the end (also
  when the tool is stopped with Ctrl-C); `AXEnhancedUserInterface` found
  on already (VoiceOver) is left on. Electron's reads back as off even
  while it's on (Deezer), so with the page readable already a check leaves
  it on, in case another tool has it on; a press always turns it off,
  leaving the app as it found it. An app may answer an error yet take a
  switch (Spotify and Spotube answer -25208 to `AXEnhancedUserInterface`,
  and read it back as on), so either sign counts.
- **Electron's fuller mode, for presses:** Electron takes presses on its
  page only in the fuller accessibility mode its switch asks for, which
  starts 2 s after the switch last went on (Electron waits for requests to
  settle; an off sent meanwhile cancels the request and leaves a fuller
  mode already on). A press sooner is accepted but does nothing, while the
  page may already show (kept by another tool reading the app's role, which
  turns on a lighter mode that never ends while the app runs). So a press
  on an Electron page waits until 2 s after the switch went on, unless the
  switch reads back on: Electron says so only in that mode, alone.
- **Out of sight:** Chromium treats a page whose window is fully out of
  view (covered, on another desktop, full screen there) as hidden: an
  Electron app builds no page there, and takes no presses on one (Deezer's,
  tested 2026-10-12: lost, not late, not queued). A page built in view stays
  usable out of view only while its switch stays on; a press that turns the
  switch on and off, as this tool's do, loses it. Opened with
  `--disable-backgrounding-occluded-windows` (Chromium's option, which keeps
  a covered window's page visible to it), Deezer's page took presses
  covered, on another desktop and full screen; minimised or hidden, it
  didn't. Spotify (CEF) took them covered without it. A Flutter app may
  build no page out of view either (Spotube's, behind other windows); an
  Electron page out of view lags one state behind (Deezer's said Pause
  while paused). So
  when no switch shows its page in 4 s, a check brings the app forward a
  moment, once, turns on again there each switch the app took until its
  page shows, then brings back the app that was in front (and waits a second: frames read while a
  desktop slides are off), and says so. A press never brings anything
  forward (Player Check should be as unintrusive as possible): when the
  page doesn't show, or a press on a page out of sight doesn't take, it
  says so and suggests bringing the window into view or another way. With
  its window closed there's no page at all (Deezer plays on without one):
  open it and run again.
- **A leftover page:** Electron drops part of its page when its switch goes
  off, and a page out of sight stops changing, so a page readable already
  may be a leftover with no player bar in it (a first check of Deezer, on
  another desktop some ten minutes after a press, found no page button,
  and later checks did). When a check finds a page readable already with
  no player's Play/Pause in it (a button named so with a slider around it),
  it builds it again: the switch off and on, the bar looked for up to 4 s;
  if it doesn't show (out of sight it can't: Deezer's leftover kept its
  stale words through it), the app is brought forward a moment, as above,
  with the switch off and on there. A press doesn't. A leftover that still
  has its bar is used as it is.

**The test** (unless `--read-only`) tries each way while the app plays. If
it isn't playing, it asks ("waiting: start playing something in Deezer")
and goes on by itself as soon as it plays, up to 2 minutes. Each way
pauses the app, then plays it again; a play that didn't take is pressed
once more ("pressed once more: … the first didn't take"; the way still
fails in that state, saying so). A way that leaves it paused is followed by
playing it again quietly before anyone is asked, in any window state: by a
way that worked in this state, else by AppleScript, its menu, then the Now
Playing panel (a last resort, as it shows on screen); only when none plays
it does it ask again. A track that ends during a trial (the app reads
stopped after the play, where the pause left it paused) says nothing about
the way: the trial runs again once it plays, and fails only if the track
ends again ("play a longer one"). The ways, in order:

1. AppleScript: its pause and play commands (as Spotify's), else commands
   named so, else one that toggles (playpause, or VLC's play); to its
   documents when they act on one (QuickTime Player's).
2. Its playback menu's first item.
3. Its page's Pause, then Play.
4. Its row in the menu bar's Now Playing panel (Control Center's): the
   panel opens for about half a second, and takes the keyboard meanwhile.
   Its rows don't name their apps (the panel shows only their icons), so
   the app's row is the one whose song its windows' titles, its page's
   player bar or its AppleScript `current track` (else `name of current
   item`, VLC's) show whole (SoundCloud's window keeps a generic title,
   and so does a paused Spotify's; its bar, and Spotify's current track,
   name the song; VLC's window on another desktop can't be read at all),
   or that shows only its name. Else it's the row the app changed with
   before, kept between runs (below). While pausing, it can also be the
   only row playing when the app is the Now Playing one. Nothing is pressed
   when that isn't exactly one row. Play presses the row that was paused. A
   row pressed that changed when the app didn't is pressed again, so that
   app is left as it was.

The keyboard's Play/Pause key isn't tested: macOS sends it only to the
Now Playing app, and AutoHush can't choose which app that is (when it
pauses a player, the app that started playing may hold Now Playing, and
keeps it while paused), so a key that worked in a test says nothing about
AutoHush. Whether the app is Now Playing shows under "Sound and Now
Playing".

A way gets ✓ only when the app both paused and played again. An app with
nothing to press and nothing that reports to Now Playing isn't tested (no
waiting), and the panel isn't pressed for an app that can't reach Now
Playing (none of its binaries links MediaPlayer, MediaRemote, AVKit or
WebKit, as Player Check reads them). A permission macOS refuses (Automation for
AppleScript) is named as such, not as the app ignoring the way.

Stopped (Ctrl-C, or Player Check's Stop) between a pause and its play, or
while it moves the app's window, it finishes that first (and plays the app
again), then stops; otherwise it stops at once. Either way it puts the
app's window back as it was, turns the switches it turned on back off, and
brings back the app that was in front if it had brought the checked one
forward. It stops the
same way when whoever ran it ends without a word (Player Check's window
closed, or the app quit by force or crashed): its output would go nowhere,
and a check left running would go on pausing and playing the app unwatched.

Each pause is judged by the surest sign the app has, in this order:
1. its AppleScript state;
2. what it reports to Now Playing;
3. its page's button (Play while paused), while its word is current: a WebKit page's anywhere, a Chromium or Flutter page's only on screen (out of sight its word lags a state, and shows as "out of sight: its word lags");
4. its level;
5. its keep-awake assertion;
6. its menu's state;
7. its menu's word changing, or its open output.

A state notification confirms too, when it comes first. (Electron apps keep
their output open a few seconds after a pause, VLC a minute, and Deezer's
menu word changes late by itself: it said Play while playing, then Pause,
with nothing pressed.)

**The page's Play/Pause is learned**, as AutoHush learns a web app's:
- **The look while it plays:** taken once a test has the app playing.
- **The look once it's paused:** taken after the first test that paused it, by any way: its script, its menu, its page or the panel. AutoHush's `PlayPauseLearner` keeps the button whose words changed, preferring one in sight, with a player's controls, with the barest words, the lowest.
- **What's saved:** the site's own words for Play and Pause, and where the button is, as a `PlayPauseRecipe`.
- **From then on:** the page way presses that button.
- **When nothing else can pause it and no button is named Play or Pause:** the check asks whoever runs it to pause the app ("waiting: pause … yourself"), as AutoHush asks with It's Paused, and learns from that.
- **A Chromium or Flutter page out of sight:** its words lag a state behind, and would be learned the wrong way round, so no look is taken there, the user isn't asked to pause it, and a press there teaches nothing.
- **A press that took** teaches the button again (what it said before and after), only while its words are current.

A page button the site disabled (during an ad) is never pressed, as
AutoHush never presses one. AutoHush would mute the app instead, as it does
for a pause a site ignores (the player's own button pressed, and the app
didn't pause). A press can't hold a mute after it ends, so the tool says so.

**What the app reports to Now Playing** is each "PlaybackState changed from … to …" MediaRemote's
daemon writes in macOS's log, read as `--now-playing-list` reads it: the
past once (a log store opened is a snapshot that later lines don't reach,
and opening one takes about 0.6 s), back to when the app opened (an hour at
most), and what follows live from `log stream`, started first and ended
with the tool. It needs an administrator. It holds wherever the app's window is:
an Electron app's page on another desktop keeps the word it had (Deezer's
said Play while it played), so there the page's button is pressed whatever
it says, since it toggles. A pause that didn't show isn't undone:
nothing may have happened (Deezer's app ignores menu presses), or the app
may have paused without showing it, so check by ear.

Meanwhile it listens for the app's state notification under the usual names
(`<bundle ID>.PlaybackStateChanged`, `<bundle ID>.playerInfo` and a few
variants): macOS delivers a distributed notification only to observers that
name it (one with no name gets nothing, measured on macOS 27), so a name
outside that list can't be seen. Without one, the player's state must be
read once a second (`PolledStateObserver`).

## Window states

A player's window may be anywhere while AutoHush pauses it, and some ways
work only in some places (an Electron page, only in view), so the test
tries every way with the app's main window (its biggest ordinary one that
Accessibility knows) in each of these states, in this order, and comes
back to the app it was run from (Player Check, or a terminal) before each
state's trials:

| State | How the tool puts it there |
|---|---|
| visible | shown, on this desktop, not minimised or full screen; when the app it came from covers it whole, that app's window is moved aside (put back at the end) |
| covered | a window of the tool's own, opaque, over it |
| on another desktop | dragged there, as a person drags a window: see below |
| covered on another desktop | the tool's window over it there |
| full screen | `AXFullScreen` |
| minimised | `AXMinimized` |
| hidden | the app hidden, as ⌘H hides it |

Before each, the window is brought back to visible, and after each the
state is read back: a state the window doesn't reach is "not tested", with
why. At the end (or at a stop) the window is put back as it was: its
state, its place and its desktop, the moved window too, and the app the
tool was run from in front. With no window open (Deezer plays on without
one), the ways are tried once, as the window is. With only one desktop
(full screen apps' don't count), the two desktop states aren't tested: add
a desktop in Mission Control.

In the first state the page's switch stays on, for learning its button;
after that, each press by the page turns the switch on (giving the page up
to 4 s to show), presses, and turns it off once it's seen whether it took,
as the tool's own presses (`--play`, `--pause`) and Player Check's do. Kept
on all along, a page built in view stays usable out of view (Deezer's
passed every state that way, even without its launch option), which those
presses don't get.

Why a state failed is said under the way: what's known (an Electron app
opened without the launch option its page needs out of view: "Chromium
neither builds nor presses a page whose window is fully out of view"),
else what the press said ("its page didn't show with Electron's switch
on"), else what the trial saw ("pressing it changed nothing").

**Dragging a window to another desktop.** macOS has no API for moving
another app's window there, so it's dragged: the app is brought forward
(SkyLight's `_SLPSSetFrontProcessWithOptions`, as window switchers do, and
the window raised: from a process in the background, Accessibility's
`AXFrontmost` and `NSRunningApplication.activate()` change nothing), held
at a spot of its top bar, Control-→ (or ←) pressed, and let go. Found
making it work (2026-10-12, macOS 27):
- The arrow must carry the Fn and number-pad flags a keyboard's arrows
  carry: macOS's desktop shortcuts are registered with them.
- Control must be released with an event of its own: the flags of posted
  events stay in the system's keyboard state, and every later click would
  be a Control-click, which can't drag a window.
- An Electron app's top bar can be dragged only where its page marks it so,
  which Accessibility can't tell (Deezer's: right of its search field), so
  spots that aren't controls are tried in turn, each with a small drag
  towards the screen's middle (a window at its edge may not go further)
  that shows whether it holds; the page is shown to Accessibility meanwhile,
  so its buttons aren't taken for the bar.
- Once held, the window is dragged back to where it started, so it lands
  in its place on the other desktop (setting its place afterwards would
  bring it back to this one).

The desktops and a window's desktop are read with SkyLight's read-only
`SLSCopyManagedDisplaySpaces` and `SLSCopySpacesForWindows`; the window
list doesn't keep another desktop's order, so a window there isn't told
covered or not by it. A window off screen on the current desktop is one
the app closed and keeps (Electron's): no window.

## Launching Electron apps with Chromium's option

`--launch-option <app>` prints the option an app needs for its page to
take presses out of view, and whether its running copy has it (`sysctl`'s
`KERN_PROCARGS2`, as `ps` reads launch arguments), separated by a tab:
`--disable-backgrounding-occluded-windows` and `yes`, `no` or `not
running`. Only Electron's apps get one. `--relaunch <app>` quits the app as a person would (never by force:
it's given 15 s), opens it again with the option, in the background, and
sends it back behind the app that was in front when it comes forward by
itself (Deezer does, a few seconds after its window shows). Player Check
shows a Relaunch button for an Electron app running without it, and opens
one that isn't running with it.

## Ways to control it

The report ends, before the verdict, with one line per way known to
control an app, each with a mark: ✓ it paused and played again in the
test in every window state tested, ⚠ in some (the states where it didn't
are listed under it, with why: "✗ covered: …"; those not tested, "–
covered: not tested (…)"), ✗ in none, or not there, ? found but not tried
(`--read-only`, or it didn't play), – not checked (it doesn't apply, the
app isn't running, or there's no Accessibility permission, which the menu,
the page and the Now Playing panel need). The ways are the four above.
Player Check shows that section as a checklist.

## Playing and pausing (`--play`, `--pause`)

The checks run silently, then it plays or pauses the app by the way named
with `--via` (`script`, `menu`, `page` or `panel`), or else tries
AppleScript (as Spotify's), the page's button, then the menu (the panel
only when named: it shows on screen), and prints one line: what it
did ("Paused it by AppleScript (pause), as its notification announced."),
that it was that way already, or why none worked. It exits 0 when it's
played or paused, 1 when not. AppleScript and the page's buttons say play
or pause; the menu's first item toggles, so it's pressed only when the
surest sign, as a test judges (above), says the app is the other way (its
menu's word only for an app with nothing surer: Deezer's changes late by
itself). Each way is
confirmed within 6 s, looking every 0.05 s: the scripted state, what the
app reports to Now Playing, the page's button's word, or the menu's word or
the sound. While the page's player bar is on screen, its word is trusted
and macOS's log isn't read (opening it and reading back to when the app
opened takes 1.4–2 s); on another desktop an Electron page's word goes
stale, so there the log is read. A WebKit page's word is trusted out of
sight too (a Safari web app's, or an app's own WebKit page, as Tauri apps
show theirs; not Qt WebEngine's, which is Chromium): on another desktop,
Pake's YouTube Music and SoundCloud's web app showed each change within
0.5 s, also after more than 6 minutes there, and their presses there took
0.3–0.5 s and 0.13–0.15 s. The page way presses the player bar's
button its page check found, read again by its word, without searching the
page again.

With `--via`, it reads only what that way needs, so a press starts sooner:
the scripting dictionary when the bundle has one (for the script way, and
its state shows quickest whether the app plays), the menu for the menu way,
the page for the page way and the panel (whose row is found by the page's
player bar), and the menu and the page for any way when nothing surer than
their words shows whether the app plays (its scripted state, or, for an
administrator, what it reports to Now Playing). The app's own words for
Play and Pause are read whenever the menu or the page may be. "Sound and
Now Playing" is only shown, so a press never reads it.

**The player bar's button is remembered**, as AutoHush remembers a web
app's learned button. Each check or press that finds it saves, per app, in
`~/Library/Caches/PlayerCheck/button-places.json`:
- where it sits: the child indices from its page, or from a Flutter app's window;
- once learned, its recipe: both words, and up to 3 places by the kinds of element around it and their distance from the window's bottom.

A press then tries, in turn:
1. The saved indices, when what's there says one of the recipe's words, or, without a recipe, is named Play or Pause with a player's slider around it, in sight.
2. The recipe's place among the page's buttons (`PlayPauseRecipe.find`), as AutoHush finds a learned button after its page reloads.
3. A search, as before.

A press whose button's words change teaches the recipe again, as AutoHush
learns a button again once it went missing. It
can't help Deezer: its page doesn't exist until its switch is on and it has
built it again (about 3.5 s; only keeping the switch on between presses
would).

**A press by the panel** finds the app's row by its song in its windows'
titles or what it plays by AppleScript first (Deezer's title, Spotify's
current track and VLC's current item name it), with the remembered player
bar's song when there is one; else by the text of the row it last changed
the app with (in a check's panel trial or a press by the panel), kept in
`button-places.json` too, when exactly one row shows it; and reads the
page only when nothing matches (SoundCloud's title doesn't name the song).
The row's own Play/Pause, as Now Playing knows the app, says whether it's
that way already, and shows the press take before the panel closes (2 s at
most), so neither the page nor macOS's log is needed. A row told only by
the app holding Now Playing is judged by the app itself, as before.

A whole press (the process from start to end), measured on macOS 27
(2026-10-11), first before these changes: Spotify by AppleScript 0.8 s →
0.1–0.5 s; by its page, on another desktop, 1.8–2.2 s → 0.4–0.6 s; Pake's
YouTube Music by its page 2.2–3.1 s → 0.3–0.55 s; SoundCloud's web app by
its page about 0.9 s → 0.1–0.3 s; Deezer by its page 6.8–8.3 s →
3.7–4.0 s (its switch); by the Now Playing panel, any of them,
0.7–1.1 s (Deezer's 4.1–4.4 s before); Music by AppleScript 0.1–0.3 s.

Tested on macOS 27 (2026-10-11): Spotify by AppleScript (1–2 s), Deezer by
its page's buttons (its window covered by others), SoundCloud's web app by
its bar's "Play current" and "Pause current", and Deezer's menu failing as
it should. The full test passed every way that applies on Spotify
(AppleScript, menu, panel), Deezer (page, panel; its menu fails),
SoundCloud (page, panel) and VLC (its toggling AppleScript `play`, judged
by its `playing` flag; panel; its Playback menu's item was disabled there,
so ✗). Then (2026-10-11) Spotify's page with `AXEnhancedUserInterface`:
the full test passed all four ways, its window on the current desktop and
on another, and `--pause`/`--play --via page` worked; Spotube 5.1.2
(Flutter) showed its interface with that switch, but its player bar's
buttons have no names, so ✗ page button. Pake's YouTube Music (a Tauri
app, 3.17.3): its page's button paused and played it, with no switch. It
reports to Now Playing through WebKit's GPU process under its own bundle
ID, so WebKit counts as a way into Now Playing for any app: then its full
test passed the page and the panel, judged by what it reports.

## The apps in Now Playing (`--now-playing-list`)

One tab-separated line per app macOS keeps in Now Playing: its bundle ID,
its process, its last state (Playing, Paused, Stopped, or Registered: ready
for Now Playing, never said it plays), 1 for the active one (the Now
Playing app), and its name; then `#active` and the Now Playing process. A number
after it reads only the last hours of log. With `--since <unix time>` it
lists only the apps whose entries changed since then, those gone as
`Removed`: a caller that read the whole list once keeps it up to date that
way, without reading days of log again (Player Check does). An app seen
then with no state change reads `Registered`; for the same process, the
state known before still holds (Player Check keeps it).

`--now-playing-reasons <app path>…` prints a line per app for Player
Check's list: `<path>\t<why it can be in Now Playing>\t<the framework that
hides its interface>\t<the switches a check turns on, in order>`, each
empty when there's none (for example `/Applications/Spotify.app\tMediaPlayer\tChromium
(CEF)\tElectron's switch, else VoiceOver's switch`), so the window shows
this tool's own rules.

Since macOS 15.4, MediaRemote won't list Now Playing's apps for an app
without Apple's entitlement, so this reads what MediaRemote's daemon writes
in macOS's log since the Mac started (`OSLogStore`): each app it adds, each
app's own "PlaybackState changed from … to …" (also while another app is
the active one), and each app it removes when it quits. Limits: only an
**administrator** may read the log ("Client lacks entitlement" otherwise);
the log's wording is macOS's, not an API, so an update can change it; and
it takes a few seconds on a Mac that hasn't restarted for days. A web app
plays through WebKit's media process, which the log names with the web
app's bundle ID.
