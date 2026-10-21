# AutoHush Workflows

What AutoHush does, and what you can do with it, from launching it to quitting it, drawn as flowcharts. They follow the code; [README.md](README.md) says the same in words, and [DEVELOPMENT.md](DEVELOPMENT.md) how it's built.

**Reading them:** a rounded box is where a path starts; a diamond, a question that picks the branch; a dashed purple box, a step that goes on in another chart below; orange, something that went wrong or needs you; green, where a path settles; a dotted line, something that happens sometimes, or at any time.

- [Overview](#overview)
- [First launch and setup](#first-launch-and-setup)
- [Monitoring: pausing and resuming](#monitoring-pausing-and-resuming)
- [Monitoring: what else changes it](#monitoring-what-else-changes-it)
- [The player’s states](#the-players-states)
- [Pauses AutoHush holds](#pauses-autohush-holds)
- [Safari web apps: adding one](#safari-web-apps-adding-one)
- [Safari web apps: learning and pausing](#safari-web-apps-learning-and-pausing)
- [Add an App: before the check](#add-an-app-before-the-check)
- [Add an App: the check and its result](#add-an-app-the-check-and-its-result)
- [An added app in use](#an-added-app-in-use)
- [Updates](#updates)
- [Problems: when the player can’t start](#problems-when-the-player-cant-start)
- [Problems: while it runs, and quitting](#problems-while-it-runs-and-quitting)

## Overview

```mermaid
flowchart TD
  L(["AutoHush opens: at login,<br/>from the Dock, for a Shortcuts<br/>action, or after an update"])
  O["Copies opened before it quit,<br/>handing over their pauses"]
  C{"A media player<br/>chosen?"}
  W["First launch and setup:<br/>the welcome window"]
  S["Start: may AutoHush<br/>control the player?"]
  P{"Installed, allowed,<br/>answering?"}
  R["Problems and recovery:<br/>the card says why,<br/>tried again by itself"]
  M["Monitoring and deciding:<br/>another app plays, the player<br/>fades out and pauses; it stops,<br/>the player fades back in"]
  ST["The player’s states"]
  MENU["The menu bar menu: the card<br/>and Auto-Pause, the players,<br/>Turn off for, the apps playing<br/>and played, Ignored Apps,<br/>the settings' switches,<br/>the buttons (laid out in<br/>STYLE_GUIDE.md)"]
  CH["Choose another player:<br/>it’s started afresh"]
  WA["Add a Web App…:<br/>Safari web apps"]
  AA["Add an App…:<br/>the check"]
  AU["An added app in use"]
  SET["Settings: Sound Sources<br/>(ignore, remove, reset),<br/>detection, timings, fades,<br/>Calls (Pause for the microphone,<br/>Stay paused after calls),<br/>Advanced (Level the volume),<br/>Diagnostics"]
  UP["Updates"]
  Q["Quit: volume back, mutes<br/>lifted, pauses handed over"]
  RL(["The new version opens:<br/>back to the top"])
  QX(["AutoHush closed"])

  L --> O --> C
  C -->|"no"| W --> S
  C -->|"yes"| S
  S --> P
  P -->|"no"| R
  R -.->|"fixed"| S
  P -->|"yes"| M
  M -.- ST
  M -->|"shown in, set from"| MENU
  MENU --> CH
  MENU --> WA
  MENU --> AA --> AU
  MENU --> SET
  MENU --> UP
  MENU -->|"Quit"| Q
  UP -->|"install"| Q
  Q -->|"after an update"| RL
  Q -->|"otherwise"| QX

  class W,M,ST,WA,AA,AU,UP ref
  class R warn
  class QX done
  classDef ref fill:#f1e7fc,stroke:#8a3fd1,stroke-width:1.5px,stroke-dasharray: 5 3,color:#1d1b22
  classDef warn fill:#fff3e2,stroke:#c47812,stroke-width:1.5px,color:#1d1b22
  classDef done fill:#e6f5eb,stroke:#2f8a50,stroke-width:1.5px,color:#1d1b22
```

From opening to quitting. The copy of AutoHush opened last is the one that runs: any copy opened before it quits first and hands over the pauses it held. Once a player is chosen and AutoHush may control it, monitoring runs until it quits, and the menu bar menu leads to everything else. The dashed boxes are charts of their own below.

## First launch and setup

```mermaid
flowchart TD
  A(["First launch:<br/>no media player chosen"])
  NT["Notifications asked once,<br/>for updates (optional)"]
  W["The welcome window:<br/>Choose Your Media Player"]
  K{"Which tile?"}
  SUP["Supported Apps: Spotify,<br/>Apple Music, VLC, Apple<br/>Podcasts, TIDAL, QuickTime<br/>Player"]
  OTH["Other Apps: an app<br/>you added, Checked by you"]
  WEB["Safari Web Apps:<br/>the tested ones first,<br/>any other Untested"]
  ADDAPP["Add an App…"]
  ADDWEB["Add a Web App…<br/>(a tested site’s<br/>address filled in)"]
  CONT["Continue:<br/>it’s the media player"]
  PERM["Allow AutoHush to Work:<br/>only what this player needs"]
  CTRL{"How is it<br/>controlled?"}
  AUT["Automation: Spotify, Apple<br/>Music, VLC, QuickTime Player,<br/>an added app’s AppleScript.<br/>Open Spotify first, then<br/>macOS asks"]
  ACC["Accessibility: TIDAL,<br/>Apple Podcasts, web apps,<br/>added apps that are pressed.<br/>Allow… opens System Settings"]
  AUD{"Audio<br/>Recording"}
  ALW["Allow…: macOS asks,<br/>or System Settings,<br/>then Reopen AutoHush"]
  ANT["Use AntiDot Mode Instead:<br/>no audio permission,<br/>never the purple dot"]
  DONE["Done unlocks once<br/>every line ticks"]
  LRN{"A web app whose<br/>button isn’t learned?"}
  LW["The learning window"]
  RUN(["Monitoring starts"])
  LOG["Settings → General:<br/>Launch at login"]

  A --> W
  A -.-> NT
  W --> K
  K -->|"a supported app"| SUP --> CONT
  K -->|"an added app"| OTH --> CONT
  K -->|"a web app"| WEB --> CONT
  K -->|"Add… under Other Apps"| ADDAPP
  K -->|"a site to add, or Add…"| ADDWEB
  CONT --> PERM
  PERM --> CTRL
  PERM --> AUD
  CTRL -->|"by AppleScript"| AUT
  CTRL -->|"by pressing"| ACC
  AUD -->|"allow it"| ALW
  AUD -->|"not for an app only muted"| ANT
  AUT --> DONE
  ACC --> DONE
  ALW --> DONE
  ANT --> DONE
  DONE --> LRN
  LRN -->|"yes"| LW --> RUN
  LRN -->|"no"| RUN
  RUN -.->|"optional"| LOG

  class ADDAPP,ADDWEB,LW ref
  class RUN done
  classDef ref fill:#f1e7fc,stroke:#8a3fd1,stroke-width:1.5px,stroke-dasharray: 5 3,color:#1d1b22
  classDef done fill:#e6f5eb,stroke:#2f8a50,stroke-width:1.5px,color:#1d1b22
```

The welcome window opens whenever no media player is chosen. Its first page lists the players as tiles (dimmed when not installed; a search from eight players on). After **Continue**, its second page asks only for what that player needs, each line ticking by itself, with **Back** to change the player. A web app still to learn opens the learning window once the welcome window is done.

## Monitoring: pausing and resuming

```mermaid
flowchart TD
  S(["Monitoring runs: which<br/>apps have their sound on"])
  F{"Another app?"}
  OWN["The player itself,<br/>system sounds:<br/>never count"]
  IGN["An ignored app (display<br/>apps’ volume sound: ignored<br/>from their first run, and<br/>after Reset List…): listed<br/>under Playing Now, never pauses"]
  DM{"Detection"}
  NORM["Normal mode: its sound<br/>level, measured only while<br/>it matters (the purple dot);<br/>silent 10 s, not measured until<br/>its sound opens again or it<br/>tells macOS it plays (one that<br/>keeps saying so stays measured)"]
  ANTI["AntiDot mode: what it tells<br/>macOS (I’m playing), or any<br/>open sound (Open audio<br/>streams only); sound without<br/>video must play 3 s (any<br/>sound 2 s, with open streams)"]
  MIC["Pause for the microphone<br/>on: its microphone on<br/>for 1 s counts, sound or<br/>not (the card: “is using<br/>the microphone”)"]
  T{"Playing<br/>for 0.5 s?"}
  TONE["Too short: a notification<br/>or chat tone, ignored"]
  AP{"Auto-Pause on,<br/>the player playing<br/>on this Mac?"}
  LEFT["Left alone"]
  TOOK["It stopped just as the app<br/>started (VLC pauses others):<br/>counted as AutoHush’s pause"]
  FO["Fade out over 1 s, then<br/>pause; the volume set back<br/>while paused (no fade without<br/>a readable volume)"]
  BACK["The app stops during<br/>the fade-out: the music<br/>comes back up, not paused"]
  YOURS["You pause it during the<br/>fade-out: your volume set<br/>back, and it stays yours<br/>(never resumed)"]
  PC{"Did the<br/>pause take?"}
  FAIL["Not within 3 s, nor after a<br/>second press: Couldn’t pause<br/>— Safari is playing, with ⓘ;<br/>it plays on"]
  PA["Paused by AutoHush"]
  Q{"Every app quiet<br/>for 2 s?"}
  MORE["More apps start or<br/>play on: it stays paused"]
  CHK{"Still paused as<br/>AutoHush left it?"}
  USER["Not resumed: you played,<br/>paused or quit it yourself"]
  RETRY["No answer: tried twice<br/>more, a second apart"]
  CALL{"Stay paused after<br/>calls on, and a call<br/>came during the pause?"}
  STAY["Stays paused: you<br/>play it when ready"]
  LVL["Level the volume on, the apps<br/>quieter: the Mac’s volume<br/>lowered to match (10 dB at<br/>most, 2 dB at least, by<br/>default), back up at the next<br/>fade-out unless you changed it<br/>(no resume after all: at once;<br/>after a crash: at the next<br/>launch, within the hour)"]
  FI(["Played and faded in<br/>over 2 s, to your volume"])

  S --> F
  F -->|"no"| OWN
  F -->|"ignored"| IGN
  F -->|"yes"| DM
  DM -->|"normal"| NORM --> T
  DM -->|"AntiDot mode"| ANTI --> T
  F -.->|"its microphone on"| MIC --> AP
  T -->|"no"| TONE
  T -->|"yes"| AP
  AP -->|"no"| LEFT
  AP -->|"it just stopped"| TOOK --> PA
  AP -->|"yes"| FO
  FO -.->|"the app stops first"| BACK
  FO -.->|"you pause it"| YOURS
  FO --> PC
  PC -->|"no"| FAIL
  PC -->|"yes"| PA
  FAIL -.->|"the apps stop"| LEFT
  PA --> Q
  Q -->|"no"| MORE --> Q
  Q -->|"yes"| CHK
  CHK -->|"no"| USER
  CHK -->|"no answer"| RETRY --> CHK
  CHK -->|"yes"| CALL
  CALL -->|"yes"| STAY
  CALL -->|"no"| FI
  CALL -.->|"no, and quieter apps"| LVL --> FI

  class FAIL warn
  class FI,USER,YOURS,STAY done
  classDef warn fill:#fff3e2,stroke:#c47812,stroke-width:1.5px,color:#1d1b22
  classDef done fill:#e6f5eb,stroke:#2f8a50,stroke-width:1.5px,color:#1d1b22
```

What happens each time another app plays. With several apps, the first one to play pauses the player and the last one to stop brings it back. The 0.5 s and 2 s are Settings → Detection’s timings, the fades Settings → Fades’, Pause for the microphone and Stay paused after calls Settings → Calls’, and Level the volume Settings → Advanced’s (all off by default); a call is an app using the microphone; TIDAL, Apple Podcasts, web apps and most added apps pause and play without fading. A player on another device (Spotify Connect) is never paused.

## Monitoring: what else changes it

```mermaid
flowchart LR
  subgraph YOU["You"]
    direction TB
    E1["You pause, play or quit<br/>the player yourself"]
    E2["It plays on another device<br/>(Spotify Connect)"]
    E3["You choose another player<br/>while AutoHush holds one paused"]
  end
  subgraph AUTO["Auto-Pause"]
    direction TB
    E4["Auto-Pause off: the card<br/>(its switch, or a click on it),<br/>Set Auto-Pause in Shortcuts"]
    E5["Turn off for 5 minutes<br/>to 24 hours: the menu,<br/>Shortcuts"]
    E6["A Focus with AutoHush’s<br/>filter starts or ends"]
  end
  subgraph MAC["The Mac and AutoHush"]
    direction TB
    E7["The Mac goes to sleep"]
    E8["The Mac wakes up"]
    E9["AutoHush quits holding a<br/>pause: an update, another<br/>copy, a reopen"]
    E10["Add an App’s check runs"]
  end
  R1["Your choice stands: never<br/>resumed or overridden"]
  R2["Left alone: Playing<br/>on another device"]
  R3["A held pause: resumed when<br/>the apps stop, unless you play<br/>or quit it first; chosen again,<br/>it’s taken back"]
  R4["What AutoHush paused comes<br/>back at once; nothing new<br/>is paused"]
  R5["Back on by itself: apps still<br/>playing pause the player once<br/>measured again"]
  R6["Auto-Pause follows the Focus,<br/>then goes back as it was,<br/>unless you changed it"]
  R7["The pause is forgotten: the<br/>player stays paused after<br/>waking; nothing is paused or<br/>resumed while asleep"]
  R8["Apps playing pause<br/>the player as usual"]
  R9["The hand-over: the next<br/>AutoHush, opened within<br/>a minute, takes it over"]
  R10["Paused while a check runs:<br/>nothing is resumed until<br/>it ends"]

  E1 --> R1
  E2 --> R2
  E3 --> R3
  E4 --> R4
  E5 --> R4
  E5 -->|"when it ends"| R5
  E6 --> R6
  E7 --> R7
  E8 --> R8
  E9 --> R9
  E10 --> R10
```

The events, besides other apps’ sound, that change what AutoHush does. Shortcuts’ **Get Auto-Pause** only reads the switch, and **Set Auto-Pause** On also ends a Turn off for. A Focus or a Shortcuts action works even when AutoHush isn’t running: macOS opens it, and a Focus that started or ended meanwhile is followed at launch.

## The player’s states

```mermaid
stateDiagram-v2
  state "Starting" as Unknown
  state "Playing on this Mac" as Playing
  state "On another device" as Elsewhere
  state "Not playing" as Idle
  state "Fading out" as FadingOut
  state "Paused by AutoHush" as PausedByUs
  state "Muted instead" as Muted
  state "Couldn’t pause" as Failed
  state "Fading in" as FadingIn

  [*] --> Unknown
  Unknown --> Playing : it plays
  Unknown --> Idle : it doesn’t
  Playing --> FadingOut : another app plays
  FadingOut --> PausedByUs : paused
  PausedByUs --> FadingIn : the apps stop
  FadingIn --> Playing : faded in
  FadingOut --> Failed : the pause fails
  FadingOut --> Playing : it stops first
  FadingIn --> FadingOut : an app starts again
  Failed --> Playing : the apps stop
  Playing --> Muted : it won’t pause
  Muted --> PausedByUs : it can pause again
  Muted --> Playing : the apps stop
  Playing --> Elsewhere : another device
  Elsewhere --> Playing : back here
  Playing --> Idle : you pause or quit it
  Idle --> Playing : you play it
  Idle --> PausedByUs : the app paused it
  PausedByUs --> Idle : you quit it, the Mac sleeps
  PausedByUs --> Playing : you play it

  class Failed warn
  class PausedByUs,Muted ref
  classDef ref fill:#f1e7fc,stroke:#8a3fd1,stroke-width:1.5px,stroke-dasharray: 5 3,color:#1d1b22
  classDef warn fill:#fff3e2,stroke:#c47812,stroke-width:1.5px,color:#1d1b22
```

The chosen player as the menu’s card and the menu bar icon show it. **Not playing** is a player paused by you, stopped or quit: AutoHush never plays it, but takes over a pause the starting app made itself (VLC). **Muted instead** is a web app during an ad it won’t pause, or an app added as Muted only (Unmute ends it too). **The apps stop** means every other app quiet for 2 s, or Auto-Pause turned off.

## Pauses AutoHush holds

```mermaid
stateDiagram-v2
  direction LR
  state "Paused by AutoHush" as Ours
  state "Paused while a check runs" as Check
  state "Held pause" as Held
  state "Handed over" as Handed
  state "Resumed" as Resumed
  state "Yours, left as it is" as Yours

  [*] --> Ours : another app plays
  Ours --> Resumed : the apps stop
  Ours --> Check : a check starts
  Check --> Ours : it ends
  Ours --> Held : another player chosen
  Held --> Ours : chosen again
  Held --> Resumed : the apps stop
  Ours --> Handed : AutoHush quits
  Handed --> Ours : reopened within a minute
  Handed --> Yours : later
  Ours --> Yours : you play or quit it, the Mac sleeps
  Held --> Yours : you play or quit it, the Mac sleeps
  Resumed --> [*]
  Yours --> [*]

  class Ours,Check,Held,Handed ref
  class Resumed,Yours done
  classDef ref fill:#f1e7fc,stroke:#8a3fd1,stroke-width:1.5px,stroke-dasharray: 5 3,color:#1d1b22
  classDef done fill:#e6f5eb,stroke:#2f8a50,stroke-width:1.5px,color:#1d1b22
```

AutoHush only ever resumes a pause it holds, and it keeps holding one across a check, a change of player and a quit. A **held pause** is a player you left while AutoHush had it paused: its own monitoring runs on to end the pause. A **hand-over** is written as AutoHush quits (an update, another copy, a quick reopen) and read once by the next one.

## Safari web apps: adding one

```mermaid
flowchart TD
  ST(["Add a Web App…: the menu,<br/>Settings → General,<br/>the welcome window"])
  SUG(["A tested site’s tile, not<br/>added yet: Spotify, YouTube<br/>Music, Amazon Music,<br/>Deezer, SoundCloud"])
  ADDR["Paste the website’s address<br/>(a tested site’s is filled in;<br/>Amazon Music: your<br/>account’s country)"]
  CHK{"A web address,<br/>and the site answers?"}
  ERR["The window says why:<br/>not a web address, no<br/>answer, page not found"]
  DUP{"A web app for<br/>this site already?"}
  USE["That one is used,<br/>not added again"]
  ACC{"Accessibility<br/>allowed?"}
  ACCN["The window asks<br/>for it, with Allow…"]
  OPEN["Opens the site in Safari<br/>and waits for it to load"]
  ASKS{"Does the site<br/>ask first?"}
  ANS["Answer the site in Safari<br/>(cookies, sign-in): waits<br/>until the site itself shows"]
  BTN["Click Add to Dock<br/>in AutoHush’s window"]
  DLG["Safari’s own Add to Dock<br/>window: name the web app,<br/>click Add"]
  OUT{"Added?"}
  AGAIN["Cancelled there: the step<br/>says so, Add to Dock<br/>opens it again"]
  MADE["The new web app appears<br/>(within 20 s); the Safari tab<br/>AutoHush opened is closed"]
  CHO["Chosen as the media<br/>player, and opened"]
  LRN["Learning its controls,<br/>in the same window"]
  STOP["Cancel, or closing the<br/>window: nothing is added"]

  ST --> ADDR
  SUG --> ADDR
  ADDR --> CHK
  CHK -->|"no"| ERR --> ADDR
  CHK -->|"yes"| DUP
  DUP -->|"yes"| USE --> CHO
  DUP -->|"no"| ACC
  ACC -->|"no"| ACCN --> ACC
  ACC -->|"yes"| OPEN --> ASKS
  ASKS -->|"yes"| ANS --> BTN
  ASKS -->|"no"| BTN
  BTN --> DLG --> OUT
  OUT -->|"Cancel"| AGAIN --> BTN
  OUT -->|"Add"| MADE --> CHO --> LRN
  BTN -.->|"before Add"| STOP

  class LRN ref
  class ERR,AGAIN,STOP warn
  classDef ref fill:#f1e7fc,stroke:#8a3fd1,stroke-width:1.5px,stroke-dasharray: 5 3,color:#1d1b22
  classDef warn fill:#fff3e2,stroke:#c47812,stroke-width:1.5px,color:#1d1b22
```

Safari’s own **Add to Dock** makes the web app; AutoHush walks you there, its window staying above other apps in the top-right corner. It asks the site once whether it answers, without cookies or a cache. Any website added to the Dock from Safari by hand is offered as a player too, marked Untested unless it’s one of the five tested sites.

## Safari web apps: learning and pausing

```mermaid
flowchart TD
  WH{"Which browser<br/>made it?"}
  CHROM["Chrome, Brave or another<br/>Chromium browser: added with<br/>Add an App…, pressed on its<br/>page through the browser’s<br/>switch for assistive tools"]
  CH["A Safari web app is<br/>chosen as the player"]
  KN{"Its Play/Pause<br/>button learned?"}
  LW["The learning window,<br/>above other apps (its first<br/>step asks for Accessibility<br/>if needed)"]
  PLAY["Play something in it (log<br/>in first), then click<br/>It’s Playing"]
  CAN{"Heard, and its<br/>page readable?"}
  WHY["The step says why:<br/>not heard, no window,<br/>buttons without names"]
  NP{"Is the web app<br/>Now Playing?"}
  KEY["Let AutoHush pause it:<br/>the keyboard’s<br/>Play/Pause key"]
  CHG{"A button<br/>changed?"}
  FAILK["Pressed again to undo it:<br/>Try Again, or<br/>Pause It Yourself"]
  MAN["Pause it yourself, then<br/>It’s Paused (within a minute,<br/>else it starts over)"]
  DONE["Learned: the button’s two<br/>words and place; played<br/>again, the window closes"]
  LATER["Later: the Controls row says<br/>not learned, with Learn<br/>Controls…; nothing is pressed"]
  PRESS["Another app plays: AutoHush<br/>presses the site’s Pause,<br/>without a fade, and checks it"]
  REF{"Did the<br/>site pause?"}
  MUTE["It won’t (an ad, a disabled<br/>button, a press ignored or<br/>failed): muted instead (Audio<br/>Recording, not in AntiDot mode)"]
  REAL["The site can pause<br/>again: paused for real,<br/>and unmuted"]
  RES(["The apps stop: Play<br/>pressed, or the mute lifted"])
  NOMUTE["In AntiDot mode nothing is<br/>muted: an ad (its button says<br/>Play) plays on, nothing shown;<br/>a refused press says<br/>Couldn’t pause"]
  LOST["Its button not found for<br/>a minute while it plays:<br/>asks you again"]
  AGN["Learn Again…: a new<br/>learning window; the old<br/>button works until<br/>It’s Playing"]

  WH -->|"Safari"| CH
  WH -->|"Chromium"| CHROM
  CH --> KN
  KN -->|"no"| LW --> PLAY --> CAN
  CAN -->|"no"| WHY --> PLAY
  CAN -->|"yes"| NP
  NP -->|"yes"| KEY --> CHG
  NP -->|"no, another app is"| MAN
  CHG -->|"yes"| DONE
  CHG -->|"no"| FAILK
  FAILK -->|"Try Again"| KEY
  FAILK -->|"Pause It Yourself"| MAN --> DONE
  LW -.->|"Later"| LATER
  LATER -.->|"Learn Controls…"| LW
  KN -->|"yes"| PRESS
  DONE --> PRESS
  PRESS --> REF
  REF -->|"yes"| RES
  REF -->|"no"| MUTE
  REF -->|"no, AntiDot mode"| NOMUTE
  MUTE --> REAL --> RES
  MUTE -->|"the apps stop first"| RES
  PRESS -.-> LOST -.-> LW
  AGN -.-> LW

  class CHROM ref
  class WHY,FAILK,LATER,NOMUTE warn
  class DONE,RES done
  classDef ref fill:#f1e7fc,stroke:#8a3fd1,stroke-width:1.5px,stroke-dasharray: 5 3,color:#1d1b22
  classDef warn fill:#fff3e2,stroke:#c47812,stroke-width:1.5px,color:#1d1b22
  classDef done fill:#e6f5eb,stroke:#2f8a50,stroke-width:1.5px,color:#1d1b22
```

A web app can’t be scripted and has no playback menu, so AutoHush learns its Play/Pause button with you once (it keeps only the button’s two words and place), then presses it. It works with the window visible, minimized or on another desktop, and follows the window that plays. Muting during an ad uses macOS’s per-app audio taps: without Audio Recording, or in AntiDot mode, that pause fails instead.

## Add an App: before the check

```mermaid
flowchart TD
  ST(["Add an App…: after Other Apps<br/>in the menu, or the Add… tile<br/>in Settings → General or<br/>the welcome window"])
  KEPT{"A finished check<br/>kept from the last day?"}
  RES["Back at its last step,<br/>to choose a way and Use"]
  CHO["1 · Choose an App…: the apps<br/>that can play, Now Playing’s<br/>first, with a search (not Apple’s<br/>other apps, not supported players)"]
  OTH["Other App…:<br/>any app on the disk"]
  OK{"Can it be<br/>checked?"}
  NO["Refused, saying why: not<br/>an app, AutoHush supports it<br/>already, or AutoHush itself"]
  OPEN["Opened in the background,<br/>if it isn’t open"]
  ALW["2 · Allow: Accessibility (needed),<br/>Audio Recording and Automation<br/>(optional; Automation only for<br/>a scriptable app)"]
  ALL{"All allowed?"}
  WARN["A note says what the check<br/>does without the rest,<br/>with Continue"]
  NEED{"An Electron app<br/>opened without<br/>its option?"}
  REO["3 · Reopen it (what it plays<br/>stops), or Skip: then paused<br/>only while its window<br/>can be seen"]
  PLAY["4 · Play something in it<br/>(heard by its sound; without<br/>Audio Recording or in AntiDot<br/>mode, by an open output)"]
  PL{"Playing within<br/>2 minutes?"}
  NOPL["It didn’t play, or quit:<br/>Try Again, or open it again"]
  CHK["5 · The check: Continue…<br/>shows the warning first"]

  ST --> KEPT
  KEPT -->|"yes"| RES
  KEPT -->|"no"| CHO
  CHO -->|"from the list"| OPEN
  CHO --> OTH --> OK
  OK -->|"no"| NO --> CHO
  OK -->|"yes"| OPEN
  OPEN --> ALW --> ALL
  ALL -->|"yes, goes on by itself"| NEED
  ALL -->|"Accessibility only"| WARN --> NEED
  NEED -->|"yes"| REO --> PLAY
  NEED -->|"no"| PLAY
  PLAY --> PL
  PL -->|"yes"| CHK
  PL -->|"no"| NOPL --> PLAY

  class CHK,RES ref
  class NO,NOPL warn
  classDef ref fill:#f1e7fc,stroke:#8a3fd1,stroke-width:1.5px,stroke-dasharray: 5 3,color:#1d1b22
  classDef warn fill:#fff3e2,stroke:#c47812,stroke-width:1.5px,color:#1d1b22
```

Add an App checks an app AutoHush has no support of its own for. Its window numbers the steps; **Reopen** shows only for an app built with Electron (Deezer, Qobuz…) opened without the option its page needs while covered or on another desktop. **Change…** picks another app (once the check has run, after asking, since it forgets what was found); a web app made by a Chromium browser shows that browser’s icon.

## Add an App: the check and its result

```mermaid
flowchart TD
  WARN(["The warning: what the<br/>check does, for about<br/>3 minutes"])
  GO{"Start?"}
  BACK["Cancel: back<br/>to step 5"]
  RUN["The check runs in AutoHush’s<br/>helper; AutoHush’s own player<br/>stays as it is (Paused while<br/>a check runs)"]
  BLOCK["The screen dimmed; clicks,<br/>scrolling and keys blocked;<br/>a panel at the bottom right:<br/>progress and Stop"]
  MUTE["The app muted meanwhile:<br/>on its own (Audio Recording,<br/>not in AntiDot mode), else<br/>the Mac’s output (and any the<br/>sound moves to), put back after"]
  STATES["Its window in 7 states: in<br/>view, covered, on another<br/>desktop, covered there, full<br/>screen, minimized, hidden"]
  WAYS["In each state, each way<br/>pauses and plays it: its<br/>AppleScript, playback menu,<br/>page’s Play/Pause, Now<br/>Playing row"]
  ASK["It asks you to pause it<br/>yourself (to learn its page):<br/>mouse and keyboard yours"]
  SHOW["Now Playing hidden in<br/>the menu bar: shown for<br/>the moment of a press"]
  STOP["Escape, or Stop"]
  PUT["Windows, desktops<br/>and sound put back<br/>as they were"]
  HOW{"How did<br/>it end?"}
  PERM["A permission<br/>missing: back<br/>to step 2"]
  FAIL["It couldn’t finish<br/>(the app quit or moved):<br/>Show Log…, Check Again"]
  STOPPED["Stopped:<br/>Check Again"]
  KEEP["The result kept<br/>for a day, until Use"]
  ANY{"Did a way AutoHush<br/>can use work?"}
  CARDS["6 · Cards of the ways that<br/>worked, Recommended first;<br/>those that didn’t, with why"]
  USE["Use: added under Other<br/>Apps, Checked by you, made<br/>the media player"]
  NPH["Now Playing couldn’t be<br/>shown: Open Menu Bar<br/>Settings…, then Check Again"]
  MUT{"Audio Recording<br/>allowed, AntiDot<br/>mode off?"}
  MII["Mute It Instead: added<br/>as Muted only, made<br/>the media player"]
  ANTI["Turn Off AntiDot Mode,<br/>or allow Audio Recording;<br/>or Check Again"]

  WARN --> GO
  GO -->|"Cancel"| BACK
  GO -->|"Start"| RUN
  RUN --> BLOCK
  RUN --> MUTE
  BLOCK --> STATES
  MUTE --> STATES
  STATES --> WAYS
  WAYS -.->|"a page to learn"| ASK
  WAYS -.->|"the panel"| SHOW
  BLOCK -.->|"any time"| STOP
  STOP --> PUT
  WAYS --> PUT
  PUT --> HOW
  HOW -->|"finished"| KEEP --> ANY
  HOW -->|"permission missing"| PERM
  HOW -->|"failed"| FAIL
  HOW -->|"stopped"| STOPPED
  ANY -->|"yes"| CARDS --> USE
  CARDS -.->|"Now Playing not shown"| NPH
  ANY -->|"no"| MUT
  MUT -->|"yes"| MII
  MUT -->|"no"| ANTI

  class USE,MII ref
  class FAIL,STOPPED,PERM,NPH,ANTI warn
  classDef ref fill:#f1e7fc,stroke:#8a3fd1,stroke-width:1.5px,stroke-dasharray: 5 3,color:#1d1b22
  classDef warn fill:#fff3e2,stroke:#c47812,stroke-width:1.5px,color:#1d1b22
```

The check runs in AutoHush’s helper, playercheck, so a check that ends, stops or crashes takes its block on the mouse and keyboard with it; the pointer still moves, and the panel shows on every desktop. The ways come surest first (AppleScript, page, menu), the Now Playing panel last, since it opens on screen for a moment. **Use** keeps only the way you chose.

## An added app in use

```mermaid
flowchart TD
  P(["An added app is<br/>the media player"])
  RE{"Opened without<br/>its option?"}
  ALERT["When it’s chosen, an alert:<br/>Reopen or Cancel; with Always<br/>reopen ticked, no more asking"]
  CARD["The icon shows !, the<br/>card says it needs<br/>reopening, with Reopen"]
  WAY{"The way chosen<br/>at Use"}
  SCR["Its AppleScript<br/>(fades when it<br/>has a volume)"]
  PAGE["Its page’s Play/Pause<br/>(its switch for assistive<br/>tools kept on)"]
  MENU["Its playback<br/>menu’s Play/Pause"]
  PANEL["Its row in the menu bar’s<br/>Now Playing panel (shown<br/>for about half a second)"]
  HID{"Now Playing<br/>hidden?"}
  SHOWN["Shown for the press, then<br/>hidden again; put back<br/>even after a crash"]
  CANT["It can’t be shown:<br/>the pause fails, saying<br/>where to show it"]
  STALE{"Its row<br/>follows it?"}
  HEAR["Heard for half a second<br/>before a pause or a resume,<br/>the row pressed as a toggle<br/>(Audio Recording)"]
  TOOK{"Did the<br/>press take?"}
  FAIL["Couldn’t pause,<br/>with ⓘ"]
  OKP(["Paused; played again<br/>when the other apps stop"])
  MUTE["Muted only (Mute It<br/>Instead): muted while other<br/>apps play, never paused"]
  MUTED["Muted — Safari<br/>is playing, with Unmute"]
  UNM["Unmute, or you pause and<br/>play it (stopped 3 s or more):<br/>heard again, left alone<br/>until the apps stop"]
  ANTI["In AntiDot mode: dimmed,<br/>Not in AntiDot; while it’s<br/>the player, the AntiDot<br/>switch is off and dimmed"]
  subgraph ANY["At any time"]
    direction TB
    REM["Remove: × on its tile,<br/>right-click it, or ⌥ Option<br/>in the menu’s list; asked first"]
    GONE["Forgotten; if it was the<br/>player, the window to<br/>choose another opens"]
    QUIT["AutoHush quits: always<br/>unmuted, its switch<br/>turned back off"]
  end

  P --> RE
  RE -->|"yes"| ALERT
  ALERT -->|"Cancel"| CARD
  ALERT -->|"Reopen"| WAY
  CARD -->|"Reopen"| WAY
  RE -->|"no"| WAY
  WAY --> SCR --> TOOK
  WAY --> PAGE --> TOOK
  WAY --> MENU --> TOOK
  WAY --> PANEL --> HID
  HID -->|"yes"| SHOWN --> STALE
  HID -->|"can’t show it"| CANT
  HID -->|"no"| STALE
  STALE -->|"no (Qobuz)"| HEAR --> TOOK
  STALE -->|"yes"| TOOK
  TOOK -->|"no"| FAIL
  TOOK -->|"yes"| OKP
  WAY --> MUTE --> MUTED --> UNM
  MUTE -.-> ANTI
  HEAR -.-> ANTI
  OKP ~~~ REM
  REM --> GONE
  GONE ~~~ QUIT

  class FAIL,CANT,CARD warn
  class OKP done
  classDef warn fill:#fff3e2,stroke:#c47812,stroke-width:1.5px,color:#1d1b22
  classDef done fill:#e6f5eb,stroke:#2f8a50,stroke-width:1.5px,color:#1d1b22
```

An app added with Add an App is paused and played only the one way chosen at Use, each press checked by the app’s own signs; when that way can’t (a page’s button with the window minimized, say), the pause fails and the menu says so. Only an AppleScript with a volume fades. An app that can only be muted, or whose Now Playing row needs its sound, isn’t available in AntiDot mode.

## Updates

```mermaid
flowchart TD
  AUTO(["An automatic check:<br/>GitHub, once a day"])
  ASK(["Updates in the menu,<br/>or Check Now in Settings"])
  NEW{"A newer<br/>version?"}
  UTD["Up to date, or it<br/>couldn’t check: said<br/>only when you asked"]
  CAN{"Can this copy<br/>install it?"}
  HAND["By hand: Homebrew, or Open<br/>Release Page (a folder it can’t<br/>write to, or a copy signed<br/>with another certificate)"]
  MODE{"Settings → Updates:<br/>when an update<br/>is found"}
  NOT["A notification; the icon’s<br/>arrow, Updates in the accent<br/>color, Install AutoHush in<br/>the menu"]
  DL["Downloaded (not in<br/>Low Data Mode), kept<br/>up to 7 days"]
  AI["Waits for a quiet moment:<br/>no pause held, no window<br/>or menu open"]
  OFFER["The offer, with what’s new:<br/>Download and Install (or Install<br/>and Relaunch), Open Release<br/>Page, Later"]
  LATER["Later: still offered<br/>in the menu"]
  PREP["Downloaded, or the kept<br/>download, then checked:<br/>GitHub’s checksum, the version,<br/>the same developer team, and<br/>the macOS it needs"]
  OK{"Checked, and<br/>still quiet?"}
  BUSY["Got busy meanwhile<br/>(automatic): at the next<br/>quiet moment"]
  ERR["Couldn’t install (it needs a newer<br/>macOS, say): an alert with Open<br/>Release Page if you asked, else a<br/>notification; not tried again<br/>until AutoHush reopens; a copy<br/>not swapped in goes to the Trash"]
  SWAP["The new version<br/>swapped in"]
  QUIT["AutoHush quits: volume<br/>back, the pause it held<br/>handed over"]
  OPEN(["The new version opens in<br/>about a second, takes the<br/>pause over, says it was updated"])

  AUTO --> NEW
  ASK --> NEW
  NEW -->|"no"| UTD
  NEW -->|"yes"| CAN
  CAN -->|"no"| HAND
  CAN -->|"yes, you asked"| OFFER
  CAN -->|"yes, automatic"| MODE
  MODE -->|"Notify me"| NOT
  MODE -->|"Download it and notify me"| DL --> NOT
  MODE -->|"Install it automatically (default)"| AI --> PREP
  NOT -->|"clicked"| OFFER
  OFFER -->|"Install"| PREP
  OFFER -->|"Open Release Page"| HAND
  OFFER -->|"Later"| LATER
  PREP --> OK
  OK -->|"busy"| BUSY
  OK -->|"failed"| ERR
  OK -->|"yes"| SWAP --> QUIT --> OPEN

  class ERR,BUSY warn
  class OPEN done
  classDef warn fill:#fff3e2,stroke:#c47812,stroke-width:1.5px,color:#1d1b22
  classDef done fill:#e6f5eb,stroke:#2f8a50,stroke-width:1.5px,color:#1d1b22
```

Settings → Updates sets what happens when an update is found, and can turn the automatic checks off. Notifications are optional: without them every choice still works and the menu bar icon shows the update. Settings, permissions and any pause AutoHush held carry over to the new version.

## Problems: when the player can’t start

```mermaid
flowchart TD
  S(["AutoHush starts the<br/>player, or checks it again"])
  W{"What’s wrong?"}
  INS["Isn’t installed:<br/>the folders watched"]
  RUN["Isn’t running: nothing to do<br/>(the card in grey); waits<br/>for it to open, then<br/>3 tries, 2 s apart; meanwhile,<br/>with Auto-Pause on, the menu<br/>lists the apps playing"]
  RESP["Isn’t responding:<br/>tried again after 5 s,<br/>doubling up to a minute;<br/>Try Again on the card"]
  CTRL["Can’t control it<br/>right now: ⓘ says why;<br/>tried again likewise"]
  PERM["A permission missing:<br/>the card in orange,<br/>with Allow…"]
  MACOS["macOS’s own prompt,<br/>or System Settings<br/>(Automation: the<br/>player opened first)"]
  TRY["Looked at again<br/>every 3 s"]
  AGAIN["Started again by itself:<br/>once it’s back, opens,<br/>answers or is allowed"]
  READY(["Ready: monitoring runs"])
  LOST["A permission taken away<br/>later: noticed when another<br/>app plays or the menu opens,<br/>then asked for as above"]

  S --> W
  W -->|"nothing"| READY
  W --> INS --> AGAIN
  W --> RUN --> AGAIN
  W --> RESP --> AGAIN
  W --> CTRL --> AGAIN
  W --> PERM --> MACOS --> TRY --> AGAIN
  AGAIN --> READY
  READY -.-> LOST

  class INS,RUN,RESP,CTRL,PERM,LOST warn
  class READY done
  classDef warn fill:#fff3e2,stroke:#c47812,stroke-width:1.5px,color:#1d1b22
  classDef done fill:#e6f5eb,stroke:#2f8a50,stroke-width:1.5px,color:#1d1b22
```

What the menu’s card says when AutoHush can’t start controlling the player, and how it recovers. Most fixes need nothing more from you: AutoHush starts again by itself, at once when the player opens or is installed again. A permission taken away while it runs is caught the next time it matters.

## Problems: while it runs, and quitting

```mermaid
flowchart TD
  R(["Monitoring runs"])
  AUD["Audio Recording not allowed:<br/>it still works, as AntiDot mode<br/>does (its waits too): any open<br/>sound counts, so a paused video<br/>may keep the player paused"]
  AUDF["Allow… in the menu or<br/>Detection; switched on in<br/>System Settings: Reopen<br/>AutoHush. Or AntiDot mode"]
  PF["A pause fails or is<br/>ignored: Couldn’t pause —<br/>Safari is playing, with ⓘ"]
  NPH["Now Playing hidden and<br/>couldn’t be shown: ⓘ offers<br/>Open Menu Bar Settings…"]
  DIAG["Settings → Diagnostics:<br/>what AutoHush sees, Last<br/>error, Copy Report (⌥ Option-<br/>click Settings in the menu)"]
  LOGS["Show Logs…: this launch<br/>or 24 hours, every entry or<br/>only problems; copy or save"]
  CHK["Add an App’s check couldn’t<br/>finish: Show Log… (the<br/>check’s own log), Check Again"]
  DEL["The chosen web app deleted:<br/>no player chosen; the window<br/>to choose another opens"]
  QUIT["Quitting, within a second:<br/>fades stopped, volume back,<br/>mutes lifted, switches off,<br/>Now Playing put back, the<br/>Mac’s output unmuted,<br/>pauses handed over"]
  NEXT(["The next launch: a press<br/>cut short put right, the Mac’s<br/>output unmuted, its volume<br/>put back if lowered within<br/>the hour, a pause handed<br/>over taken over"])

  R -.-> AUD --> AUDF
  R -.-> PF
  PF -.->|"Now Playing way"| NPH
  PF --> DIAG --> LOGS
  R -.-> CHK
  R -.-> DEL
  R -->|"Quit"| QUIT --> NEXT

  class AUD,PF,NPH,CHK,DEL warn
  class NEXT done
  classDef warn fill:#fff3e2,stroke:#c47812,stroke-width:1.5px,color:#1d1b22
  classDef done fill:#e6f5eb,stroke:#2f8a50,stroke-width:1.5px,color:#1d1b22
```

Problems that don’t stop monitoring, where to look when something seems off, and what quitting puts right. AutoHush’s own log keeps the last 24 hours in **~/Library/Logs/AutoHush**, private details left out; each check’s log is in its **Checks** folder.
