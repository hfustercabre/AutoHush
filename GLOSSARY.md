# Glossary

The words AutoHush's code and docs use for its parts, so that each name
means one thing. Code names are in backticks. See
[DEVELOPMENT.md](DEVELOPMENT.md) for how the parts work together.

**Chosen player**: the media player the user picked for AutoHush to pause
and resume: an app such as Spotify, or a Safari web app. There is one at a
time, or none until the user picks one. In the code it's a `MusicPlayer`.
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
tried again by itself. _Avoid_: bootstrap.

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
while open, its rows when it next opens). _Avoid_: model (Settings' model is the windows' own: what they
alone show, and their actions).

**Learning session** (`LearningSession`): learning the chosen web app's
controls with the user, from choosing it until it's learned, and again
when asked. It follows the player's learning status, takes the user's
steps (It's Playing, Try Again, Pause It Manually, It's Paused), and counts
down the minute the user has to pause it, with a note when a step can't be
taken. The windows that show the steps read it from the app state.
_Avoid_: learner (that's the player's own part, which reads the page).

**Window watch** (`WindowWatch`): while AutoHush's windows are open,
follows once a second what they show that macOS doesn't announce: the
players installed, the permissions, whether notifications are on, launch
at login, Diagnostics. Each window says what it needs; the watch refreshes
only what the open ones need, and stops when none is open.

**User settings** (`UserSettings`): the user's own settings and what
follows from them: Auto-Pause and its snooze, the apps ignored and the
apps seen, the timings, the detection method, the order of Settings' list
of apps. It stores them, and the monitoring, the menu and Settings show
them: Settings reads what only it shows (the timings, detection, the
list's order) here, the rest from the app state. _Avoid_: preferences
(that's where they're stored, `Preferences`).

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
