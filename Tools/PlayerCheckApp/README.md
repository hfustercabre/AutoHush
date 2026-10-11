# Player Check

A window over [PlayerCheck](../PlayerCheck): it lists the apps on your Mac
that can be in macOS's Now Playing list, and checks the one you pick for
the ways AutoHush could control it. It can also play and pause the apps
with a known way, to try each way by hand.

```bash
sh Tools/PlayerCheckApp/build.sh              # writes "Player Check.app" here, with playercheck inside it
open "Player Check.app"
```

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

- **The list:** the apps in `/Applications`, `~/Applications` (where
  Safari web apps are) and `/System/Applications`, subfolders included,
  that can be in Now Playing (see below). Those macOS lists in Now Playing
  right now come first, with their state: "Now Playing (Playing)" for the
  active one, "In Now Playing: Paused", or
  "Registered" for an app ready for it that never said it plays. A green
  dot: it's running. "checked": it has a finished check (kept between
  launches, in `~/Library/Application Support/Player Check/`; those from
  before the Play/Pause key stopped being a way are dropped). Search by name. The
  list of Now Playing apps is read in full when Player Check opens and when
  the arrow in the toolbar looks again; after a check or a Play/Pause, only
  what changed is read.
- **Checking:** choose an app, then **Check…**, and confirm. An app that
  isn't running is opened first, in the background. The check tests each
  way to control it (AppleScript, its playback menu, its page's button and
  the menu bar's Now Playing panel), pausing the app and playing it again
  by each. The keyboard's Play/Pause key isn't one: macOS sends it only to
  the Now Playing app, which AutoHush can't choose (when AutoHush pauses a
  player, the app that started playing may hold Now Playing). It needs the app playing: if it isn't, an
  orange request asks you to start it, and the test goes on by itself as
  soon as it plays (up to 2 minutes). **Stop** ends a check (if a test had
  paused the app, it's played again first). A check stopped or failed
  leaves the last finished one shown, with a note.
- **The results:** "Ways to control it" as a checklist (✓ worked in the
  test, ✗ not there or didn't work, ? not tried, – not checked), "For
  AutoHush" (which kind of player it would be), and the full report, which
  **Copy Report** copies.
- **Play and Pause:** an app with a known way to control it gets **Play**
  and **Pause** buttons: once its check found a way, or before any check
  when the app shows one (a scripting dictionary with play and pause, a
  Safari web app, an Electron, CEF or Flutter app). They use the first way that worked in
  its check; otherwise they try AppleScript, the page's button, then the
  menu, in turn. Each way in the checklist that worked has its own two
  buttons, to use that one alone. The result shows under the buttons ("Paused it with its
  page's 'Pause current' button."). The app must be running.

## Permissions

- **Accessibility**, for Player Check: reading menus and pages, pressing
  them, and the switches that show an Electron, CEF or Flutter app's
  interface (Electron's `AXManualAccessibility`, VoiceOver's
  `AXEnhancedUserInterface`; turned back off after). The app's detail shows
  its framework as a tag. PlayerCheck runs inside it and shares it.
  Without it, a note links to System Settings. Signed ad hoc, a rebuilt
  one needs it again; signed with a certificate (`SIGNING_IDENTITY`, above),
  it keeps it.
- **Automation**, asked by macOS the first time it reads or controls an
  app by AppleScript.
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
| WebKit, for the pages it shows | `WebKit.framework` (the pages any app shows report through WebKit's GPU process, under the app's bundle ID) | Pake's YouTube Music (a Tauri app); also apps that only show pages, as Mail, Maps and Dictionary |

The last row lists apps that aren't players: whether they report depends on
the pages they show (Pake's YouTube Music was the active Now Playing app
while it played; Mail's messages rarely play anything). An app macOS lists
in Now Playing is shown even if none of these matched; TextEdit, Calculator
and AutoHush itself aren't listed.
