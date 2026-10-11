# PlayerCheck

Says whether AutoHush could control an app (pause it while another app
plays, then play it again), and which kind of player it would be, so it
could be added as the README's [Adding a media player](../../README.md#architecture)
says. It reads the app's scripting dictionary, its playback menu, where its
sound comes from, whether it's Now Playing and, for a Safari web app or an
Electron app (Deezer, TIDAL), the Play/Pause button of its page. It ends
with a checklist of the ways it could be controlled, and can also play or
pause the app. [Player Check](../PlayerCheckApp) does all of this from a
window.

## Use

```bash
swiftc -O -o playercheck Tools/PlayerCheck/playercheck.swift
./playercheck Spotify                    # by name, bundle ID or path; reads only
./playercheck Spotify --press            # while it plays: also pauses and plays it once, each way it found
./playercheck Spotify --pause            # just pauses it (--play: plays it), by the first way that works
./playercheck Deezer --play --via page   # by that way only: script, menu or page
./playercheck --now-playing-list         # the apps macOS keeps in Now Playing now
```

Whatever runs it (Terminal, say) needs the **Accessibility** permission
for the menu and page checks, and macOS asks once per app for
**Automation** the first time it reads or controls that app by AppleScript.
The app must be running for everything but its scripting dictionary.

Example, with Spotify playing:

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
  by script: before, menu 'Pause', state playing, sound on
    after the pause: menu 'Pause', state paused, sound on → it paused
  by its menu: …
  notification: com.spotify.client.PlaybackStateChanged [… Player State …]
Ways to control it
  ✓ AppleScript: pausing and playing it by script worked, as Spotify and Apple Music
  …
  ✓ Play/Pause key: it's Now Playing, so the key reaches it (until another app reports playing)
  …
Verdict
  Scriptable, like Spotify and Apple Music: a ScriptablePlayerProfile with suite fourCharCode("spfy").
  It has a volume: measure its curve (swift run measure-volume-curve com.spotify.client).
  State notification: com.spotify.client.PlaybackStateChanged.
```

Deezer's app (7.1.340, Electron 38.4.0) with `--press`, while it plays:

```
Page buttons
  built with Electron 38.4.0: its page shows once Electron's switch is on
  AXManualAccessibility on: its page showed 112 buttons after 2.2 s (one read, as AutoHush reads a web app: 23 ms)
  Play/Pause: 'Pause', 51 pt from the window's bottom, with a player's slider around it

Press test
  by its menu: before, menu 'Pause', page 'Pause', sound on
    after the pause: menu 'Pause', page 'Pause', sound on → nothing changed in 4 s: it didn't take, or can't be seen
  by its page's button: before, menu 'Pause', page 'Pause', sound on
    after the pause: menu 'Pause', page 'Play', sound on → it paused
    after playing again: menu 'Pause', page 'Pause', sound on
  …
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
  (`pVol`) for fades.
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
  else its title.
- **Which button is the player's:** as AutoHush's learning ranks them:
  named Play or Pause, alone or first (SoundCloud's bar says "Pause
  current"; in English, Spanish, Catalan and a few more: the `playWords`
  and `pauseWords` lists), in sight and not covered, with a slider or
  progress bar around it, then the lowest. In sight means a real size
  inside the window (Electron squeezes what's scrolled out of the window to
  no height at its edge); not covered means macOS's hit test at its middle,
  within the app, finds it (song tiles under Deezer's and SoundCloud's
  player bars sit lower than the bar's button, but under it).
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

With `--press`, and only while the app plays (its scripted state says
playing, or its sound is on), it pauses the app once by script (when the
dictionary fits), once with its menu's first item and once with its page's
Pause, each time watching for 4 s whether the menu's or the page's word,
the scripted state or the sound changed, then plays it again. A pause that
changed nothing it can see isn't undone: nothing may have happened (Deezer's
app ignores menu presses), or the app may have paused without showing it,
so check by ear. Electron apps keep their sound on a few seconds after a
pause, and Deezer's menu updates its word late, so there only the page's
word shows it at once.

Meanwhile it listens for the app's state notification under the usual names
(`<bundle ID>.PlaybackStateChanged`, `<bundle ID>.playerInfo` and a few
variants): macOS delivers a distributed notification only to observers that
name it (one with no name gets nothing, measured on macOS 27), so a name
outside that list can't be seen. Without one, the player's state must be
read once a second (`PolledStateObserver`).

## Ways to control it

The report ends, before the verdict, with one line per way known to
control an app, each with a mark: ✓ it works (tried, or the Play/Pause key
reaches it now), ? found but not tried (`--press` while it plays), ✗ not
there or didn't work, – not checked. The ways: AppleScript, the playback
menu, the page's button, the Play/Pause key (it reaches only the app that's
Now Playing), and the Now Playing panel in the menu bar (its rows play and
pause any app listed there; not checked by this tool). Player Check shows
that section as a checklist.

## Playing and pausing (`--play`, `--pause`)

The checks run silently, then it plays or pauses the app by the way named
with `--via` (`script`, `menu` or `page`), or else tries AppleScript (as
Spotify's), the page's button, then the menu, and prints one line: what it
did and what changed ("Paused it by AppleScript (pause): its state is
paused."), that it was that way already, or why none worked. It exits 0
when it's played or paused, 1 when not. AppleScript and the page's buttons
say play or pause; the menu's first item toggles, so it's pressed only when
the sound says the app is the other way (an Electron app's sound stays on
a few seconds after a pause: that's why the page comes first). Each way is
confirmed within 4 s: the scripted state, the page's button's word, or the
menu's word or the sound.

Tested on macOS 27 (2026-10-11): Spotify by AppleScript (1–2 s), Deezer by
its page's buttons (its window covered by others), SoundCloud's web app by
its bar's "Play current" and "Pause current", and Deezer's menu failing as
it should ("pressed its menu's 'Pause', but nothing changed in 4 s").

## The apps in Now Playing (`--now-playing-list`)

One tab-separated line per app macOS keeps in Now Playing: its bundle ID,
its process, its last state (Playing, Paused, Stopped, or Registered: ready
for Now Playing, never said it plays), 1 for the one the Play/Pause key
reaches, and its name. A number after it reads only the last hours of log.

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
