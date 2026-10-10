# Changelog

All notable changes to AutoHush are documented here.
This project follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Fixed

- **Music another app paused as it started didn't come back.** VLC, for
  one, pauses Spotify and Apple Music itself when it starts playing, before
  AutoHush pauses them, so AutoHush found them paused and left them alone
  once VLC stopped. AutoHush now resumes a pause like that as its own, when
  your player stopped after the other app's sound began. One you made
  before stays yours.

## [0.12.0] — 2026-10-10

### Changed

- **SoundCloud is a tested web app:** it's listed with Spotify, YouTube
  Music, Amazon Music and Deezer, suggested until you add it, and no longer
  marked Untested.
- **Adding Amazon Music asks for your account's country.** Amazon Music has
  its own site in some countries, and you can sign in only on your
  account's: Add a Web App still opens the one for your Mac's region, and a
  new row under the address lets you choose another country. Ireland now
  gets the United Kingdom's site, as Irish accounts use.

### Fixed

- **Learning a web app's controls could pause another app for a moment.**
  AutoHush pauses the web app with the keyboard's Play/Pause key, which
  macOS sends to its "Now Playing" app: the one that started playing last.
  When that's another app (one that started after the web app, say),
  AutoHush no longer presses the key: it asks you to pause the web app
  yourself right away.

## [0.11.3] — 2026-10-10

### Fixed

- **The learning window marked the step to do now with a grey circle,**
  while Add a Web App, showing the same steps, used a blue arrow: both use
  the arrow now.
- **In Arabic, that arrow pointed right,** away from its step, in a window
  that reads right to left: it points forward now, as the text runs.

## [0.11.2] — 2026-10-10

### Fixed

- **Settings → Apps' buttons didn't fit the narrowest window** in Czech,
  German, Greek, Hungarian, Slovenian and Ukrainian on macOS 26 and later,
  whose buttons are wider: in Ukrainian the page spread past the window.
  Those translations are shorter now.
- **On macOS 15, a lighter band ran under Settings' page name.** The page
  now runs up to the top, as on later versions.

## [0.11.1] — 2026-10-10

### Fixed

- **Return in the welcome window's search did nothing when two players
  shared a name,** as the Spotify app and the suggested Spotify web app
  do. It now picks the app, or, without it, the web app.
- **A player paused for another app stayed paused when you chose a
  different player meanwhile.** Choosing one ended the pause AutoHush was
  holding without resuming it. The player you left now plays again once
  the other apps stop, as it would have, unless you played or quit it
  yourself, and even if AutoHush is reopened meanwhile; choose it again and
  AutoHush takes the pause back.
- **Learn Controls didn't open the web app.** With it closed, It's Playing
  could only say AutoHush couldn't see its page. Now the web app opens with
  the learning window, as after adding it.
- **Ignore Another App… did nothing for an app that doesn't identify
  itself** as Mac apps do. An alert now says why it can't be ignored.
- **Learn Controls opened its window over Add a Web App,** in the same
  corner, while you typed an address. Add a Web App now closes first.

## [0.11.0] — 2026-10-10

### Changed

- **Settings has a sidebar, like System Settings.** Its pages are General,
  Apps, Detection, Fades, Diagnostics, Updates and About; the sidebar also
  shows AutoHush's version and a link to support it. The window no longer
  changes height from tab to tab: you resize it, and it opens where and as
  big as you left it.
- **Settings → General shows your media player** with what it's doing,
  whether AutoHush may control it and whether it fades, and Auto-Pause
  under it. Every player is a tile under it, three a row: click one to
  choose it. The welcome window shows the same tiles, and scrolls past five
  rows of them.
- **AutoHush is in the Dock while one of its windows is open.**
- **The menu's players come under "Supported Apps"**, as in Settings, then
  the Safari web apps under their own heading.
- **Learning a web app's controls happens in its window only.** The menu
  and Settings no longer show the steps. Instead, a **Controls** row in the
  menu's card and in Settings says whether they're learned, with **Learn
  Controls** (or **Learn Again** once learned): a new learning window that
  starts over, closing one still open. **Learn Controls Again…** is gone
  from the menu's players.
- **Learn Again keeps what AutoHush learned until you click It's Playing.**
  Until then the web app is still paused and resumed as before, so a click
  by mistake costs nothing: closing the window, or Later, keeps it.
- **The Mac's standard menus and keyboard shortcuts.** While one of its
  windows is open, AutoHush has the usual menu bar: ⌘V pastes a web
  address, ⌘W closes the window, ⌘Q quits and ⌘, opens Settings. Return
  presses a window's main button, or, in the welcome window's search, picks
  the player it narrowed down to; Escape presses Cancel. AutoHush still
  adds no shortcuts of its own.
- **The welcome, Add a Web App and learning windows look like Settings.**
  Their title sits in the title bar, as a Settings page's name; under it,
  the icon and what the window is for, then headed cards, and the buttons
  in a bar along the foot. The welcome window keeps one width for both its
  pages, and its permissions show on squares in your accent color.
- **AntiDot mode is on the Detection page**, with the timings. While it's on,
  the silence threshold, which only measuring uses, is hidden. **Updates**
  has a page of its own.
- **Restore Defaults sets back only what its page shows:** Detection's
  timings (not the silence threshold while AntiDot mode hides it), or the
  fades.
- **Media, not just music.** AutoHush pauses music, podcasts and videos, and
  now says so: you choose your *media player*, the switch is just
  **Auto-Pause**, and the timings and fades talk about *playback*.
- **Liquid Glass on macOS 26 and later.** The menu's card, Settings' cards
  and AutoHush's buttons are glass, and macOS draws its own controls in
  AutoHush with it too. On macOS 15 AutoHush looks as it always has.

### Fixed

- **AutoHush didn't open on Intel Macs.** It was built for Apple silicon
  only; it now runs on both.
- **AntiDot mode could show the purple dot.** With "Open audio streams
  only", a web app that wouldn't pause (during an ad) was still muted, and
  listened to first, through an audio tap. AntiDot mode now never taps, as
  it promises.
- **A fade-out called off at the wrong moment came back up fully,** then
  faded out again, when another app started just then. It now fades out
  again from where it was.
- **AutoHush's windows fell behind other apps' after a desktop switch.**
  Going to another desktop and back brought the app you'd used before in
  front of Settings or the welcome window. Now AutoHush's window stays in
  front.
- **The first It's Playing after opening a web app didn't take.** It said
  AutoHush couldn't see the web app's page, and a second click worked:
  Safari prepares a page for AutoHush only when it's first asked, and
  answers that first question with nothing. Now AutoHush asks again.

## [0.10.0] — 2026-10-09

### Fixed

- **The menu showed some errors in English.** When the music player answered
  a start with an error, the status line showed the technical message. Now
  it says "Can't control TIDAL right now" in your language, and an ⓘ after
  it tells why, in words.
- **A pause the music player refused went unnoticed.** The card kept saying
  "Playing" while the other app played. Now it says "Couldn't pause —
  Safari is playing", with the same ⓘ, until the other app stops.
- **Music paused just as the Mac went to sleep could come back after
  waking.** When another app started playing as the Mac fell asleep, the
  pause finished after it, and the music was resumed once awake. Now it
  stays paused, as after any sleep.
- **SoundCloud could learn a song's Play button instead of the player's.**
  Its player bar says "Play current", and the songs' own buttons, some
  scrolled out of sight, just "Play". Learning now prefers the button in
  sight that sits with the player's other controls.
- **A web app just added could be reported as not installed** while macOS
  hadn't caught up with it yet.
- Smaller fixes: adding a web app no longer holds AutoHush up while Safari is
  slow to answer, and the learning steps can no longer go back to an
  earlier step.

### Changed

- **You name the web app yourself.** Add to Dock opens Safari's Add to Dock
  window and leaves it to you: change the name if you like, then click Add.
  If you cancel it, Add to Dock opens it again.
- **The Add a Web App and learning windows stay in sight.** They float above
  other apps, in the top-right corner of the screen, while Safari and the
  web app come in front.
- **Learning a web app's controls takes one click.** Once the song plays and
  you click It's Playing, AutoHush pauses the web app itself with the
  keyboard's Play/Pause key, learns which button changed, and plays it
  again. If that doesn't take, the step says so, with Try Again and Pause It
  Manually, which lets you pause it yourself, as before. The minute you have
  for that now stands out.
- **Settings → Diagnostics** shows the music player's last error, and for
  TIDAL and Apple Podcasts whether AutoHush could read their own words for
  Play and Pause.

## [0.9.0] — 2026-10-09

### Fixed

- **Adding a suggested web app from the welcome window left two windows
  asking for the same permission.** Now the Add a Web App window closes once
  the web app is added, the welcome window asks for what it needs, and Done
  opens the window that learns its controls.

### Changed

- **Settings → Apps: click an app, then Remove.** Removing one app was only
  in its right-click menu. Now a click selects it, and **Remove**, under the
  list, takes it off. Removing an app you turned off asks first, since it
  then pauses your music again.

## [0.8.6] — 2026-10-09

### Fixed

- **It's Playing did nothing when AutoHush couldn't read the web app's
  page.** With the web app closed, without a window, or with a window macOS
  restored at login (it can show its buttons without their names), the
  click did nothing, or It's Paused then always said no button changed. Now
  the step says AutoHush can't see the page, and to open its window, or
  close it and open it again.
- **The Add a Web App window offered It's Playing before Accessibility was
  allowed.** Its learning steps now wait for the permission, with the same
  button to allow it as the learning window.
- **Adding a web app left its Safari tab open** when it was the window's
  only tab (Safari wasn't open before), or after answering the site's
  question. The tab is now closed, or its window when it's the only tab
  there.
- **Add a Web App could take another website for the one you typed** when
  their addresses began the same way and ended in short parts
  (music.amazon.bad.co for music.amazon.com). Now only another country's
  ending (es, co.uk, com.br) or a region's or city's (cat, berlin) counts as
  the same service's site.

## [0.8.5] — 2026-10-08

### Fixed

- **Learning a web app could take the wrong button.** AutoHush guessed
  when a web app played and paused from its sound, so with an ad first or a
  player bar that came late it could learn the playing song's own button,
  which stops working at the next song. Now you tell it: play a song, click
  **It's Playing**, pause it, click **It's Paused**, and the button that
  changed is learned. You have a minute between the two clicks (the step
  counts down), and a click AutoHush can't take says why. The buttons show
  wherever the steps do: the learning window, the Add a Web App window, the
  menu and Settings.
- **A web app added from a cookie page couldn't play.** On a Mac with no
  YouTube cookies in Safari (in Europe), YouTube shows its cookie page
  first, and AutoHush added that page: a web app called "Before you
  continue", with Google's icon, that sends the music to Safari. Now an
  **Answer the site in Safari** step waits until the site itself shows, and
  AutoHush adds it only once you click **Add to Dock**, after answering
  anything the site asks.
- **A fresh YouTube Music window made AutoHush learn its button again.**
  Such a window shows its player bar only once something plays, so after a
  minute AutoHush took the button for gone and asked you to play and pause
  it once more. The button now counts as missing only while the web app
  plays.

## [0.8.4] — 2026-10-08

### Fixed

- **A web app's button learned wrong stayed wrong.** AutoHush learned a web
  app's Play/Pause button again only when it went missing, so one learned
  the wrong way round (0.8.2 could, with an ad before the song) kept
  AutoHush pausing or resuming it at the wrong times. **Learn Controls
  Again…**, under the players in the menu and in Settings' player pop-up,
  or **Learn Again** in Settings → General, now forgets the button and asks
  you to play and pause the web app once more.

## [0.8.3] — 2026-10-08

### Fixed

- **Learning a web app's button could swap its words.** With an ad before
  the song, pausing right as the song itself began could make AutoHush
  learn YouTube Music's Play/Pause button with "Play" and "Pause" the wrong
  way round, so it read the music's state backwards. The words now come
  from the pause itself: the button's last change before the sound went
  off. A moment of silence the music comes back from by itself (a stall
  after the ad) no longer counts as the pause either.
- **A pause handed over at a restart could resume the wrong player.** When
  AutoHush quits while holding the music paused (an update, a reopen), the
  next AutoHush resumes it once the other apps stop. If the music player
  was changed in between, it resumed the newly chosen one, which wasn't
  paused. The handover now names the player, and only that one is resumed.

## [0.8.2] — 2026-10-07

### Fixed

- **The welcome window can't get lost anymore.** Opened while another app
  was in front (as after System Settings' **Open Anyway**), it could end up
  behind that app's windows, or on another desktop when that app took you
  there, and AutoHush has no Dock icon to bring it back. It now opens in
  front, on the desktop you're on, and opening AutoHush's menu brings it
  there again while it's open. It's also centered: it grew from the middle
  of the screen, so its bottom, Continue included, could be off the screen.
  And it's never taller than the screen: with web apps added, the list of
  players could make it taller than a 13-inch MacBook's; the list now
  scrolls instead. The learning, Add a Web App and Settings windows come
  forward the same way.
- **Learning works on a fresh YouTube Music window.** Such a window shows
  its player bar only once something plays, already saying "Pause"; with
  an ad first, the bar turns to "Pause" only when the song itself begins.
  AutoHush missed the bar's button then, and learned the song's own button
  instead, which stops working once another song plays. Both now count, so
  the bar's button is learned.

## [0.8.1] — 2026-10-07

### Fixed

- **A missing permission is asked for where it's needed, and waited for.**
  After you choose your player, the welcome window lists the permissions
  it needs, each with a button: **Open Spotify** (macOS asks for Automation
  only while the player is open), **Allow…**, which shows macOS's own
  prompt or the right place in System Settings, or **Use AntiDot Mode
  Instead**, which needs no audio permission. **Done** unlocks once
  everything's allowed; each line ticks by itself.
  - The window that learns a web app asks for Accessibility first, and its
    steps unlock once it's allowed. Before, it asked you to play the web
    app while AutoHush couldn't watch it yet, so the steps didn't tick
    until you chose the player again.
  - Add a Web App checks Accessibility as it opens; Continue waits for it.
  - Settings → General shows what's missing under the player and under
    AntiDot mode, with the same buttons, and says when macOS waits for you
    to allow AutoHush in Login Items.
  - The menu's permission row asks macOS first when it hasn't asked yet
    (it opened System Settings, which lists AutoHush only once asked), and
    with audio recording missing, a second row offers AntiDot mode.

## [0.8.0] — 2026-10-07

### Added

- **Safari web apps can be your music player.** Any website you add to the
  Dock from Safari (File → Add to Dock), such as YouTube Music, Amazon Music
  or Spotify's web player, is offered under **Safari Web Apps** in the menu,
  Settings and the welcome window. They're marked **Experimental**: every
  website works differently, so a web app may not pause or resume as
  expected, as the heading and the windows that add and learn one say.
  - AutoHush presses the site's own Play/Pause button, so the site stays in
    step. It learns which button that is: when you choose a web app, a
    window asks you to play something in it, then pause it, and closes once
    it has seen both. A tip under each step says how: log in first if the
    site asks, let the music itself play for 5 to 10 seconds (ads don't
    count), then wait for the tick. The same steps show in the menu and in
    Settings until then. It presses nothing before it has learned.
  - Spotify, YouTube Music, Amazon Music and Deezer have been tested: their
    web apps are offered first, under the site's name. Any other web app
    comes after them, marked **Untested**, its page title without the
    slogan after " | " or a dash.
  - It works with the window visible, minimized or on another Space, and
    with more than one window: it follows the one that plays. It needs the
    Accessibility permission, and pauses without fading.
  - When a site won't pause, AutoHush mutes the web app instead: during an
    ad whose button is disabled, or still reads "Play" as on YouTube Music,
    or when a press doesn't take. As soon as the site can be paused (the ad
    is over and the music plays), AutoHush pauses it and unmutes it, so the
    music goes on from there afterwards. A web app that pauses is never
    muted, and none is muted in AntiDot mode.
  - If a site changes so that its button can't be found for a minute,
    AutoHush asks to learn it again, and keeps both layouts.
  - Settings → Diagnostics shows whether the button has been learned and
    whether windows on other Spaces can be reached.
- **Add a Web App…** makes a website your music player from its address:
  in the menu's players, Settings (the player pop-up's last item) and the
  welcome window. Paste the address; AutoHush checks that the site
  answers, adds it to the Dock with Safari's own Add to Dock, chooses it,
  opens it and learns its controls, all in one window. **Cancel** stops it
  before anything is added; once added, the Safari tab it opened is closed.
  - The tested sites are offered with a download symbol until you add them:
    choosing one opens the window with its address filled in.
- **Fades can be turned off** with a switch in Settings → Advanced, without
  moving their sliders to 0: the music then pauses and resumes at once. The
  sliders show only while it's on, and Diagnostics says "Off".

### Fixed

- **A paused app no longer counts as playing just because its sound is
  still open,** while your music isn't playing. AutoHush only measures how
  loud apps are while it matters, and otherwise counted any open sound as
  playing: VLC, for one, keeps its sound open about a minute after you pause
  it. Now an app that tells macOS when it plays (VLC does) counts as paused
  once it stops telling, as in AntiDot mode.
- **Each Safari web app is told apart.** Their sound was all put down to
  one "Web App", so Settings → Apps showed a single entry for them; each
  now shows under its own name.
- **Music AutoHush paused stays paused after the Mac sleeps,** as music
  players keep it after a sleep. Other apps' sound stops as the Mac falls
  asleep, and AutoHush took that for them ending: it tried to resume the
  music while the Mac slept, which a web app's page couldn't follow, and
  the music didn't come back. Now nothing is paused or resumed while the
  Mac sleeps.
- **A resume that doesn't take is tried again,** twice, a second apart,
  as when the player doesn't answer.
- **A permission taken away while AutoHush runs is noticed.** If you
  turned off its Automation or Accessibility access in System Settings,
  AutoHush stopped pausing your music without a word, its menu still
  saying "Not playing". Now it checks again when another app starts
  playing or you open the menu, asks for the permission as it does at
  launch, and carries on by itself once you allow it again.
- **After you allow audio recording, the menu offers Reopen AutoHush.**
  macOS applies that permission only once AutoHush is opened again; until
  then the menu kept asking for it, as if you hadn't allowed it.
- **Command-line players pause the music too.** Sound from a program run
  in Terminal, such as afplay, mpv or ffplay, was never counted, since it
  has no app of its own. It now counts as the app that started it, e.g.
  Terminal, and can be ignored like any app.

---

## [0.7.0] — 2026-10-06

### Added

- **Twenty-one more languages, 35 in all.** Every European language macOS
  is translated into: Dutch, Swedish, Danish, Norwegian, Finnish, Polish,
  Czech, Slovak, Hungarian, Romanian, Croatian, Slovenian, Greek and
  Ukrainian. And the most spoken others: Russian, Turkish, Arabic (right to
  left), Hindi, Indonesian, Vietnamese, and Traditional Chinese for Hong
  Kong (also used in Macau and for Cantonese). Each uses macOS's own words
  for its settings and has the plural forms its grammar needs. Like most of
  the others, they were translated automatically.
- **Apple Podcasts and VLC** can be your music player, besides Spotify,
  Apple Music and TIDAL.
  - **Apple Podcasts** is controlled like TIDAL: AutoHush presses Play/Pause
    in its Controls menu, which needs the Accessibility permission, and it
    pauses and resumes without fading.
  - **VLC** is scripted like Spotify and Apple Music (macOS asks once for
    permission to control it), and fades.
  - Both are watched about once a second, since neither announces when you
    play or pause it.
- **Settings → Apps can be sorted** by Last Played (the default, the most
  recent first), Name or On/Off, and the arrow beside **Sort by** reverses
  the order. AutoHush remembers the choice.
- **A search over the music players**, in the menu's player list, beside
  Settings' pop-up and in the welcome window. It only appears once there
  are eight players or more, so not yet.
- **Settings → Apps has a search**: the magnifier beside **Sort by** opens
  a field that finds apps by name, ignoring case and accents. The ✕ closes
  it, and it's closed again each time Settings opens.

### Changed

- **A more consistent look and wording.** The "Sort by" pop-up looks like
  the music player's. Settings → Apps and Diagnostics share one bar at the
  bottom, with a line above it only while the list scrolls under it. A
  failure to change the login item shows as a warning, like the other
  warnings, not in red. Auto-Pause is spelled the same everywhere, the card
  asks to "Allow" access as the menu item under it does, "Playing Now" is a
  heading like the others, and tooltips read in sentence case.
- **The music players are offered the most used first**: Spotify, Apple
  Music, VLC, Apple Podcasts, then TIDAL. Those that aren't on your Mac come
  last, in the menu, Settings and the welcome window.
- **Settings → Apps grows with its list**, up to the height of Advanced,
  so more apps show before it scrolls. The heading and the buttons stay in
  place while the list scrolls.
- The code shared by TIDAL and Apple Podcasts lives in `MenuPlayers`, and
  players that announce nothing share one observer. TIDAL works as before;
  it notices being quit at its next check, within a second.

## [0.6.3] — 2026-10-06

### Fixed

- **AntiDot mode now pauses the music for Safari.** Safari only says it's
  playing a video, and does it differently while the video is hidden. Once
  AntiDot mode had seen that, it took every visible Safari video, and any
  sound without video, for paused, so the music kept playing. It now knows
  how Safari and other apps built on WebKit tell macOS they play: the music
  pauses for their videos and comes back about 2 s after you pause one,
  instead of about 9.5 s. Sound without video still pauses the music, even
  when it starts right after you pause a video. Apps are learned again
  after updating.

### Changed

- **AntiDot mode ignores notification sounds from Chrome and similar
  apps**: sound without video must now last at least 3 s before the music
  pauses (videos still pause it after 0.5 s). These apps say they're
  playing for about 2.5 s after even a short sound, which paused the music
  for each message. Settings and Diagnostics show the new timing.
- The README compares the two modes with measured times.

## [0.6.2] — 2026-10-05

### Changed

- **Diagnostics shows more**: how AutoHush is doing at the top, then the
  apps with sound, the music player (its version, its state and whether it
  can fade), the detection and its timings, each permission with whether
  it's allowed, AutoHush's own settings, and the Mac. Headings stand out
  from the content, each part folds away to a one-line summary, the tab
  scrolls, and Copy Report includes all of it.
- **Settings opens on General** every time, instead of on the tab it was
  left on.
- **About is a tab in Settings**, instead of a separate panel: AutoHush's
  version, what it does and the players it works with, links to GitHub,
  the release notes and a new issue, and a link to support AutoHush. The
  menu's **About** button opens it.
- **Spanish and Catalan** reviewed by a native speaker, including the text
  added in 0.4.0 to 0.6.1. The permissions now read "acceso a Accesibilidad"
  and "acceso a Automatización" ("accés a Accessibilitat", "accés a
  Automatització"), plus two smaller Catalan fixes.

## [0.6.1] — 2026-10-05

### Changed

- **Easier to read in light mode**: descriptions, labels and warnings are
  darker, cards have an outline, and switches that are off show their
  track. Dark mode is unchanged.

## [0.6.0] — 2026-10-05

### Added

- **Settings → Diagnostics**: what AutoHush sees right now, kept up to date
  while the tab shows: every app with its sound on, with its icon, how
  AutoHush judges it and why, then its own settings. **Copy Report** puts
  it on the clipboard. It replaces the Diagnostics alert; ⌥-clicking
  Settings in the menu opens it.

### Changed

- **A redesigned menu**, laid out like Control Center:
  - **A card at the top** with your music player's icon and name, what's
    happening ("Paused — Safari is playing"), and the **Auto-Pause** switch.
  - **Music player** is on the card: click it to unfold the players.
  - **Turn off for** offers each duration as a button, so pausing AutoHush
    takes one click.
  - **Playing now** gives each app a switch for whether it pauses your
    music, instead of a submenu.
  - **Settings, Updates, About and Quit** are buttons at the bottom.
  - **Retry** is on the card, only when the player didn't answer or
    reported an error, and the menu stays open to show how it went.
    AutoHush also tries again by itself then, less and less often (up to
    once a minute).
- **Settings looks like the menu**: each group of settings sits in a card,
  with the same switches and buttons, and each app in the Apps tab has its
  icon and a switch. The choice of what happens when an update is found,
  and AntiDot mode's choice of detection, are rows of buttons. The welcome
  window lists the music players as rows in a card, the chosen one checked.
- **Players that aren't installed** show a likeness of their icon, drawn
  in your Mac's icon style (default or dark), instead of a blank app icon.
- **Bigger text** in the menu, Settings and the welcome window: one step
  above the system's sizes, so descriptions and labels read easily. The
  menu is a little wider to match.
- **No keyboard shortcuts**: ⌘, ⌘Q, ⌘R and ⌥⌘, are gone from the menu, and
  Return no longer presses a button in AutoHush's windows and alerts.

### Fixed

- In light mode, the "Notifications are off" note in Settings no longer
  disappears when it blinks.
- TIDAL's words for Play and Pause are read from the TIDAL that's running,
  not from another copy on the Mac, such as the disk image it came from.

## [0.5.1] — 2026-10-05

### Fixed

- **AutoHush notices when your music player is uninstalled while it runs**,
  and says so at once instead of after a restart. It starts again by itself
  when the player is put back.
- **Only players in an Applications folder count as installed**:
  /Applications, your own ~/Applications or /System/Applications. A copy on
  the disk image it came from, or anywhere else, no longer does.

## [0.5.0] — 2026-10-05

### Added

- **TIDAL support**: choose TIDAL under Music Player. TIDAL can't be
  scripted, so AutoHush pauses and resumes it by pressing Play/Pause in its
  Playback menu, which needs the Accessibility permission. TIDAL's volume
  can't be read, so it pauses and resumes without fading, and the fade
  settings are dimmed while it's the player.

### Changed

- **AutoHush starts by itself once you grant a permission** it needs to
  control your music player, instead of waiting for you to choose Retry.
- **Settings → Advanced is grouped** like General: Detection (when another
  app counts as playing or stopped, and the silence threshold) and Fades.
  **Treat an app as stopped after** is now **Resume music after**, worded
  like **Pause music after**.

## [0.4.0] — 2026-10-05

### Added

- **Apple Music support**: AutoHush can now pause and resume Apple Music
  (the Music app) instead of Spotify, with the same fades.
- **Choose your music player**: in the menu's new **Music Player** submenu,
  or in Settings → General. A player that isn't on your Mac is shown
  dimmed. The first time AutoHush opens, a small window asks which one to
  use; if you're updating, AutoHush keeps controlling Spotify. The player
  you don't choose counts like any other app: its sound pauses your music,
  unless you ignore it.

### Changed

- **Settings → General is tidier**: it's grouped into Music, Privacy and
  Updates, with each setting's description under it. **Check Now** shows
  what the last check found and when it ran, and the choice of what
  happens when an update is found is hidden while automatic checks are
  off.
- macOS's permission prompt now says AutoHush controls "your music
  player".

### Fixed

- The Settings window now resizes as soon as a switch shows or hides
  options. Before, it kept its old size until the next click.

## [0.3.11] — 2026-10-04

### Changed

- **Lighter while your music plays**: with no other app playing, AutoHush
  now checks for one once a second instead of four times (a new app is
  still noticed at once), and it redraws its menu only when something
  changed.
- **Update checks leave nothing on disk**: no network cache or cookies are
  kept for them.

### Fixed

- In Settings → General, clicking between or beside the update choices no
  longer makes the "Notifications are off" note blink.
- Two copies of AutoHush opened at the same moment no longer both quit:
  only copies opened earlier are asked to quit.

## [0.3.10] — 2026-10-04

### Fixed

- **After you reset AutoHush's notifications in System Settings** (Reset
  Notifications…), AutoHush asks for permission again: at once while its
  Settings window is open, otherwise within the hour. Before, it didn't
  notice until it was opened again.

## [0.3.9] — 2026-10-04

### Changed

- **AutoHush asks for permission to send notifications when it first
  starts**, along with its other permissions, instead of with its first
  news about an update.
- **While notifications are off, the update choices that rely on them are
  unavailable**: Notify me and Download it and notify me show dimmed, and
  clicking one makes the "Notifications are off" note blink. If one of them
  was chosen, AutoHush switches to Install it automatically and turns
  automatic checks off, so nothing is installed without you. Settings
  follows changes to the notification setting while it's open.

### Fixed

- **Only one AutoHush runs at a time**: opening another copy (another
  version, a second install) quits the one already running, instead of both
  pausing and resuming your music. A pause the old one was holding is taken
  over, as after an update.
- Quitting AutoHush with `kill` or from the system now restores the volume
  and hands over a pause, like quitting from its menu.

## [0.3.8] — 2026-10-04

### Added

- **Notifications about updates**: AutoHush now tells you when a new
  version is available, downloaded, or installed ("AutoHush was updated to
  0.3.8"), and when an automatic install fails. It asks for permission the
  first time it has news.
- **Choose what happens when an update is found** (Settings → General):
  **Notify me**, **Download it and notify me**, or **Install it
  automatically** (the default, as before). A downloaded update is kept for
  at most 7 days, is replaced when a newer version comes out, and is deleted
  once installed or no longer wanted. Automatic downloads wait while Low Data
  Mode is on.
- **The update window shows what's new**, and says which version you're
  running and which one is available or downloaded. Its button tells you
  whether it will **Download and Install** or just **Install and Relaunch**.

### Changed

- Once an update is found, **Check for Updates…** in the menu becomes
  **Install AutoHush 0.3.8…**, which opens the update window. It replaces
  the separate "Update Available" item.
- If you had turned off "Install updates automatically", your choice is now
  **Notify me**.

## [0.3.7] — 2026-10-04

### Changed

- **Buy Me a Coffee** has left the menu: it's now a line in **About
  AutoHush** and at the bottom of **Settings → General**, "Would you like to
  support me?", with the link.

## [0.3.6] — 2026-10-04

### Added

- **Buy Me a Coffee** in the menu opens AutoHush's Buy Me a Coffee page, if
  you'd like to support it.

## [0.3.5] — 2026-10-04

### Changed

- **Updates keep working on future macOS versions**: macOS 27 deprecates
  the `hdiutil` commands AutoHush used to open a downloaded update. It now
  opens it with `diskutil image`, which macOS recommends instead, and falls
  back to `hdiutil` on macOS 15, which doesn't have it.

## [0.3.4] — 2026-10-04

### Changed

- **Installing with Homebrew takes one command**:
  `brew install --cask hfustercabre/tap/autohush`. The cask moved from this
  repository to its own tap,
  [hfustercabre/homebrew-tap](https://github.com/hfustercabre/homebrew-tap),
  which Homebrew adds by itself. Copies installed with the earlier two-line
  command keep updating themselves as before.

## [0.3.3] — 2026-10-04

### Fixed

- **Updating no longer leaves your music paused**: if you chose **Install
  and Relaunch** while AutoHush had your music paused for another app, the
  new version didn't know that pause was its own, so your music stayed
  paused. Now AutoHush notes the pause as it quits to update, and the new
  version takes it over. Your music comes back when the other app stops,
  or within a couple of seconds if nothing is playing any more. Automatic
  updates still wait until AutoHush isn't holding your music paused.

## [0.3.2] — 2026-10-04

### Fixed

- **Restarting after an update**: AutoHush installed the new version but
  then failed to restart. The old version stayed running, unresponsive,
  until it was force-quit, and only then did the new one open. The cause
  was its quit: it had to wait for work that couldn't run until the quit
  itself finished. AutoHush now quits from the main run loop, and the
  one-second safety limit on quitting is a timer that always fires.
  0.3.0 and 0.3.1 still have the problem when they install the next
  version: force-quit AutoHush once afterwards (or log out), and the new
  version opens.

## [0.3.1] — 2026-10-04

### Changed

- **One setting for when the music comes back**: Settings → Advanced no
  longer has **Resume music after**. It only added a fixed wait after
  **Treat an app as stopped after**, which already decides when the music
  resumes, and it was too short for any sound to call the resume off. The
  music now resumes as soon as the last app counts as stopped: 2 s of
  silence by default, 0.2 s sooner than before. A value you had set for
  it is no longer used.
- **Treat an app as stopped after** is now at least 1 second. Below that,
  the music came back in every short pause between tracks or videos;
  shorter values you had set become 1 second.

## [0.3.0] — 2026-10-04

### Added

- **Updates itself**: when the daily check finds a new version, AutoHush
  downloads it from GitHub, installs it and restarts. It waits for a moment
  when it isn't holding your music paused and none of its windows or menus
  are open.
  - **Checks first:** the download must match GitHub's SHA-256 checksum, and
    the app inside must be the announced version, signed with the same
    certificate as the copy you have. That is the check macOS uses to keep
    AutoHush's permissions, so nothing else can be installed this way.
  - **To turn it off:** Settings → General → **Install updates
    automatically**. The menu's **Update Available** then offers **Install
    and Relaunch**.
  - **When it can't:** AutoHush can't update itself from a folder it can't
    write to, and Settings says so.
  - **Earlier copies:** versions up to 0.2.0 still need one update by hand.
- The Homebrew cask now declares that AutoHush updates itself
  (`auto_updates`), so `brew upgrade` leaves it to AutoHush.

## [0.2.0] — 2026-10-04

### Changed

- **Lighter on the battery**: AutoHush now wakes the Mac about once a
  second when idle instead of about 30 times, and uses half the CPU or less
  (measured: 0.18 % idle, 0.26 % with the music playing, 0.35 % while
  measuring another app; Energy Impact 0.2–0.4). Its once-a-second check
  only asks the processes with audio running, instead of every audio
  process on the Mac.
- **Turn Off For** now offers 5, 15 and 30 minutes, 1 hour and 24 hours.
  24 hours replaces Until Tomorrow, which ended at 8:00 the next day: up to
  31 hours when chosen after midnight.
- **Eleven languages**: AutoHush now speaks English, Spanish (Spain and
  Latin America), Catalan, German, French (France and Canada), Italian,
  Portuguese (Brazil and Portugal), Japanese, Korean and Chinese (Simplified
  and Traditional), following your Mac's language: it uses the first of your
  preferred languages that it has, and English otherwise. Every text it
  shows (the menu, Settings, alerts, Diagnostics, VoiceOver labels and the
  permission prompts) comes from String Catalogs in
  `Resources/Localization/`. Each build adds new text from the code to the
  catalog by itself, as Xcode does, and the engine now hands Diagnostics
  plain facts that the app words.
- **A redesigned installer**: the disk image window now uses AutoHush's
  colours and mark, the mounted disk shows the app's icon, and the window
  leaves room for Finder's tab and path bars, so the first-launch note is
  never cut off. The volume's hidden files stay out of sight even when Finder
  shows hidden files.
- **An app icon**: the menu bar's sound bars in purple, on a background that
  follows your Mac's appearance (light, dark, clear or tinted on macOS 26 and
  later). Made in Icon Composer and compiled into the app; macOS 15 gets a
  flat version.
- **A menu bar icon of its own**: sound bars cut out of a rounded square,
  replacing eight unrelated system symbols. Every state uses the same tile:
  the bars play, become a dot and a pause sign when AutoHush pauses your
  music, drop to three dots when nothing plays, point away when the music
  plays on another device, show hollow while starting, and make room for "!"
  when something needs your attention. Drawn in code, so it stays sharp at any
  size.

- **Modular project structure**, following Apple's sample apps (Food Truck,
  Backyard Birds) and popular open-source Mac apps (AeroSpace, Ice, Stats):
  - `AutoHushKit`: the engine (audio detection, playback decisions, fades,
    the `MusicPlayer` interface, permissions, configuration, storage). It has
    no user interface and knows no player by name; the compiler keeps it
    from depending on the app or a player.
  - `AutoHushApp`: the app, grouped by feature (MenuBar, Settings, Updates,
    Diagnostics, About), with `Main/` wiring them to the engine. Update
    checks, the Diagnostics text and the About panel moved out of
    `AppDelegate` (`UpdateController`, `DiagnosticsReport`, `AboutPanel`).
  - `AutoHush`: a one-file executable that only starts the app.
  - `SpotifySupport`: everything Spotify-specific; each new player gets its
    own `<App>Support` module, listed in `AutoHushPlayers`. Player modules
    and their tests live in `PlayersSupport/` folders.
  - `AutoHushKit/PrivateAPI`: the only place calling undocumented macOS
    functions (TCC, `responsibility_get_pid_responsible_for_pid`).
  - `AutoHushKit/Permissions`: what each permission is for and where it is
    granted; the menu's warning is now the missing `Permission`.
  - Types shared between modules use `package` access. Tests are split per
    module, with shared fakes in `AutoHushTestSupport`. `AutoHushError` is
    now `MusicPlayerError`.
- **`measure-volume-curve` is a package tool** (`swift run
  measure-volume-curve`, in `Tools/`) that uses the engine's tap meter
  (which now also reports the average level) and the supported players,
  replacing `Scripts/measure-volume-curve.swift`.
- The engine no longer uses AppKit: opening System Settings moved to the app.
- **Simpler code**, with no change in behaviour:
  - `AudioMonitor` hands AntiDot mode's judging to `PlaybackSignals` and
    what Diagnostics shows to `ActiveAudioReport`.
  - Menu and Settings text for the engine's states and choices lives in the
    app, with one row per state for its icon, label and status line.
  - Long functions are split into named steps (the menu, the measuring
    tool), repeated code is shared (process caches, Spotify commands,
    the auto-pause display), and every type has a doc comment.
  - Repetitive tests are parameterized.
  - Unused code is gone: the menu's "monitoring" look and "until Thursday"
    snooze text (never shown, yet translated into every language),
    options nothing used (opening Settings on a given tab, a custom status
    bar, a second check that audio output is running), and test helpers
    copied between files (fixed dates, the fake GitHub answer).
- Less duplicated code: the timing defaults are defined once (in
  `TimingSettings`), and each supported player is listed once.

### Fixed

- An app that stops while the music fades out now brings the music back up
  at once, without pausing it. Before, the pause always finished first (the
  fade held up every later event), then the music resumed. This showed with
  a fade-out at least as long as "Treat an app as stopped after".
- Turning auto-pause off no longer holds up player updates while the music
  fades back in.
- Music paused just as the other app stopped (after the fade-out, while the
  volume was being set back) stayed paused, and faded down. It now resumes.
- `measure-volume-curve` no longer crashes when the music goes silent during
  a measurement, and gives the player its volume and play state back when it
  stops early.
- Turning auto-pause back on (or a snooze ending) no longer pauses the music
  for a moment because of an app that only has its sound output open, such as
  a muted call or a paused video. While auto-pause is off nothing is
  measured, so such apps count as playing; AutoHush now measures them again
  before pausing, which takes about 2.5 s.
- A snooze that ends the next day no longer reads "until tomorrow 22:00"
  after midnight: the menu and Settings now say "until 22:00".
- Clicking Check Now twice, or checking while the automatic check runs, no
  longer asks GitHub twice and shows the answer twice.

### Security

- The update check only ever opens one of AutoHush's release pages on
  github.com: an answer pointing anywhere else (another site, a file, a
  network share, another app) is refused.

## [0.1.0] — 2026-10-03

The first release of AutoHush: a macOS menu bar app that pauses your music
while other apps play audio, and brings it back afterwards. It works with
Spotify and needs macOS 15 or later.

### Pausing and resuming

- **Automatic:** the music pauses when another app has been making sound for
  0.5 s, and resumes 0.2 s after every other app has been quiet for 2 s, so
  gaps between tracks or videos don't bounce it.
- **Fading:** the music fades out over 1 s before pausing and back in over 2 s
  after resuming, at a steady rate in decibels (a logarithmic fade) down to
  50 dB below your volume. Your volume is always left as it was, even when a
  fade is interrupted, the other app stops halfway, or AutoHush quits.
- **Respects you:** if you pause, play or quit the music player yourself while
  another app is playing, AutoHush takes that as your decision and won't
  resume it later. It only ever resumes music it paused.
- **Ignores the noise:** notification banner sounds, alert beeps and system
  sound effects (played by `systemsoundserverd` for every app) never pause the
  music, and neither do short sounds apps play themselves.
- **Knows where you're listening:** music playing on another device through
  Spotify Connect is left alone.
- **Reliable:** the player is asked for its live state right before every
  pause and resume; a resume is retried when the player doesn't answer in
  time, and the startup check is retried while a just-launched player isn't
  ready yet. AutoHush restarts monitoring by itself when the player opens.

### Detecting other apps' sound

- **Audio levels:** each app with its sound on is measured through a private
  CoreAudio process tap (peak level only, in memory, nothing recorded), so a
  paused video that keeps its sound switched on doesn't keep the music paused.
  Apps are grouped by the app that owns them (Chrome's helpers count as
  Google Chrome).
- **Purple recording dot kept to a minimum:** other apps are measured only
  while it can change a decision (auto-pause on, the music playing on this Mac
  or paused by AutoHush), and the music player itself is never measured.
- **System Audio Recording permission:** read and requested through TCC; when
  it's denied, AutoHush falls back to "any app with its sound on is playing"
  and the menu links to the right place in System Settings.
- **AntiDot mode** (Settings → General): never measures sound, so macOS never
  shows the purple dot. Apps are judged by what they tell macOS: an app that
  keeps the Mac awake for playback counts as playing, one seen doing that
  before but not now counts as paused, and the rest count while their sound
  is on. Alternatively, any app with its sound on can count as playing.

### Menu bar

- A status line ("Music paused — Google Chrome is playing"), the playing apps
  with their icons and a **Never Pause Music for …** option each, **Auto-Pause
  Music**, **Turn Off For** (15 minutes, 1 hour, until 8:00 tomorrow) and
  **Ignored Apps**.
- One actionable warning when a permission is missing, **Retry** after a
  failed start, and **Diagnostics…** (hold ⌥) listing every app with its sound
  on and how AutoHush judges it.
- **About AutoHush**, **Check for Updates…** and **Update Available** when a
  newer release exists.

### Settings

- **General:** launch at login, Auto-Pause Music, AntiDot mode and its
  detection choice, and update checks.
- **Apps:** every app that has played sound, each with a **Pauses Music**
  switch; **Ignore Another App…**, **Remove from List** and **Reset List…**.
- **Advanced:** how long an app must play before the music pauses, how long it
  must be quiet before it counts as stopped, the extra wait before resuming,
  the fade-out and fade-in times, and the silence threshold, with **Restore
  Defaults**. Changes apply immediately.

### Updates

- A daily check (optional) and a manual one against the latest GitHub release;
  only the release's tag and page are read. Homebrew installs are told to run
  `brew upgrade --cask autohush`.

### Distribution

- Signed with the self-signed "AutoHush Self-Signed" certificate and the
  hardened runtime, so permissions survive updates; not notarized by Apple.
- A DMG that opens as a drag-to-Applications window with a note on the
  one-time "Open Anyway" step, and a Homebrew cask (`autohush`) installed from
  this repository's tap, which removes the download quarantine.
- Scripts to create the signing certificate, build the app and DMG, prepare a
  release, and measure a music player's volume curve.

### For developers

- Music players sit behind one interface (`MusicPlayer`), so more can be
  added one at a time under `MusicPlayers/<App>/`; Spotify is the first.
- Swift 6 with strict concurrency; the test suite (Swift Testing) uses mock
  CoreAudio, level meter, power assertion and player implementations, so it
  never taps real audio or scripts a real player.
