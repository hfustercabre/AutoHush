# Player Check

A window over [PlayerCheck](../../Sources/PlayerCheck): it lists the apps on your Mac
that can be in macOS's Now Playing list, and checks the one you pick for
the ways AutoHush could control it. It can also play and pause the apps
with a known way, to try each way by hand.

```bash
sh Tools/PlayerCheckApp/build.sh              # writes "Player Check.app" here, with playercheck inside it
open "Player Check.app"
```

Both are products of AutoHush's package: the window (`PlayerCheckApp`, from
this folder) and playercheck (it runs AutoHush's own code for what the two
share). So `build.sh` runs `swift build -c release --product PlayerCheckApp`
and `--product playercheck` in the repository, then puts them in the app
with this folder's `Info.plist`; the first build compiles AutoHush's modules
and takes a few minutes. The window runs playercheck as AutoHush's Add an
App… does, through the same interface: its command line, exit statuses and
one-line answers (`PlayerCheckKit`), the report's lines and the progress they
show (`CheckReportLine`, `CheckProgress`), the same check panel
(`CheckPanel`), and the same runner (AutoHushKit's `ToolRun`). AutoHush.app
never includes it: no app target depends on `Tools/`, and
`Scripts/build-app.sh` builds only AutoHush and playercheck.

`build.sh` takes a folder to build into (the current one by default). The
app is signed ad hoc, for your own Mac, unless `SIGNING_IDENTITY` names a
code signing certificate in your keychain (for example "AutoHush
Self-Signed", made by `Scripts/create-signing-certificate.sh`):

```bash
SIGNING_IDENTITY="AutoHush Self-Signed" sh Tools/PlayerCheckApp/build.sh
```

macOS knows an ad hoc build by its content, so each rebuild is a new app
to it and loses its permissions; one signed with a certificate keeps them.

## Using it

- **The list:** the apps in `/Applications`, `~/Applications` (where Safari
  web apps are) and `/System/Applications`, subfolders included, that can be
  in Now Playing (see below). Those macOS lists in Now Playing right now
  come first, with their state: "Now Playing (Playing)" for the active one,
  "In Now Playing: Paused", or "Registered" for an app ready for it that
  never said it plays. A green dot: it's running. "checked": it has a
  finished check (kept between launches, in `~/Library/Application
  Support/Player Check/`; those from before the window states are dropped,
  as their ✓ meant one state). Search by name. The list of Now Playing apps
  is read in full when Player Check opens and when the arrow in the toolbar
  looks again; after a check or a Play/Pause, only what changed is read.
- **Checking:** choose an app, then **Check…**, and confirm. An app that
  isn't running is opened first, in the background (an Electron app with the
  launch option its page needs out of view, below). Before anything else,
  the check makes sure Player Check has every permission it needs
  (Accessibility, Audio Recording, and Automation for the app when it has
  AppleScript play or pause), and macOS asks for any not decided yet;
  without all of them it's cancelled before it does anything, and an orange
  warning says which is missing, with Open System Settings (the last
  finished check stays shown). An app that doesn't answer whether it may be
  controlled (it quit meanwhile; macOS itself waits for one still starting)
  cancels the check the same way, with no button, as there's no permission
  to allow. The app is muted all through the check (you don't
  hear it; Player Check still hears whether it plays) and heard again at the
  end; a Chromium browser's web app plays through its browser, so the whole
  browser is, its other tabs and web apps too. Then it makes sure the app
  plays: if it isn't playing, an orange request asks you to start it, and
  the check goes on by itself as soon as it plays (up to 2 minutes; if it
  doesn't, the check stops there, with nothing moved or pressed). Only then
  does anything move. The check tests each way to control it (AppleScript,
  its playback menu, its page's button and the menu bar's Now Playing
  panel, shown for a moment if you hid it), pausing the app and playing it
  again by each, with the app's window in each state a player's can be in
  while AutoHush controls it: visible, covered (Player Check puts a window
  of its own over it), on another desktop, covered there, full screen,
  minimized and hidden. Player Check moves the window there itself, starting
  by bringing it to visible on this desktop whatever state it's in, and
  comes back to the front before each state's trials; for the desktops it
  drags the window with the pointer and Control-arrow. So from the first
  move until the window is put back, your clicks, scrolling and keys are
  blocked (playercheck's `--block-input`): the pointer still moves (except
  during a drag), and the panel's Stop and Escape still work, both stopping
  the check; whenever the check asks you something, they're yours again.
  Meanwhile every screen dims (black at 50%) but the panel: the shade lets
  the check's drags through and hides nothing from it (macOS still counts
  the windows under it as visible, so a Chromium page there takes presses).
  Its own window may move aside so the app's shows. Everything is put back
  as it was at the end (also at a Stop). A check takes about 3 minutes; the
  status says which state it's in ("Checking: its window covered, 2 of 7…").
  While it runs, a small panel at the screen's bottom right shows how far it
  has got, on every desktop (full screen apps' too): what it's doing, what
  it asks of you with the time left, the window states as segments with the
  one it's in and the way it's pressing, while your input is blocked an
  orange line saying so, and its **Stop**, which leaves the app you're in
  where it is. It floats above other windows (above the menu bar and the
  shade too while the screen is dimmed), which the check doesn't count as
  covering the app; during a drag, a click on it is taken as its Stop. The
  keyboard's Play/Pause key isn't one: macOS sends it only to the Now
  Playing app, which AutoHush can't choose (when AutoHush pauses a player,
  the app that started playing may hold Now Playing). When a way leaves it
  paused, the check first plays it again by itself (that way once more, then
  a way that worked, else AppleScript, its menu, then the panel) and asks
  you only when none does; a track that ends during a test is tested again
  rather than failing the way. **Stop** ends a check (if a test had paused
  the app, it's played again first; what the check is doing ends first, then
  the window is put back). A check stopped or failed leaves the last
  finished one shown, with a note. Quitting Player Check, or closing its
  window, stops a check or Play/Pause that's running; one whose window went
  by force (or a crash) stops by itself. Its window doesn't go full screen:
  the green button zooms it instead.
- **The results:** "Ways to Control It" as a checklist (✓ worked in every
  window state, an orange ⚠ in some, with the states it failed in and why
  under it, ✗ in none or not there, ? not tried, – not checked), "For
  AutoHush" (which kind of player it would be), and the full report, which
  **Copy Report** copies. It runs each check with `playercheck --developer`,
  so the verdict also says how a built-in player of that kind would be made
  (a `ScriptablePlayerProfile` with its suite, a `MenuPlayerProfile`, …),
  which AutoHush's Add an App… leaves out.
- **Play and Pause:** once a check found a way that works (✓ or ⚠), the app
  gets **Play** and **Pause** buttons above its results. Pressed, they read
  the state the app's window is in (`playercheck --window-state`) and use
  the first way in the checklist that worked in that state in its check,
  alone; the result says which ("Its window minimized: by its row in the Now
  Playing panel."). When no way worked in that state, nothing is pressed and
  it says so. Before a check, or when no way worked, there are none. Each
  way found in the checklist (✓, or ? not tried) has its own two buttons,
  which use that way alone. The result shows under Play and Pause ("Paused
  it with its page's 'Pause current' button."). While one runs, **Stop**
  ends it (it may be waiting on the app, or on macOS's Automation prompt);
  the buttons are off until it ends. The app must be running.
- **Electron apps and their launch option:** Chromium takes no presses on an
  Electron app's page while its window is covered or on another desktop,
  unless the app was opened with `--disable-backgrounding-occluded-windows`
  (playercheck's README says more). Player Check reads whether it was
  (`playercheck --launch-option`); when it wasn't, an orange note says a
  check now would show those states failing, with **Relaunch … With It**:
  confirmed, it quits the app and opens it again with the option, in the
  background (`playercheck --relaunch`), which stops what it was playing.
- **Logs:** every check and Play/Pause is also logged, whole and with each
  line's time, in `~/Library/Logs/PlayerCheck/` (the last 50 runs): when a
  result looks wrong, the run that gave it can be read there, though a later
  check replaced it here.

## Permissions

- **Accessibility**, for Player Check: reading menus and pages, pressing
  them, and the switches that show an Electron, CEF or Flutter app's
  interface (Electron's `AXManualAccessibility`, VoiceOver's
  `AXEnhancedUserInterface`; for a Chromium browser's web app, VoiceOver's
  set on the browser, for all its windows and tabs; turned back off after,
  unless one may have been on already), and putting the app's window in each
  state (moving it, and the pointer and keyboard events that drag it to
  another desktop). The app's detail shows its framework as a tag, and the
  check's confirmation says which switch it turns on and that the app may be
  brought forward a moment while its window is out of sight (both as
  playercheck's `--now-playing-reasons` tells them). PlayerCheck runs inside
  it and shares it. Without it, a note links to System Settings, and
  **Check…** first asks macOS for it (macOS's own request, which leads to
  System Settings), then waits: the check starts by itself once it's allowed
  (**Stop** ends the wait). A check without it could only test AppleScript.
  Signed ad hoc, a rebuilt one needs it again; signed with a certificate
  (`SIGNING_IDENTITY`, above), it keeps it.
- **Automation** for an app with AppleScript play or pause, asked at the
  start of its check (and before a Play or Pause by AppleScript), as
  AutoHush asks it.
- **Audio Recording**, asked at the first check: Player Check measures how
  loud the app is, as AutoHush does, to tell whether it plays, and keeps it
  muted through the check (macOS shows its recording indicator meanwhile;
  nothing is recorded). A check needs it; without it, a Play or Pause judges
  sound by what the app tells macOS and its open output.
- **An administrator account** for the "In Now Playing Now" section: it
  comes from macOS's log (`playercheck --now-playing-list`), which only
  administrators can read. Without it, the list still shows the apps that
  can be in Now Playing.

## Which apps can be in Now Playing

No Info.plist key or entitlement says so: Spotify, Deezer, TIDAL and VLC
have none. What they share is their App Store category
(`LSApplicationCategoryType`, music or video), which doesn't match Now
Playing (Podcasts has an empty one, web apps none, GarageBand is "music"),
and Apple's own apps carry private MediaRemote entitlements. An app joins
Now Playing only while it runs, through its code. So Player Check reads the
frameworks the app's binaries link (their Mach-O load commands: everything
in `Contents/MacOS`, where VLC's is a plugin, and the app's own
frameworks), through playercheck's `--now-playing-reasons`: the same rule
its checks use.

| Reason shown | Linked | For example (macOS 27) |
|---|---|---|
| MediaPlayer | `MediaPlayer.framework` (MPNowPlayingInfoCenter and MPRemoteCommandCenter: the public way) | Spotify, VLC, Music, Podcasts, Books, News |
| MediaPlayer, through Electron / Chromium (CEF) | the same, in the app's Electron or Chromium framework | Deezer, TIDAL |
| MediaRemote | `MediaRemote.framework` (Apple's apps) | QuickTime Player, TV, Voice Memos |
| AVKit, for videos it plays | `AVKit.framework` only (its player view updates Now Playing) | Photos, Notes, App Store |
| WebKit | Safari, and Safari web apps by their bundle ID (their pages report through WebKit's media process) | web apps for YouTube Music, SoundCloud |
| Chromium, as a &lt;Browser&gt; web app | nothing it links: its launcher's Info.plist names its browser (`CrBundleIdentifier`); since Chromium 130 each web app reports as itself, apart from the browser's tabs | web apps made with Chrome or Brave (in `~/Applications/<Browser> Apps.localized`) |
| WebKit, for the pages it shows | `WebKit.framework` (the pages any app shows report through WebKit's GPU process, under the app's bundle ID) | Pake's YouTube Music (a Tauri app); also apps that only show pages, as Mail, Maps and Dictionary |

The last row lists apps that aren't players: whether they report depends on
the pages they show (Pake's YouTube Music was the active Now Playing app
while it played; Mail's messages rarely play anything). An app macOS lists
in Now Playing is shown even if none of these matched; TextEdit, Calculator
and AutoHush itself aren't listed.
