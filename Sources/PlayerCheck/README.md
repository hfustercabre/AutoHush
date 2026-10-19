# PlayerCheck

Says whether AutoHush could control an app (pause it while another app
plays, then play it again), and which kind of player it would be, so it can
be added as DEVELOPMENT.md's [Adding a media
player](../../DEVELOPMENT.md#architecture) says. It reads the app from outside,
as AutoHush would, then tests each way to control it, with the app's window
in each state a player's window can be in. AutoHush itself runs it, as a
helper inside AutoHush.app (`Contents/Helpers/playercheck`), for **Add an
App…**, and keeps what worked as the app's setup. [Player Check](../../Tools/PlayerCheckApp)
does all of this from a window.

It's a target of AutoHush's package and runs AutoHush's own code wherever
the two do the same thing (Apple events, scripted states, playback menus and
their words, learning a page's Play/Pause, sound, windows on other
desktops, Now Playing), so what it finds holds for AutoHush. AutoHush
controls an added app the way the user chose among those the check found
(`CheckedPlayer`): players of documents (as QuickTime Player, now built in), Electron, CEF,
Flutter and Tauri pages and Chromium browsers' web apps, what apps report
to Now Playing, and the Now Playing panel. The check keeps its own code for those, since it reports
more than AutoHush needs: each try, in each window state, and why it
failed.

## Use

```bash
swift build -c release --product playercheck   # from the repository; writes .build/release/playercheck
cd .build/release
./playercheck Spotify                    # by name, bundle ID or path: checks it and tests each way
./playercheck Spotify --block-input      # the same, blocking clicks, scrolling and keys while it moves the window and presses
./playercheck Spotify --read-only        # checks it without pressing anything
./playercheck Deezer --block-input --partial --result out.json --logs ~/Library/Logs/AutoHush/Checks \
    --caches ~/Library/Caches/com.autohush.AutoHush/PlayerCheck
                                         # as Add an App runs it: goes on without Audio Recording or Automation
                                         # (only Accessibility is needed), writes what it found as JSON (CheckResult),
                                         # its log and its caches in those folders; in AntiDot mode, --no-taps too
./playercheck Spotify --developer        # the verdict also says how a built-in player of its kind would be made
                                         # (AutoHush's own types; the Player Check app passes it, Add an App doesn't)
./playercheck Spotify --pause            # just pauses it (--play: plays it), by the first way that works
./playercheck Deezer --play --via page   # by that way only: script, menu, page or panel
./playercheck --now-playing-list         # the apps macOS keeps in Now Playing now (from the log since the Mac started)
./playercheck --now-playing-list 24      # the same, from the last 24 hours' log only (as Add an App asks)
./playercheck --now-playing-list --since 1760180000   # only what changed since then (apps gone: Removed)
./playercheck --now-playing-reasons /Applications/Spotify.app   # why it can be in Now Playing, its framework and switches
./playercheck --launch-option Deezer     # the launch option it needs (Electron's apps) and whether it runs with it
./playercheck --relaunch Deezer          # quits it, then opens it again with that option, in the background
                                         # (Add an App's Reopen step, which passes --logs and --caches too)
./playercheck --window-state Deezer      # the state its window is in now: visible, covered, on another desktop, …
```

The options may come before or after the app's name. Its code names no
player (a test holds it to that): the report says what kind of player an
app could be in the words of AutoHush's kinds (“as the supported scriptable
players are”), and only the names of the app it checks, as read from it.

The code is split by
subject: `main.swift` runs the steps in the report's order, and each
file holds one subject (`Scripting`, `Menu`, `Page`, `WindowStates`,
`Signs`, `PressTest`, `Report`, …). `Kit/` is PlayerCheckKit, the parts
that need no app to check (its command line, an app's binaries, what the
log leaves out, what's kept, how a press is judged, how a stop is handled,
what the check found made into its result), so tests reach them.
`Tests/PlayerCheckTests` tests the tool itself, run as a read-only check
of Calculator (`argumentsForTests`): its command line, its report's words,
the apps' interfaces and its log. What reads, moves or presses another app
is checked live.

## Permissions

Whatever runs it (AutoHush, whose permissions its helper uses; Terminal;
or Player Check) needs:
- **Accessibility**, for the menu, the page and the Now Playing panel, to
  put the app's window in each state (pointer and keyboard events for the
  desktops), and, with `--block-input`, to block the user's input meanwhile
  (an active event tap).
- **Audio Recording**, to measure how loud the app is, as AutoHush does,
  and to keep it muted through a test; macOS shows its recording indicator
  meanwhile.
- **Automation** for the app, when it has AppleScript play or pause.

A test asks for all of them first (its **Permissions** section), before it
does anything else: macOS asks for any not decided yet. Without all of them
it stops there with "Not checked: … needs …" and exit status 3, with no
window moved and nothing pressed. With `--partial`, which AutoHush passes
(its Add an App window has said what's missing), only Accessibility is
needed: without Audio Recording the app isn't muted by this tool (run by Add
an App, AutoHush mutes the Mac's output meanwhile instead) and whether it
plays is told by other signs, and without Automation its AppleScript isn't
tried.
With `--no-taps`, which AutoHush passes in AntiDot mode, no sound is tapped
at all, as without Audio Recording. An app that doesn't answer whether it
may be controlled (one still starting) is asked again for up to 20 s, and
the check stops the same way, saying so, if it never answers.
`--read-only`, `--play` and `--pause` ask nothing up front.

**The app is muted through a test** (with Audio Recording, and without
`--no-taps`; else, run by Add an App, AutoHush mutes the Mac's output
instead, `OutputMute`), behind a muted process tap, as AutoHush mutes a web
app's ad:
nothing reaches the speakers, while every other tap, its level's included,
still hears it, and the app doesn't know. A process it starts later is
muted within 0.1 s, a set that can't be tapped yet is tried again every
half second, and the report says when it couldn't be muted. The tap ends
with the tool, so a stop or a crash lets it be heard again. A Chromium
browser's web app plays through its browser, so the whole browser is muted,
its tabs and other web apps too.

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
   visible on this desktop. With `--block-input` (AutoHush's and Player
   Check's), the user's clicks, scrolling and keys are blocked from here
   until the window is put back, apart from the requests; Escape stops the
   check (below).
7. **Page Buttons:** its page's Play/Pause, read in view (a Chromium page
   is built and kept current only in view). An app with nothing to press
   but its page has its page read before step 5, where it is, so one with
   nothing to press isn't asked to play or moved.
8. **Press Test:** each way, paused and played again, in each window state.
9. **Ways to Control It:** a checklist: ✓ worked in every window state
   tested, ⚠ in some (the states where it failed, and why, under it), ✗ in
   none or not there, ? found but not tried, – not checked.
10. **Verdict:** which kind of player it would be. With `--developer`, also
    how a built-in player of that kind would be made, in AutoHush's own
    types (a `ScriptablePlayerProfile` with its suite and state
    notification, a `MenuPlayerProfile`, a player type of its own, a tested
    web app); a line elsewhere that names one (a profile's `readVolume`)
    gets that part only then too. Add an App… doesn't pass it, so its
    report ends with what the check found.

## The ways

1. **AppleScript:** its pause and play commands in its own suite, else
   commands named so, else one that toggles (playpause, or a play that
   toggles); to its documents when they act on one. Chosen and sent as
   Apple events as AutoHush chooses and sends them (`ScriptSetup`). Its volume is checked once, while paused:
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
   Playing, as AutoHush chooses it (`PanelRows.row`); a row chosen by
   memory is confirmed by the app itself. Where its song showed besides its
   windows' titles (its player bar, its current track) goes in its result
   with the panel (`PanelClues`), so AutoHush reads the same there. The
   panel's icon is found in the menu bar's own windows, whatever covers it.
   With Now Playing hidden in the menu bar, the tool shows it for the
   moment of a press, then puts the setting back (unless the user changed
   it meanwhile), as AutoHush does; one left shown by a check cut short is
   put back by AutoHush at its next start, or by the tool as it stops. A
   row that never shows whether its app plays (it always says paused) is
   pressed as a toggle, when the app's sound says otherwise.

A way that leaves the app paused is followed by playing it again by a way
that worked, before anyone is asked; a track that ends during a trial is
tested again. The keyboard's Play/Pause key isn't a way: macOS sends it
only to the Now Playing app, which AutoHush can't choose.

## Whether it plays

A pause or a play is judged by the surest sign the app showed before it: its
AppleScript state (read where AutoHush reads it: its `player state` only
with the three standard values, else its `playing` flag, else its
documents'), what it reports to Now Playing (from macOS's log,
administrators only), its page's word (only while current: a WebKit page's
anywhere, a Chromium or Flutter page's only on screen), its level, its
keep-awake assertion, its menu's state; else its menu's word changing or its
sound. A Now Playing row that doesn't follow its app is judged by the
app's level alone. A Chromium browser's web app has no level (its sound is
the browser's, all its pages together); its keep-awake sign counts the
browser's "Playing audio" assertions instead (below). Its state
notification (`<bundle ID>.PlaybackStateChanged`, `.playerInfo`, …)
confirms too, and the verdict names the one that announced both (with
`--developer`).

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
app, any profile). So the check counts the other pages' (before it
waits for the web app to play; or, found playing already, all of them
but one), and one more than theirs says it plays; another page starting
or stopping meanwhile makes that unclear (said). Its last-resort sound
sign is the browser's own output.

## Window states

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

Its state is read once the check has come back to the app it was run from
(AutoHush or Player Check, or the app in front when it started), from that
app's desktop: whoever started the app playing may have gone to the app's
own desktop for it. Coming back, the tool shows that desktop with
Control-arrow when bringing the app forward doesn't. Before each state, the
window is brought back to visible (a window on another desktop that
Accessibility can't reach is reached by showing its desktop with
Control-arrow), and the state is read back: one it doesn't reach is “not
tested”, with why. At the end it's put back as it was: its state, place and
desktop (a minimized or hidden window on its own desktop), the windows of
other apps that covered it raised again, and the app it was run from in
front. With no window open the ways are tried once; with one desktop, the
two desktop states aren't tested.

## Blocking the mouse and keyboard (`--block-input`)

The drags to another desktop are made of pointer and keyboard events, and a
click or a key from whoever runs the check spoils them (or a trial). With
`--block-input` (AutoHush and Player Check always pass it), from the first
move of the window until it's put back, an active event tap where input
enters the window server drops their keys (modifiers, media and function
keys too), clicks, drags, scrolling and gestures. It lets through:

- the tool's own events, marked in `kCGEventSourceUserData`;
- the pointer's moves, except during a drag, which they would carry off;
- clicks on the panel of whoever runs it, AutoHush's or Player Check's (the
  parent process's windows above the ordinary ones that don't cover a whole
  display: not the shade it dims the screen with meanwhile), so its Stop
  works; during a drag, a click there can't reach it without letting go of
  the window, so it's taken as Stop;
- Escape, which stops the check as Stop does.

The block is lifted while the check asks something ("waiting: …"). If the
check writes nothing for a minute, it's lifted and the check stops at its
next step, rather than drag the window with the user's input free. The tap
runs on a thread of its own and goes with the process, however it ends.
When the block ends, the modifiers are posted as they are on the keyboard,
so no app keeps one held. Input other tools post where hardware input
enters (the HID event tap) is blocked too meanwhile; what they post further
on (the session's event tap, or to one app) never reaches the block. From a
shell it's off by default: there's no panel there, and Ctrl-C would be
blocked.

## Stopping

Ctrl-C, the panel's Stop (AutoHush's or Player Check's), Escape while input
is blocked, or whoever ran it ending (its window closed, a crash): while
the window is away from where it was, or in a trial, the check finishes the
step under way (a trial plays the app again first; a move; the page read; a
wait ends at once), then puts the window back and stops; before anything
moved, it stops at once. Either way the switches it turned on are set back,
the app that was in front comes back, and a Now Playing shown for a press
is hidden again.

## Playing and pausing (`--play`, `--pause`)

The checks run silently, then it plays or pauses by `--via`'s way, else
tries AppleScript, the page's button, then the menu (the panel only when
named), and prints one line: what it did, that it was that way already, or
why none worked (exit status 0 or 1). Each press is confirmed within 6 s.
With `--via`, only what that way needs is read, so a press starts sooner.

## What's kept

In `~/Library/Caches/PlayerCheck/`, or `--caches`' folder (AutoHush's
checks use `~/Library/Caches/com.autohush.AutoHush/PlayerCheck`):

- `button-places.json`, per app: where the page's player bar button sits,
  its learned recipe (words and places, as AutoHush's `PlayPauseRecipe`),
  and its Now Playing panel row.
- `words.json`: each app's own words for Play and Pause, per copy and
  version.

While a hidden Now Playing is shown for a press, the setting to put back is
kept too, where AutoHush's next start finds it, until it's put back.

In `~/Library/Logs/PlayerCheck/`, or `--logs`' folder (AutoHush's checks
use `~/Library/Logs/AutoHush/Checks`): every check, press and relaunch,
whole, with each line's time (its own last 50: older ones go to the
Trash, and other files in the folder are left alone). The log, like the report,
writes the home folder as `~`, so it never holds the Mac account's name,
and leaves out what was playing (`PrivateText`): a page's button is named
by its Play or Pause word only, a panel row by its place and what told it
was the app's, and window titles and the track an app's AppleScript
reports aren't shown.
`--now-playing-list`, `--now-playing-reasons`, `--launch-option` and
`--window-state` aren't logged: they're asked often. AutoHush's Show Log
opens only a log named as the tool names them (`RunLogName`).

## Its interface

Whoever runs it (AutoHush's Add an App…, the Player Check app) uses the
same types the tool does, in `PlayerCheckKit` (its `Kit/` folder): the
flags (`CommandLineOptions`, with the arguments of a check, a press and each
question), the exit statuses (`CheckExitStatus`: 0, 1, 3 for a missing
permission, 128 + the signal for a stop), and each one-line answer
(`NowPlayingListLine`, `NowPlayingReasonsLine`, `LaunchOptionAnswer`,
`WindowStateAnswer`), written and read by the same code. The report's lines
they follow (the requests, the window states and trials, the input block,
the permissions, the ways' checklist) are `CheckReportLine`s, and what a
check found is `CheckResult` (`--result`), both in `CheckedPlayers`.

## The apps in Now Playing (`--now-playing-list`)

One tab-separated line per app macOS keeps in Now Playing: bundle ID,
process, last state (Playing, Paused, Stopped, or Registered: never said it
plays), 1 for the active one, name; then `#active` and its process. Since
macOS 15.4 an app without Apple's entitlement can't ask MediaRemote for
that list, so it's read from what MediaRemote's daemon writes in macOS's
log: only administrators can read it, and its wording isn't an API.

`--now-playing-reasons` gives, per app, why it can be in Now Playing (the
frameworks its binaries link: MediaPlayer, through Electron or CEF too;
MediaRemote; AVKit; WebKit; Chromium, for a browser's web app), the
framework that hides its interface, and the switches a check turns on, so
Player Check lists apps by the same rule.

## Example

Spotify, playing at the start, checked with `--developer` (trials shortened):

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
    volume (“sound volume”): 100; set to 99, it reads 98: reads 1 less than set: a ScriptablePlayerProfile needs readVolume; put back to 100
    after playing again: menu “Pause”, state playing, page “Play”, sound on → it plays
  …
  its window put back as it was (visible)
  Spotify unmuted: the test is over

Ways to Control It
  ✓ AppleScript: “pause” and “play” paused and played it, as the supported scriptable players do (all 7 window states)
  ✓ Playback menu “Playback”: pressing it paused and played it (all 7 window states)
  ⚠ Page button, with VoiceOver's switch on: “Pause” / “Play”, learned as AutoHush learns it: pressing it paused and played it, in 2 of 7 window states
      ✗ on another desktop: its page didn't show with VoiceOver's switch on
      …
  ✓ Now Playing panel: pressing its row (row 1 of 2, its song found in its windows' titles) paused and played it (all 7 window states)

Verdict
  A scriptable player, as the supported scriptable players are: its own pause and play, and its state.
  As a built-in player: a ScriptablePlayerProfile with suite fourCharCode("spfy").
  It has a volume, so it can fade.
  Measure its volume's curve: swift run measure-volume-curve com.spotify.client.
  State notification: com.spotify.client.PlaybackStateChanged, which announced each pause and play (the profile's stateNotification).
  …
```
