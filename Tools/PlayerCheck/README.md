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
(asking you to start it first if it isn't playing), and ends with a
checklist of what worked. It can also just play or pause the app. [Player Check](../PlayerCheckApp) does all of this from a
window.

## Use

```bash
swiftc -O -o playercheck Tools/PlayerCheck/playercheck.swift
./playercheck Spotify                    # by name, bundle ID or path: checks it and tests each way
./playercheck Spotify --read-only        # checks it without pressing anything
./playercheck Spotify --pause            # just pauses it (--play: plays it), by the first way that works
./playercheck Deezer --play --via page   # by that way only: script, menu, page or panel
./playercheck --now-playing-list         # the apps macOS keeps in Now Playing now
./playercheck --now-playing-list --since 1760180000   # only what changed since then (apps gone: Removed)
./playercheck --now-playing-reasons /Applications/Spotify.app   # why each app can be in Now Playing (Player Check's list)
```

Whatever runs it (Terminal, say) needs the **Accessibility** permission
for the menu and page checks, and macOS asks once per app for
**Automation** the first time it reads or controls that app by AppleScript.
The app must be running for everything but its scripting dictionary.

Example, with Spotify paused at the start:

```
Spotify 1.3.4.258 (com.spotify.client)
Scripting dictionary
  commands: pause (spfyPaus), playpause (spfyPlPs), play (spfyPlay)
  player state (pPlS): yes, values stopped/playing/paused: yes
  sound volume (pVol): yes, so it can fade
Playback menu
  'Playback': first item 'Pause', enabled
Sound and Now Playing
  sound output running now: Spotify (com.spotify.client, pid 394)
  Now Playing: this app (until another app reports playing)
Page buttons
  built with Chromium (CEF): its page shows once a switch for assistive tools is on (Electron's switch, else VoiceOver's switch)
  Electron's switch (AXManualAccessibility): not taken
  VoiceOver's switch on: its page showed 161 buttons after 0.4 s (one read, as AutoHush reads a web app: 35 ms)
  Play/Pause: 'Pause', 56 pt from the window's bottom, with a player's slider around it
Press test
  waiting: start playing something in Spotify; the test goes on as soon as it plays (up to 2 minutes)
  it plays: testing
  by script: before, menu 'Pause', state playing, sound on
    after the pause: menu 'Pause', state paused, sound on → it paused
    after playing again: menu 'Pause', state playing, sound on
  by its menu: …
  by its page's button: …
  by the Now Playing panel: …
  notification: com.spotify.client.PlaybackStateChanged [… Player State …]

Ways to control it
  ✓ AppleScript: pausing and playing it by script worked, as Spotify and Apple Music
  ✓ Playback menu 'Playback': pressing it paused and played it, as TIDAL and Apple Podcasts
  ✓ Page button, with VoiceOver's switch on: 'Pause': pressing it paused and played it
  ✓ Now Playing panel: pressing its row ('Leave Forever, Hayes & Y – Departures') paused and played it
Verdict
  Scriptable, like Spotify and Apple Music: a ScriptablePlayerProfile with suite fourCharCode("spfy").
  It has a volume: measure its curve (swift run measure-volume-curve com.spotify.client).
  State notification: com.spotify.client.PlaybackStateChanged.
  With VoiceOver's switch on, its page's Play/Pause works: it could be a player that learns that button, …

(VoiceOver's switch set back to off, as it was.)
```

Deezer's app (7.1.340, Electron 38.4.0), while it plays:

```
Page buttons
  built with Electron 38.4.0: its page shows once a switch for assistive tools is on (Electron's switch)
  Electron's switch on: its page showed 112 buttons after 2.2 s (one read, as AutoHush reads a web app: 23 ms)
  Play/Pause: 'Pause', 51 pt from the window's bottom, with a player's slider around it

Press test
  by its menu: before, menu 'Pause', page 'Pause', sound on
    after the pause: menu 'Pause', page 'Pause', sound on → it didn't pause in 4 s
  by its page's button: before, menu 'Pause', page 'Pause', sound on
    after the pause: menu 'Pause', page 'Play', sound on → it paused
    after playing again: menu 'Pause', page 'Pause', sound on
  …
Ways to control it
  ✗ AppleScript: no scripting dictionary
  ✗ Playback menu 'Play' (found by ⇧← ⇧→, not ⌘← ⌘→): pressing it changed nothing
  ✓ Page button, with Electron's switch on: 'Pause': pressing it paused and played it
  ✓ Now Playing panel: pressing its row ('Another One Bites The Dust, Queen – The Game') paused and played it

Verdict
  Its menu has Play/Pause, but pressing it didn't take (as Deezer's menu): not controllable that way.
  With Electron's switch on, its page's Play/Pause works: it could be a player that learns that button,
  as Safari web apps (WebAppPlayers), with no fades; AutoHush has no such player for apps yet.

(Electron's switch set back to off, as it was.)
```

Checked on macOS 27 (2026-10-11) against the players AutoHush supports:
Spotify (`spfy`) and Apple Music (`hook`) come out as scriptable, TIDAL and
Apple Podcasts as menu players, VLC as a menu player whose scripting
doesn't fit, YouTube Music and SoundCloud as web apps, Safari and TextEdit
as neither.

## What it checks

Everything is read from outside the app, as AutoHush itself would:

- **Scripting:** `/usr/bin/sdef` prints the app's dictionary. AutoHush's
  `ScriptablePlayers` need pause and play in the app's own suite
  (`<suite>Paus`, `<suite>Play`), the `player state` property (`pPlS`) with
  stopped, playing and paused (`kPSS`, `kPSP`, `kPSp`), and `sound volume`
  (`pVol`) for fades. An app whose dictionary has a true/false `playing`
  property instead (VLC's) has its state read from that.
- **Playback menu:** through Accessibility, the menu whose items include ⌘←
  and ⌘→, with Play/Pause first, as `AccessibilityPlaybackMenu` finds it
  whatever the app's language. Failing that, a menu whose first item is on
  Space and that has ← and → under other modifiers: Deezer's Play menu
  (Space, ⇧← ⇧→), which AutoHush wouldn't find as it is, and the tool says
  so. (Every arrow shortcut of a menu counts: TIDAL has ⌘← for Previous and
  ⇧⌘← for Seek back.)
- **Sound:** Core Audio's process objects with output running whose
  responsible process is the app (`responsibility_get_pid_responsible_for_pid`),
  so a helper that plays for it (WebKit's media process for a web app)
  counts as the app.
- **Now Playing:** MediaRemote's player path, read only. A process asks
  MediaRemote once and keeps its first answer, so each question runs a
  fresh copy of the tool, found by its own path (`proc_pidpath`).
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
  then the button), so a miss is asked again after 0.2 s. A window that
  isn't on screen (on another desktop, minimised, or its app hidden) isn't
  hit-tested.
- **The switches, set back:** a page readable already (an assistive tool
  asked for it before) needs none, so none is turned on. A switch the tool
  turned on is turned back off at the end (also when the tool is stopped
  with Ctrl-C); `AXEnhancedUserInterface` found on already (VoiceOver) is
  left on. An app may answer an error yet take a switch (Spotify and
  Spotube answer -25208 to `AXEnhancedUserInterface`, and read it back as
  on), or read Electron's back as off while it's on (Deezer), so either
  sign counts. A Chromium or Flutter app may build no page while its
  window can't be seen (Deezer's, fully covered by others; Spotify's, on
  another desktop when the switch went on; Spotube's, behind other
  windows); once built, the page stays readable covered, hidden, minimised
  or on another desktop. So when no page shows in 4 s, the tool brings the
  app forward a moment, turns the switch off and on again there, waits for
  its page, then brings back the app that was in front (and waits a
  second: frames read while a desktop slides are off), and says so. With
  its window closed there's no page at all (Deezer plays on without one):
  open it and run again.

**The test** (unless `--read-only`) tries each way while the app plays. If
it isn't playing, it asks ("waiting: start playing something in Deezer")
and goes on by itself as soon as it plays, up to 2 minutes; it asks again
if a way leaves it stopped. Each way pauses the app, then plays it again:

1. AppleScript: its pause and play commands (as Spotify's), else commands
   named so, else one that toggles (playpause, or VLC's play).
2. Its playback menu's first item.
3. Its page's Pause, then Play.
4. Its row in the menu bar's Now Playing panel (Control Center's): the
   panel opens for about half a second, and takes the keyboard meanwhile.
   Its rows don't name their apps (the panel shows only their icons), so
   the app's row is the one whose song its windows' titles, its page's
   player bar or its AppleScript `current track` show whole (SoundCloud's
   window keeps a generic title, and so does a paused Spotify's; its bar,
   and Spotify's current track, name the song), or that shows only its
   name. While pausing, it can also be the only row playing when the app
   is the Now Playing one. Nothing is pressed when that isn't exactly one
   row. Play presses the row that was paused. A row pressed that changed
   when the app didn't is pressed again, so that app is left as it was.

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

Stopped (Ctrl-C, or Player Check's Stop) between a pause and its play, it
plays the app again first, then stops; otherwise it stops at once. Either
way it turns the switches it turned on back off, and brings back the app
that was in front if it had brought the checked one forward.

Each pause is judged by the surest sign the app has: its AppleScript
state, else what it reports to Now Playing, else its page's button (Play
while paused), else its menu's word or its sound. (Electron apps keep their
sound on a few seconds after a pause, and Deezer's menu word changes late
by itself: it said Play while playing, then Pause, with nothing pressed.)
What it reports is each "PlaybackState changed from … to …" MediaRemote's
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

## Ways to control it

The report ends, before the verdict, with one line per way known to
control an app, each with a mark: ✓ it paused and played again in the
test, ✗ not there or didn't work (or it only paused), ? found but not tried
(`--read-only`, or it didn't play), – not checked (it doesn't apply, or the
app isn't running). The ways are the
five above. Player Check shows that section as a checklist.

## Playing and pausing (`--play`, `--pause`)

The checks run silently, then it plays or pauses the app by the way named
with `--via` (`script`, `menu`, `page` or `panel`), or else tries
AppleScript (as Spotify's), the page's button, then the menu (the panel
only when named: it shows on screen), and prints one line: what it
did and what changed ("Paused it by AppleScript (pause): its state is
paused."), that it was that way already, or why none worked. It exits 0
when it's played or paused, 1 when not. AppleScript and the page's buttons
say play or pause; the menu's first item toggles, so it's pressed only when
the sound says the app is the other way (an Electron app's sound stays on
a few seconds after a pause: that's why the page comes first). Each way is
confirmed within 6 s: the scripted state, what the app reports to Now
Playing, the page's button's word, or the menu's word or the sound.

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
way, without reading days of log again (Player Check does).

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
