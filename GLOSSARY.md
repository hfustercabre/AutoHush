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
everything the menu shows, `AppStatus`).

**Monitoring** (`MonitoringPipeline`): the engine of one start. It follows
which apps play, decides when to pause and resume the player, and does it.
Each start makes a new one, and it stops as a whole.

**Monitoring settings** (`MonitoringSettings`): what the monitoring
follows from the user's settings: whether Auto-Pause is on now, the
ignored apps, the timings, and the detection method (normal or AntiDot
mode).

**Held pause** (`HeldPauses`): a pause AutoHush made on a player that the
user then left for another. That player's monitoring runs on only to end
the pause, as it would have, and stops once the player plays again or the
user takes it over.

**Hand-over** (`PauseHandover`): the pauses AutoHush holds as it quits,
written down so that the AutoHush opened next (an update, a reopen) ends
them. One older than a minute is ignored.

**Take over, take back**: a monitoring that starts treats a pause as its
own. It takes over a pause from the hand-over, and takes back a held pause
when its player is chosen again.
