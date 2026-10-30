# Glossary

The words AutoHush's code and docs use for its parts, so that each name
means one thing. Code names are in backticks. See
[DEVELOPMENT.md](DEVELOPMENT.md) for how the parts work together.

**Chosen player**: the media player the user picked for AutoHush to pause
and resume: an app such as Spotify, a Safari web app, or an app added with
Add an App (a checked app). There is one at a time, or none until the user
picks one. In the code it's a `MusicPlayer`.
_Avoid_: music app, target.

**Player session** (`PlayerSession`): the chosen player from its start
until AutoHush quits. It starts the player, tries again after a failed
start, checks again that AutoHush may still control it, runs its
monitoring with the monitoring settings, and keeps the held pauses and the
hand-over. Choosing a player, noticing whether it's installed, and
learning a web app's controls happen outside it and call it. The menu and
Settings show its state.

**Start**: checking that AutoHush may control the chosen player, then
starting its monitoring. A start that fails says why in the health, and is
tried again by itself. One that finds the player not running still starts
its monitoring while Auto-Pause is on, only to list the apps playing (at
the idle rate, as it can pause nothing), until the player opens. _Avoid_:
bootstrap.

**Health** (`AppHealthState`): whether the chosen player's monitoring
runs, and if not, why: starting, ready, not running or not installed,
retrying, a permission needed, or failed. With no player chosen, it asks
for one. The menu's status line says it. _Avoid_: status (that's
everything the menu and the windows show, `AppStatus`).

**Status** (`AppStatus`): everything the menu and the windows show about
AutoHush, as one value: the chosen player and the players to choose from,
the health, the music's state, the apps playing, seen and ignored,
Auto-Pause, learning, an update found. Its rules turn it into words and
icons: the status line, its orange, the menu bar icon.

**App state** (`AppState`): the one place the status is kept. AppDelegate
writes it; Settings and the welcome, learning and Add a Web App windows
read it part by part, each window drawn again only when a part it shows
changes; the menu gets a copy each time it changes (its card follows it
while open, its rows when it next opens). Add an App's windows (the window,
Choose an App and the check's panel) read their own model instead,
`AddAppModel`: its steps, from choosing the app to Use, which Add an App's
own module (`AddAppFeature`) holds with them. _Avoid_: model
(Settings' model is the windows' own: what they alone show, and their
actions).

**Learning session** (`LearningSession`): learning the chosen web app's
controls with the user, from choosing it until it's learned, and again
when asked. It follows the player's learning status, takes the user's
steps (It's Playing, Try Again, Pause It Yourself, It's Paused), and counts
down the minute the user has to pause it, with a note when a step can't be
taken. The windows that show the steps read it from the app state.
_Avoid_: learner (that's the player's own part, which reads the page).

**Window watch** (`WindowWatch`): while AutoHush's windows are open,
follows once a second what they show that macOS doesn't announce: the
permissions, whether notifications are on, launch at login, Diagnostics,
and the players installed while none is chosen (once one is, the
Applications folders are watched instead). Each window says what it
needs; the watch refreshes only what the open ones need, and stops when
none is open.

**User settings** (`UserSettings`): the user's own settings and what
follows from them: Auto-Pause and its snooze, the apps ignored and the
apps seen, the timings, the detection method, the order of Settings' list
of apps. It stores them, and the monitoring, the menu and Settings show
them: Settings reads what only it shows (the timings, detection, the
list's order) here, the rest from the app state. _Avoid_: preferences
(that's where they're stored, `Preferences`).

**Sound Sources** (`SoundSourcesSettingsView`, the page
`SettingsPage.soundSources`, its list `AppListModel`):
Settings' page of the apps heard playing sound, each switched to pause
the chosen player or to be ignored, in the order the user chose
(`AppListOrder`). In the menu, the same apps are under Playing Now,
Recently Played and Ignored Apps.
_Avoid_: the Apps page or tab (its name until 2026-10-19).

**Monitoring** (`MonitoringPipeline`): the engine of one start. It follows
which apps play, decides when to pause and resume the player, and does it.
Each start makes a new one, and it stops as a whole.

**Monitoring settings** (`MonitoringSettings`): what the monitoring
follows from the user's settings: whether Auto-Pause is on now, the
ignored apps, the timings, and the detection method (normal or AntiDot
mode).

**Held pause** (`HeldPauses`): a pause AutoHush made on a player that the
user then left for another. That player's monitoring runs on only to end
the pause, as it would have, and stops once the player has played again
and faded back in, or the user takes it over.

**Hand-over** (`PauseHandover`): the pauses AutoHush holds as it quits,
written down so that the AutoHush opened next (an update, a reopen) ends
them. One older than a minute is ignored.

**Take over, take back**: a monitoring that starts treats a pause as its
own. It takes over a pause from the hand-over, and takes back a held pause
when its player is chosen again.

**Heard, silent** (`PlayerHearing`): what the player's own sound says,
measured through a tap on it: heard lately, or measured long enough with
nothing heard. In AntiDot mode nothing is measured, so neither can be told.

**Playing silently** (`playsSilently`): the player says it plays here, but
isn't heard, like a muted trailer. AutoHush leaves it alone, and the menu
says "Playing silently".

**The user's play** (`PlayerInput`): a key pressed or a click while the
player was already the frontmost app, or a click in one of its own windows
while it isn't (its menu bar icon, its menu: `PlayerWindowClicks`), just
before it played. A play after
it is the user's, so AutoHush doesn't pause it again; without it, a start
is the app's own (an autoplay, the next trailer). Media keys and events
other apps post don't count.

**Restart** (`watchRestart`, `handleRestart`): the player playing again
while AutoHush holds its pause: the pause didn't take, or it started again
by itself. It's muted until the pause is over (unless it's the user's
play); one that can't be muted plays on, and its pause failed.

**Muted instead of paused** (`PauseMute`): AutoHush's mute of the player,
standing for its pause after a restart. It's lifted at the resume; once the
player is paused under it, it's kept until the player plays again, so a
restart by itself is never heard.

**Quiet listen** (`quietProcesses`, `quietListenInterval`): an app silent
for 10 seconds has its tap released, so it's quiet and no longer counts as
playing. Every 30 seconds while the player plays, and once before each
resume, AutoHush listens to the quiet apps it doesn't ignore for half a
second, to hear whether one plays again.

**Shortcuts action** (`SetAutoPauseIntent`, `TurnOffAutoPauseForIntent`,
`GetAutoPauseIntent`): something the Shortcuts app can ask AutoHush to do
with Auto-Pause: set it on or off or toggle it, turn it off for one of the
menu's durations, or tell whether it's on now. It acts on the running
AutoHush through `AutoPauseControlling`. _Avoid_: intent (Apple's name for
the code behind one, an App Intent).

**App Shortcut** (`AutoHushShortcuts`): a ready-made shortcut that runs a
Shortcuts action with nothing to set up, offered in Shortcuts, Spotlight
and Siri. AutoHush has two: turn Auto-Pause off, and turn it on. Each
phrase names the app, as Siri requires.

**Focus filter** (`AutoPauseFocusFilter`): a Focus's setting for
Auto-Pause, On or Off, added in System Settings → Focus. While that Focus
is on, Auto-Pause follows it; when it ends, `FocusAutoPause` puts back how
Auto-Pause was, unless the user changed it meanwhile.

**Check** (playercheck, `PlayerCheckRun`): finding out how AutoHush can
pause and play an app it has no support of its own for: its AppleScript,
its playback menu, its page's Play/Pause and its row in the Now Playing
panel are each tried, pausing the app and playing it again, with its window
in each window state. AutoHush runs it in its helper, playercheck
(`Contents/Helpers`), from Add an App; Player Check runs the same in a
window. _Avoid_: test (that's the code's tests), scan.

**Way** (`PlayerSetup.Way`, `CheckResult.WayKind`): one means of pausing
and playing an app: its script, its menu, its page or the panel; or, when
none works and the user chooses it, muting it while other apps play
(`.mute`, its state kept by `MutedAppState`). A check says how each did: in
every window state, in some, in none (or with its windows closed), not
there, not tried or not checked.
_Avoid_: method.

**Window state**: where an app's window is while a check presses it: in
view, covered, on another desktop, covered there, full screen,
minimized or hidden. A way that works in every state works wherever the
user leaves the window. The check's **trip** (`WindowState.trip`) moves the
window through these 7, in the order that takes the fewest moves. **Windows closed** is a state of its own: no
window on screen or within reach (a menu bar player's), where each way
that needs none is tried once.

**Checked app** (`AddedAppPlayer`, kind `.checkedApp`): an app added with
Add an App, offered under "Other Apps" with its "Checked by you" badge, and
controlled the one way the user chose among those its check found (a setup
kept before that choice may hold several, a press handed to the next when
one fails): pressed by it (`CheckedPlayer`), or muted instead of paused
(`MutedApp`). That way is kept as its **player setup** (`PlayerSetup`).
_Avoid_: custom player.

**Needs reopening** (`MusicPlayer.needsReopen`): the chosen player runs,
but was opened without what it needs to be controlled wherever its window
is (an Electron app's launch option); `reopen()` quits it and opens it
again as it needs. The menu and Settings → General say so, with a Reopen
button; a player the user chose to reopen always (`ReopenChoices`) is
reopened without asking.
