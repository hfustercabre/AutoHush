# PlayerCheck

Says whether AutoHush could control an app (pause it while another app
plays, then play it again), and which kind of player it would be, so it
could be added as the README's [Adding a media player](../../README.md#architecture)
says. It reads the app's scripting dictionary, its playback menu, where its
sound comes from, whether it's Now Playing and, for a Safari web app or an
Electron app (Deezer, TIDAL), the Play/Pause button of its page. Then it
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
./playercheck Deezer --play --via page   # by that way only: script, menu, page, key or panel
./playercheck --now-playing-list         # the apps macOS keeps in Now Playing now
./playercheck --now-playing-list --since 1760180000   # only what changed since then (apps gone: Removed)
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
  Now Playing: this app (the Play/Pause key reaches it, until another app reports playing)
Press test
  waiting: start playing something in Spotify; the test goes on as soon as it plays (up to 2 minutes)
  it plays: testing
  by script: before, menu 'Pause', state playing, sound on
    after the pause: menu 'Pause', state paused, sound on → it paused
    after playing again: menu 'Pause', state playing, sound on
  by its menu: …
  by the Play/Pause key: …
  by the Now Playing panel: …
  notification: com.spotify.client.PlaybackStateChanged [… Player State …]

Ways to control it
  ✓ AppleScript: pausing and playing it by script worked, as Spotify and Apple Music
  ✓ Playback menu 'Playback': pressing it paused and played it, as TIDAL and Apple Podcasts
  – Page button: not checked (neither a web app nor an Electron app)
  ✓ Play/Pause key: pressing it paused and played it (it reaches the Now Playing app)
  ✓ Now Playing panel: pressing its row ('Leave Forever, Hayes & Y – Departures') paused and played it
Verdict
  Scriptable, like Spotify and Apple Music: a ScriptablePlayerProfile with suite fourCharCode("spfy").
  It has a volume: measure its curve (swift run measure-volume-curve com.spotify.client).
  State notification: com.spotify.client.PlaybackStateChanged.
```

Deezer's app (7.1.340, Electron 38.4.0), while it plays:

```
Page buttons
  built with Electron 38.4.0: its page shows once Electron's switch is on
  AXManualAccessibility on: its page showed 112 buttons after 2.2 s (one read, as AutoHush reads a web app: 23 ms)
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
  ✓ Play/Pause key: pressing it paused and played it (it reaches the Now Playing app)
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
- **Page buttons:** a Safari web app's page is open to Accessibility as it
  is, but WebKit fills it in only once something first asks for it (YouTube
  Music, just opened: no buttons at the first look, 36 a few seconds
  later), so the tool waits until the count of buttons holds. An app with
  `Contents/Frameworks/Electron Framework.framework` is Electron. Its
  interface is a web page, kept out of Accessibility until an assistive
  tool sets `AXManualAccessibility` on the app: Electron's documented
  switch (electronjs.org, Accessibility), narrower than Chromium's
  `AXEnhancedUserInterface`, which VoiceOver sets and which has side
  effects, so the tool never touches that one. It sets the switch, waits
  for the page (Deezer's: about 2 s), and reads the buttons as AutoHush
  reads a Safari web app's: each window's `AXWebArea`, then
  `AXUIElementsForSearchPredicate`, each button named by its description,
  else its title. The windows are those on the current desktop, else, as
  AutoHush finds them, those on another (macOS's window list holds only the
  current desktop's; the undocumented HIServices function
  `_AXUIElementCreateWithRemoteToken` reaches the rest).
- **Which button is the player's:** as AutoHush's learning ranks them:
  named Play or Pause, alone or first (SoundCloud's bar says "Pause
  current"; in English, Spanish, Catalan and a few more: the `playWords`
  and `pauseWords` lists), in sight and not covered, with a slider or
  progress bar around it, then the lowest. In sight means a real size
  inside the window (Electron squeezes what's scrolled out of the window to
  no height at its edge); not covered means macOS's hit test at its middle,
  within the app, finds it (song tiles under Deezer's and SoundCloud's
  player bars sit lower than the bar's button, but under it). A window on
  another desktop isn't on screen, so its buttons aren't hit-tested.
- **Electron's switch, set back:** reading it always answers 0, so it
  counts as off when the page wasn't readable before; then it's set back
  off at the end (also when the tool is stopped with Ctrl-C), and otherwise
  left on (VoiceOver may need it). Turned on while the window is fully
  covered by others, the switch may build no page; once built, the page
  stays readable covered, hidden or minimised. So when no page shows in
  4 s, the tool brings the app forward a moment, waits for its page, then
  brings back the app that was in front, and says so. With its window
  closed there's no page at all (Deezer plays on without one): open it and
  run again.

**The test** (unless `--read-only`) tries each way while the app plays. If
it isn't playing, it asks ("waiting: start playing something in Deezer")
and goes on by itself as soon as it plays, up to 2 minutes; it asks again
if a way leaves it stopped. Each way pauses the app, then plays it again:

1. AppleScript: its pause and play commands (as Spotify's), else commands
   named so, else one that toggles (playpause, or VLC's play).
2. Its playback menu's first item.
3. Its page's Pause, then Play.
4. The keyboard's Play/Pause key, posted as a person would press it: only
   while the app is Now Playing, since macOS sends the key to that app,
   checked again before the second press (another app may take Now Playing
   meanwhile, as one resuming its music when this one pauses).
5. Its row in the menu bar's Now Playing panel (Control Center's): the
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

A way gets ✓ only when the app both paused and played again. An app with
nothing to press and nothing that reports to Now Playing isn't tested (no
waiting), and the key and the panel aren't pressed for an app that can't
reach Now Playing (none of its binaries links MediaPlayer, MediaRemote or
AVKit, as Player Check reads them). A permission macOS refuses (Automation
for AppleScript, posting keys) is named as such, not as the app ignoring
the way.

Stopped (Ctrl-C, or Player Check's Stop) between a pause and its play, it
plays the app again first, then stops; otherwise it stops at once. Either
way it sets Electron's switch back and brings back the app that was in
front if it had brought the checked one forward.

Each pause is judged by the surest sign the app has: its AppleScript
state, else its page's button (Play while paused), else its menu's word or
its sound. (Electron apps keep their sound on a few seconds after a pause,
and Deezer's menu word changes late by itself: it said Play while playing,
then Pause, with nothing pressed.) A pause that didn't show isn't undone:
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
with `--via` (`script`, `menu`, `page`, `key` or `panel`), or else tries
AppleScript (as Spotify's), the page's button, then the menu (the key and
the panel only when named: they can reach another app, and the panel shows
on screen), and prints one line: what it
did and what changed ("Paused it by AppleScript (pause): its state is
paused."), that it was that way already, or why none worked. It exits 0
when it's played or paused, 1 when not. AppleScript and the page's buttons
say play or pause; the menu's first item toggles, so it's pressed only when
the sound says the app is the other way (an Electron app's sound stays on
a few seconds after a pause: that's why the page comes first). The key is
pressed only while the app is Now Playing. Each way is confirmed within
6 s: the scripted state, the page's button's word, or the menu's word or
the sound.

Tested on macOS 27 (2026-10-11): Spotify by AppleScript (1–2 s), Deezer by
its page's buttons (its window covered by others), SoundCloud's web app by
its bar's "Play current" and "Pause current", and Deezer's menu failing as
it should. The full test passed every way that applies on Spotify
(AppleScript, menu, key, panel), Deezer (page, key, panel; its menu fails),
SoundCloud (page, key, panel) and VLC (its toggling AppleScript `play`,
judged by its `playing` flag; key; panel; its Playback menu's item was
disabled there, so ✗).

## The apps in Now Playing (`--now-playing-list`)

One tab-separated line per app macOS keeps in Now Playing: its bundle ID,
its process, its last state (Playing, Paused, Stopped, or Registered: ready
for Now Playing, never said it plays), 1 for the one the Play/Pause key
reaches, and its name; then `#active` and the Now Playing process. A number
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
