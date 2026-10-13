# PlayerCheck

Says whether AutoHush could control an app (pause it while another app
plays, then play it again), and which kind of player it would be, so it
can be added as the README's [Adding a media player](../../README.md#architecture)
says. It reads the app from outside, as AutoHush would, then tests each way
to control it, with the app's window in each state a player's window can
be in. [Player Check](../PlayerCheckApp) does all of this from a window.

It's a target of AutoHush's package and runs AutoHush's own code wherever
the two do the same thing (Apple events, VLC's states, playback menus and
their words, learning a page's Play/Pause, sound, windows on other
desktops, Now Playing), so what it finds holds for AutoHush. What AutoHush
doesn't do yet stays its own: players of documents (QuickTime Player),
menus on other arrows, Electron, CEF, Flutter and Tauri pages, what apps
report to Now Playing, and the Now Playing panel.

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
./playercheck --now-playing-reasons /Applications/Spotify.app   # why it can be in Now Playing, its framework and switches
./playercheck --launch-option Deezer     # the launch option it needs (Electron's apps) and whether it runs with it
./playercheck --relaunch Deezer          # quits it, then opens it again with that option, in the background
./playercheck --window-state Deezer      # the state its window is in now: visible, covered, on another desktop, …
```

The options may come before or after the app's name. The code is split by
subject: `main.swift` runs the steps in the report's order, and each
file holds one subject (`Scripting`, `Menu`, `Page`, `WindowStates`,
`Signs`, `PressTest`, `Report`, …).

## Permissions

Whatever runs it (Terminal, or Player Check) needs:
- **Accessibility**, for the menu, the page and the Now Playing panel, and
  to put the app's window in each state (pointer and keyboard events for
  the desktops).
- **Audio Recording**, to measure how loud the app is, as AutoHush does,
  and to keep it muted through a test; macOS shows its recording indicator
  meanwhile.
- **Automation** for the app, when it has AppleScript play or pause.

A test asks for all of them first (its **Permissions** section), before it
does anything else: macOS asks for any not decided yet. Without all of
them it stops there with "Not checked: … needs …" and exit status 3, with
no window moved and nothing pressed. An app that doesn't answer whether
it may be controlled (one still starting) is asked again for up to 20 s,
and the check stops the same way, saying so, if it never answers.
`--read-only`, `--play` and `--pause` ask nothing up front.

**The app is muted through a test**, behind a muted process tap, as
AutoHush mutes a web app's ad: nothing reaches the speakers, while every
other tap, its level's included, still hears it, and the app doesn't know.
A process it starts later is muted within 0.1 s, a set that can't be tapped
yet is tried again every half second, and the report says when it couldn't
be muted. The tap ends with the tool, so a stop or a crash lets it be heard
again. A Chromium browser's web app plays through its browser, so the whole
browser is muted, its tabs and other web apps too.

## What a check does

Each step is a section of the report, in this order:

1. **Scripting Dictionary:** its `.sdef` (or, while it runs, what `sdef`
   prints): play and pause commands, `player state`, `sound volume`.
2. **Permissions** (a test only): above.
3. **Playback Menu:** the menu with Play/Pause first and ⌘← ⌘→, as
   AutoHush finds it, else one whose first item is on Space with other
   arrows (Deezer's), and the app's own words for Play and Pause.
4. **Sound and Now Playing:** its sound output, its level, its keep-awake
   assertions, and whether it's the Now Playing app.
5. **Playing** (a test only): the test needs the app playing. If it isn't,
   it asks (“waiting: start playing something in …”) and goes on as soon
   as it plays, up to 2 minutes; if it doesn't, the check stops, with
   nothing moved or pressed. Moving the window comes only after this.
6. **Window States** (a test only): the window is put in the first state,
   visible on this desktop.
7. **Page Buttons:** its page's Play/Pause, read in view (a Chromium page
   is built and kept current only in view). An app with nothing to press
   but its page has its page read before step 5, where it is, so one with
   nothing to press isn't asked to play or moved.
8. **Press Test:** each way, paused and played again, in each window state.
9. **Ways to Control It:** a checklist: ✓ worked in every window state
   tested, ⚠ in some (the states where it failed, and why, under it), ✗ in
   none or not there, ? found but not tried, – not checked.
10. **Verdict:** which kind of player it would be.

## The ways

1. **AppleScript:** its pause and play commands (Spotify's), else commands
   named so, else one that toggles (playpause, VLC's play); to its
   documents when they act on one (QuickTime Player's). Sent as Apple
   events as AutoHush sends them. Its volume is checked once, while paused:
   set one step away, read back, put back.
2. **Its playback menu's first item.**
3. **Its page's Pause, then Play.** The player bar's button: named Play or
   Pause, in sight, not covered, with a slider around it. The button whose
   words change at the first pause is learned, as AutoHush learns a web
   app's; when nothing else can pause it and no button is named so, the
   check asks whoever runs it to pause the app (“waiting: pause …
   yourself”) and learns from that. A button the site disabled (an ad) is
   never pressed.
4. **Its row in the menu bar's Now Playing panel:** the panel opens for
   about half a second. Its rows don't name their apps, so the app's row is
   the one showing its song (from its windows' titles, its page's player
   bar or its AppleScript current track), else the row it changed with
   before, else, pausing, the only one playing while the app holds Now
   Playing; a row chosen by memory is confirmed by the app itself.

A way that leaves the app paused is followed by playing it again by a way
that worked, before anyone is asked; a track that ends during a trial is
tested again. The keyboard's Play/Pause key isn't a way: macOS sends it
only to the Now Playing app, which AutoHush can't choose.

## Whether it plays

A pause or a play is judged by the surest sign the app showed before it:
its AppleScript state, what it reports to Now Playing (from macOS's log,
administrators only), its page's word (only while current: a WebKit page's
anywhere, a Chromium or Flutter page's only on screen), its level, its
keep-awake assertion, its menu's state; else its menu's word changing or
its sound. A Chromium browser's web app has no level (its sound is the
browser's, all its pages together); its keep-awake sign counts the
browser's "Playing audio" assertions instead (below). Its state notification (`<bundle ID>.PlaybackStateChanged`,
`.playerInfo`, …) confirms too, and the verdict names the one that
announced both.

## Pages kept out of Accessibility

| Framework | Its interface | Switches tried, in turn |
|---|---|---|
| Electron (Deezer, TIDAL) | a web page | `AXManualAccessibility` (Electron's) |
| Chromium Embedded Framework (Spotify) | a web page | Electron's, then `AXEnhancedUserInterface` (VoiceOver's) |
| Flutter (Spotube) | the window's own elements | `AXEnhancedUserInterface` |

| A Chromium browser's web app (Chrome's, Brave's) | a web page, served by the browser | `AXEnhancedUserInterface`, set on the browser |
A switch the tool turned on is turned back off at the end (one found on is
set back on). When no switch shows the page in 4 s, a check brings the app
forward a moment, once; a press never does. Electron takes presses only
2 s after its switch goes on, so a press waits for that. Chromium treats
a page whose window is fully out of view as hidden: no page is built, and
presses are lost. Opened with `--disable-backgrounding-occluded-windows`,
an Electron app's page takes presses covered and on another desktop
(`--relaunch` opens it so); minimized or hidden, still not.

## Window states
A Chromium browser's web app is a launcher in `~/Applications/<Browser>
Apps.localized/` whose Info.plist names its site (`CrAppModeShortcutURL`)
and its browser (`CrBundleIdentifier`). Its window is its own, but the
page in it is the browser's: the switch goes on the browser, for all its
windows and tabs, and the browser takes presses 2 s after it (a press
waits). Set on the web app, or read without it (the page shows once
anything asked the browser for it), presses are silently ignored. The
browser makes a page pressable only while its window can be seen: turned
on then and kept on, presses take in every state (hidden or minimized, its
word lags); turned on for each press, as this tool's presses and trials
do, they fail minimized or hidden. Since Chromium 130 it reports to Now
Playing as itself, with its own row in the panel. Its sound and keep-awake
assertions are the browser's, shared with its tabs: the browser holds one
"Playing audio" assertion per playing page (a tab, a call, another web
app, any profile), so the check counts them once the web app plays, and
one more or fewer than its other pages' tells whether it plays; another
page starting or stopping meanwhile makes that unclear (said).


Each way is tried with the app's main window in each of these states:

| State | How the tool puts it there |
|---|---|
| visible | shown, on this desktop; if the window it was run from covers it, that one moves aside |
| covered | a window of the tool's own over it |
| on another desktop | dragged there, as a person drags a window, with Control-→ |
| covered on another desktop | the tool's window over it there |
| full screen | `AXFullScreen` |
| minimized | `AXMinimized` |
| hidden | the app hidden, as ⌘H hides it |

Its state is read once the check has come back to the app it was run
from (Player Check, or the app in front when it started), from that app's
desktop: whoever started the app playing may have gone to the app's own
desktop for it. Coming back, the tool shows that desktop with Control-arrow
when bringing the app forward doesn't. Before each state, the window is
brought back to visible (a window on another desktop that Accessibility
can't reach is reached by showing its desktop with Control-arrow), and the
state is read back: one it doesn't reach is
“not tested”, with why. At the end it's put back as it was: its state,
place and desktop (a minimized or hidden window on its own desktop), the
windows of other apps that covered it raised again, and the app it was run
from in front. With no window open the ways are tried once; with one
desktop, the two desktop states aren't tested.

## Stopping

Ctrl-C, Player Check's Stop, or whoever ran it ending (its window closed,
a crash): while the window is away from where it was, or in a trial, the
check finishes the step under way (a trial plays the app again first; a
move; the page read; a wait ends at once), then puts the window back and
stops; before anything moved, it stops at once. Either way the switches it
turned on are set back, and the app that was in front comes back.

## Playing and pausing (`--play`, `--pause`)

The checks run silently, then it plays or pauses by `--via`'s way, else
tries AppleScript, the page's button, then the menu (the panel only when
named), and prints one line: what it did, that it was that way already, or
why none worked (exit status 0 or 1). Each press is confirmed within 6 s.
With `--via`, only what that way needs is read, so a press starts sooner.

## What's kept

- `~/Library/Caches/PlayerCheck/button-places.json`, per app: where the
  page's player bar button sits, its learned recipe (words and places, as
  AutoHush's `PlayPauseRecipe`), and its Now Playing panel row.
- `~/Library/Caches/PlayerCheck/words.json`: each app's own words for Play
  and Pause, per copy and version.
- `~/Library/Logs/PlayerCheck/`: every check, press and relaunch, whole,
  with each line's time (the last 50). `--now-playing-list`,
  `--now-playing-reasons`, `--launch-option` and `--window-state` aren't
  logged: Player Check asks them often.

## The apps in Now Playing (`--now-playing-list`)

One tab-separated line per app macOS keeps in Now Playing: bundle ID,
process, last state (Playing, Paused, Stopped, or Registered: never said it
plays), 1 for the active one, name; then `#active` and its process. Since
macOS 15.4 an app without Apple's entitlement can't ask MediaRemote for
that list, so it's read from what MediaRemote's daemon writes in macOS's
log: only administrators can read it, and its wording isn't an API.

`--now-playing-reasons` gives, per app, why it can be in Now Playing (the
frameworks its binaries link: MediaPlayer, through Electron or CEF too;
MediaRemote; AVKit; WebKit; Chromium, for a browser's web app), the framework
that hides its interface, and
the switches a check turns on, so Player Check lists apps by the same rule.

## Example

Spotify, playing at the start (trials shortened):

```
Spotify 1.3.4.258 (com.spotify.client)
Scripting Dictionary
  commands: pause (spfyPaus), playpause (spfyPlPs), play (spfyPlay)
  player state (pPlS): yes, values stopped/playing/paused: yes
  sound volume (pVol): yes, so it can fade
  pause and play share suite “spfy”
Permissions
  Accessibility: allowed
  Audio Recording: allowed
  Automation for Spotify: allowed
  Spotify is muted until the check ends: you won't hear it, while its sound still reaches what measures it
Playback Menu
  “Playback”: first item “Pause”, enabled
Sound and Now Playing
  sound output running now: Spotify (com.spotify.client, pid 401)
  heard now: yes
  Now Playing: this app (until another app reports playing)
Playing
  it plays: testing
Window States
  each way is tested with its window in each state: visible, covered, on another desktop, covered on another desktop, full screen, minimized, hidden; it's put back as it is now: visible
  visible now: its page is read in view, and the test starts there
Page Buttons
  built with Chromium (CEF): its page shows once a switch for assistive tools is on (Electron's switch, else VoiceOver's switch)
  VoiceOver's switch on: its page showed 167 buttons after 0.4 s (one read, as AutoHush reads a web app: 35 ms)
  Play/Pause: “Pause”, 56 pt from the window's bottom, with a player's slider around it
Press Test
  State 1 of 7: visible
  by script (pause, play): before, menu “Pause”, state playing, page “Pause”, sound on, heard
    after the pause: menu “Play”, state paused, page “Pause”, sound on → it paused
    announced: paused (com.spotify.client.PlaybackStateChanged)
    volume (“sound volume”): 100; set to 99, it reads 98: reads 1 less than set (as Spotify, one less): the profile needs readVolume; put back to 100
    after playing again: menu “Pause”, state playing, page “Play”, sound on → it plays
  …
  its window put back as it was (visible)
  Spotify unmuted: the test is over

Ways to Control It
  ✓ AppleScript: “pause” and “play” paused and played it, as Spotify and Apple Music (all 7 window states)
  ✓ Playback menu “Playback”: pressing it paused and played it (all 7 window states)
  ⚠ Page button, with VoiceOver's switch on: “Pause” / “Play”, learned as AutoHush learns it: pressing it paused and played it, in 2 of 7 window states
      ✗ on another desktop: its page didn't show with VoiceOver's switch on
      …
  ✓ Now Playing panel: pressing its row (“I Worry Too Much, Egotist – I Worry Too Much”) paused and played it (all 7 window states)

Verdict
  Scriptable, like Spotify and Apple Music: a ScriptablePlayerProfile with suite fourCharCode("spfy").
  …
```
