# AutoHush Style Guide

How AutoHush looks and reads, so every change fits in. It covers the menu,
the Settings window, the other windows (welcome, Add a Web App, learning,
Add an App and its own) and every text the app shows. When something isn't
covered here, match the screens that already exist, then macOS's own
conventions
([Apple's Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)).

## Contents

- [Principles](#principles)
- [Layout](#layout)
- [Text sizes](#text-sizes)
- [Colors](#colors)
- [Components](#components)
- [Lists and searches](#lists-and-searches)
- [Writing](#writing)
- [Translations](#translations)
- [Right to left](#right-to-left)
- [Accessibility](#accessibility)
- [Keyboard](#keyboard)
- [Checking a change](#checking-a-change)

## Principles

- **macOS draws it.** Text uses macOS's text styles; the controls are
  macOS's own (switches, push buttons, segmented controls, sliders, pop-ups,
  group boxes); the colors are macOS's, as it draws them in each mode;
  Settings' pages are macOS's grouped forms. So AutoHush looks like the
  macOS it runs on, and follows it when macOS changes. AutoHush draws only
  what macOS has no control for: the players' tiles, the badges, the menu's
  panel and its card. Settings' sidebar keeps its own sizes.
- **Liquid Glass from macOS 26, the same app before.** On macOS 26 and later
  macOS draws its controls and forms with Liquid Glass, and the menu's card
  is clear glass; on macOS 14.4 and 15 they look as macOS draws them there. Glass
  of AutoHush's own only ever goes behind `if #available(macOS 26, *)`, with
  the earlier look as the fallback: AutoHush still runs on macOS 14.4. `Scripts/build-app.sh` records the SDK the app was built with, or
  macOS 26 and later would draw all of it the old way. Before macOS 26,
  Settings' title bar is see-through (the toolbar would draw a lighter
  band of its own over the page); the thin line beside its sidebar is
  macOS 14 and 15's own, as in Finder and System Settings, and stays.
- **One way to do each thing.** Use the shared components below rather than
  styling a screen by hand. A new pattern goes into the shared files, and
  into this guide, before it's used.
- **Easy to read.** Text keeps a contrast of at least 4.5:1 against its
  background, except where it's in macOS's own colors (its secondary
  label, orange, the accent color), which it keeps as macOS draws them,
  in light mode too.
- **Calm.** Nothing is red. Things move only when they change: rows that
  reorder slide into place. Besides that, only what shows AutoHush at work
  moves: a spinner while it does a step itself, and a countdown while time
  runs out; and a note that answers a click blinks for a moment (see
  `ChoiceChips`).

The shared files are in `Sources/AutoHushApp/Views/Components/`, one
component and its small parts per file: `Font+AutoHush.swift` holds the
text sizes, `AppearanceStyle.swift` the colors and `View+CaptionStyle.swift`
the caption style, `View+ChosenOutline.swift` the chosen look;
`ButtonStyles.swift`, `MainButton.swift`,
`FlowingButtons.swift`, `Highlightable.swift`, `Card.swift`,
`SectionHeading.swift`, `SwitchRow.swift`, `ChoiceChips.swift`,
`BottomBar.swift`, `PlayerTiles.swift`, `PlayerIcon.swift`,
`WindowHeader.swift`, `WindowPage.swift`, `ChecklistStepRow.swift`,
`StepSymbol.swift`, `PermissionButton.swift`,
`PermissionRow.swift`, `NoteLabel.swift`, `SearchField.swift`,
`IconChipButton.swift`, `CopyButton.swift`, `CardChip.swift`,
`PlayerFixButtons.swift`, `SymbolTile.swift`, `SupportLine.swift`,
`BadgedHeading.swift`, `WebAppsHeading.swift`, `OtherAppsHeading.swift`,
`ControlsRow.swift` and `PlayerChecks.swift` the components, `View+Unavailable.swift` how
what doesn't apply is greyed out, and `PlayerAlerts.swift` the alert
before an added app is removed, and before Add an App's Change… forgets a
check that has run (**Choose Another App**, the default button, and
**Cancel**, Escape). The menu's own rows are in `Views/MenuBar/`
(`MenuActionRow`, `MenuSwitchRow`, `MenuLine`, `MenuRowSymbol`, below).
The words said the same wherever they show are in
`Sources/AutoHushApp/Text/`, one table per topic: `ButtonText` (Cancel,
Continue, Allow…, Open <app>), `PermissionText`, `ReopenText`, `WayText`,
`AntiDotText`, `DetectionText`, `AutoPauseText`, `FadesText`, `NoneText`,
`TryAgainText`, `LaterText`, `ChooseText`, `ChangeAppText`, `LearnText`
(the Controls row), `IgnoredText`, `AccessibilityText` (what
VoiceOver says of a control that shows or hides what's under it:
Expanded, Collapsed) and the update choices'.

## Layout

| Where | Rule |
|---|---|
| Settings window | Laid out as System Settings: a sidebar of pages (`SettingsSidebar`) beside the page shown, whose name is the window's title, in the toolbar, after Back and Forward (the user, 2026-10-25, as System Settings has them: a row can open another page): two arrows joined (`NSToolbarItemGroup`, `chevron.backward` and `chevron.forward`, momentary, navigational), each dimmed with nothing to go to, and the View menu's Back (⌘[) and Forward (⌘]). The history is the pages shown since Settings opened (`SettingsNavigation`); opened afresh, it starts over. The arrow keys and the pointer move a highlight through it as in the menu (see [Keyboard](#keyboard)). The user resizes it: from as wide as its widest choice needs in the language (**715 pt** in English, 841 in German: the sidebar's 235 and the page's least width, `leastPageWidth`, 480 and 606) to **875 pt** (the page at 640, or at its least width when that's more), and **650 to 900 pt** tall (so the sidebar shows About above its foot), opening at **760 × 650** the first time; it keeps its place and size between launches. The sidebar stays **235 pt**; the page grows from **480 to 640 pt**. macOS's grouped form insets its sections **20 pt** from the page's sides (on macOS 27), and a page's `BottomBar` lines its buttons up with them. Cards are **8 pt** apart. |
| Settings pages | AutoHush opened again while it runs (Finder, Spotlight, Launchpad), with no window of its own showing, opens Settings → General (as other menu bar apps open their settings: its way in when the icon is hidden), where a warning `NoteLabel` under Keep icon next to system icons says when the notch hides the icon (`MenuBarIconVisibility`; the user, 2026-10-26). Two named groups, then About (S5d + S5a, 2026-10-25): **Everyday** ("What most people change": General, Media Player, Sound Sources, Behavior) and **Advanced** ("Fine-tuning and checks": Fine-Tuning, Diagnostics), each name in `appCaption` semibold, `appSecondary`, what it's for under it in `.tertiary`, a 14 pt gap between groups. General has the media player's card, with **Change…** (which shows Media Player), and Startup and Menu Bar; Media Player, every player's tile. Behavior has the switches only, a card each (Pausing, Resuming, Fades, Volume, Modes; Stay paused after calls indented beside a thin line, as a part of Resume playback, D3, 2026-10-26), each ending with a `FineTuningRow` to its settings in Fine-Tuning; Fine-Tuning has Timing, Fade Lengths, Volume Limits and Detection, each greyed out, saying why, while the switch it follows is off. Every card with settings has its own Restore Defaults: Behavior's for its switches, Fine-Tuning's for its sliders and ways, General's Startup and Menu Bar, About's Updates. About has Updates' card (`UpdatesCard`) under what AutoHush does. Each page but About is macOS's grouped form (`SettingsPageScroll`, `Form` with `.formStyle(.grouped)`): its `Card`s are the form's sections, their titles over them, and it scrolls by itself. |
| Pages with a list | Sound Sources and Diagnostics: the form scrolls, and the buttons stay at the window's foot in a [`BottomBar`](#components). Sound Sources' sort and search are its section's header. |
| Diagnostics | Each part (how AutoHush is doing, the apps, the player, Behavior, the detection, the permissions, AutoHush, the Mac) folds away when its heading is clicked, leaving a one-line summary; the heading's chevron points forward while folded and down while open. "Updated as it happens." heads the page, in `captionStyle`, above the first part (beside the foot's buttons it left them too little room in several languages). After a click, **Copy Report** says "Copied" for 2 s, as Copy Logs does (`CopyButton`; a click meanwhile starts the 2 s over). **Show Logs…** sits left of Copy Report and opens the logs window. A problem row AutoHush can fix ends with that fix's chip, after its value, as elsewhere: **Choose…** (no player, or one not installed: Settings → Media Player), **Learn Controls…** (a web app's button not learned), **Allow…** (a permission not allowed). |
| Other windows | The welcome, Add a Web App, learning and Add an App windows, and Add an App's Choose an App and warning windows (`HostedWindowController`), look like a Settings page: the title bar is part of the window (no band, no line), with the window's title in it in bold, as a page's name; the welcome window's title is its page's ("Choose Your Media Player", "Allow AutoHush to Work"). The content (a [`WindowPage`](#components)) starts **2 pt** under the title bar with a [`WindowHeader`](#components) (the icon and what the window is for), has **20 pt** margins (`windowMargins`), groups under `SectionHeading`s in cards **8 pt** apart, and ends with the buttons in a [`BottomBar`](#components) across the window, the main one blue at the right. Their height follows their content; their width is fixed (below: the welcome window and the guiding windows; Add an App's three are **460 pt** wide and open centered, at the normal level, the Add an App window floating above other apps only while it waits for the app to play, so its steps stay in view). Like any window, each can be minimized (⌘M, or its yellow button). |
| Welcome window | Both pages **540 pt** wide, so the window keeps its width and its `PlayerTiles` go three a row as in Settings. Past **five rows** of tiles (the apps' and the web apps' together), they scroll inside their card. |
| The Dock | AutoHush lives in the menu bar, with no Dock icon, except while one of its windows is open, minimized ones included (`DockPresence`): then it's in the Dock and the app switcher, with the Mac's standard menu bar (`MainMenu`, see [Keyboard](#keyboard)), so its window keeps its place when the user leaves its desktop and comes back. |
| Menu | AutoHush's own panel under its menu bar item (`MenuPanel`), not a system menu, so it grows and shrinks smoothly: a titled window with its title bar hidden (macOS rounds its shadow and border with its corners), on the menu's own material, Liquid Glass from macOS 26 (corner **16 pt**; **10 pt** before), which follows Reduce Transparency and Increase Contrast. It's **345 pt** wide in every language (`menuContentWidth`), as tall as its content up to the screen's bottom, its top edge fixed. As in macOS's own menu bar menus (Wi-Fi's), the card and the toolbar stay put, and only what's between them scrolls when it must, between lines; while more is below (only once the screen caps it, never while it grows to fit a part that came: `isCappedByScreen`), its last rows fade out over the bottom **32 pt**, so the menu's own material shows through, under a `chevron.compact.down` in `appSecondary`; before macOS 26, only the chevron (a mask there dims every row). It takes the keyboard without making AutoHush the active app, with nothing focused as it opens, and Escape, a click elsewhere, another desktop or another window becoming key closes it. It's compact (`MenuSpacing`): its sections ("Turn off for", "Playing Now") have **14 pt** side margins and **3 pt** above and below; a part's title has **4 pt** above it and none under; rows of a switch or a chevron **2 pt** above and below; lines (`Divider`, **14 pt** in from the sides, **2 pt** above and below) part them; its switches are macOS's small ones. Every row's picture (an app's icon, a setting's symbol, a warning's) starts **16 pt** from the menu's edge in a **22 pt** column, its text **10 pt** after it, at **48 pt** (`MenuSpacing.row`), so they line up down the menu; Ignored Apps' stacked icons take **10 pt** more. The card at the top has **12 pt** of padding (**10 pt** before macOS 26) and holds only the player, what's happening and Auto-Pause, then, under a line, what AutoHush can do with the player, as Settings → General shows it (`PlayerChecks`: its permission allowed, its fades), and, under another, Change Player (`CardPlayerRow`). The whole card is Auto-Pause's: under the pointer, the arrow keys' highlight or the switch's focus it takes the tint (`.cardFocusTint`) over its glass (a control inside it, Change Player, takes the highlight while the pointer is on it and gives it back as the pointer leaves it: `KeyHighlight`'s hovered controls), and a click anywhere on it but on its own buttons turns Auto-Pause on or off. Its rows (`MenuRowButtonStyle`) light up in the accent color, text in white, under the pointer or the keyboard's highlight, as a menu's do. The toolbar's **Updates** checks in place: it says "Checking…" and the panel stays open until the result, then closes for the alert that tells it; choosing a player acts in place, its side window closing as the card follows the new player; every other row that opens something closes it first, and so does any window or alert of AutoHush's coming forward (one a choice opened). |
| Menu bar icon | `MenuBarIcon`: a 17 pt template image in the 22 pt square item, centered. While an update waits (found, downloaded or installing: while the menu offers it), the image is the item's full **22 pt**, the tile still centered, with a disc of **8 pt** in its bottom-right corner, reaching into the room around the tile, a down arrow cut out of it and a **1.2 pt** gap cut out of the tile around it; the item keeps its width, and the image is drawn as it is (`imageScaling = .scaleNone`). |
| Guiding windows | **440 pt** wide. A window that walks the user through other apps (Add a Web App, learning a web app: Safari and the web app come in front meanwhile) floats above every app (`floatsInCorner`), in the top-right corner of the screen the pointer is on, **16 pt** from its edges, keeping its top edge as its steps come and go. Other windows open centered, at the normal level. |
| About | A4 (the user's pick, 2026-10-26: "its too crowded"): AutoHush's icon at **64 pt** beside its name (`appAboutTitle`) and version, and what it does in one sentence in `appSecondary`; then Updates (`UpdatesCard`), the links' chips centered, and the copyright in `appCaption`, **22 pt** apart, **20 pt** margins; it fits the window without scrolling. The players are on the Media Player page, the way to support it at the sidebar's foot. Updates' "When an update is found" is a pop-up menu, as System Settings has them, what each choice does its help tag and VoiceOver hint. |
| Logs window | Opened by Diagnostics' **Show Logs…**; its title, "AutoHush Logs", in the title bar as in the other windows. The user resizes it: **760 × 440 pt** at least, opening centered at **960 × 640** the first time; it keeps its place and size between launches. At the top, the `SearchField`, then the time pop-up (This Launch, Last 24 Hours) and the level pop-up (All Levels, Problems Only). Under them, the columns' titles (Level, Time, Area, Message, in the user's language) in `appCaption` semibold, `.appSecondary`, in line with the rows and still while the entries scroll; each column is as wide as its title or its widest entry, **12 pt** apart. The entries fill one card, oldest first, a `CardDivider` between them: a mark (a problem's orange `exclamationmark.triangle.fill`; otherwise a small grey dot, filled for a notice, hollow for an info line), when (the date, the 24-hour time and the Mac's offset from UTC then, `15/10/2026 14:05:09 UTC+2`, as copies and saves say it too), the area (Player, Detection, Web Apps, Updates, Settings, App) in `appCaption`, and the message, selectable. Times, areas and entries are always in English, whatever the Mac's language: the log is never translated. It opens at the newest entry and follows new ones while **Follow new entries**, the switch at the left of the `BottomBar`, is on; **Save…** and **Copy Logs** sit at the right, and Copy Logs says "Copied" for 2 s, as Copy Report does. With nothing to show, the card says why: no match for the search, no problems, or nothing logged yet. |
| Full screen | No window goes full screen (`.fullScreenNone`): Settings' and the logs window's green button zooms them instead. The guiding windows are `.fullScreenAuxiliary`, so they float over an app that's full screen. |
| Section titles | Outside the boxes, as System Settings': in Settings, the form's section headers, drawn by macOS (bold, body size), a group's note under its title (as under "Other Apps" and "Safari Web Apps"); in the other windows, a `Card`'s title or a `SectionHeading`, `appHeadline`, **4 pt** in from the box's edge; in the menu, `appMenuHeading` in grey, as macOS's menus' section headers. A label inside a box is a row's title ("Detect playing apps by"), never a heading. |

## Text sizes

Use the `Font` tokens. Never set a text's size by hand. Each is one of
macOS's text styles, so it's whatever size the running
macOS gives that style; the sizes below are macOS 14 to 27's.

| Token | macOS style (size) | For |
|---|---|---|
| `appAboutTitle` | title 2 semibold (17) | The app's name in About, beside its icon |
| `appBody` | body (13) | Plain text, row titles, and buttons (the default) |
| `appHeadline` | headline (13 bold) | Titles: a card's (the player's name in the menu), the players' groups in windows, Diagnostics' parts |
| `appMenuHeading` | callout semibold (12), `appSecondary` | The menu's section headings ("Media Player" over the side window's players, "Turn off for", "Playing Now", the players' groups), as macOS's own menus' section headers ("Output" in the Sound menu, measured 2026-10-18): `SectionLabel` takes it inside the menu (`isInMenu`) |
| `appCallout` | callout (12) | Values, notes, search fields |
| `appSubheadline` | subheadline (11) | The status line under the menu card's title |
| `appCaption` | subheadline (11) | Descriptions under rows and titles, captions |
| `appSidebarRow` | 16 | A page's name in Settings' sidebar (its own) |
| `appSidebarName` | 15 semibold | "AutoHush" at the foot of Settings' sidebar (its own) |

Inside Settings' forms, macOS sets the rows' and the section titles' fonts
itself: the pages set none of their own.

- **Numbers that change** (levels, timings) use `.monospacedDigit()`, so they don't jitter.
- **Symbols** take a text style too, so they follow macOS's sizes:
  - the menu toolbar's symbols are `title3`;
  - the menu's chevrons: a side row's `chevron.forward` `body`
    semibold, the one that says more is below `title3` semibold;
  - Diagnostics' fold chevron is `subheadline` semibold; its status
    symbol `largeTitle`;
  - the "Add…" tile's `plus` is `body` medium, the tiles' × `title3`;
  - two keep a size of their own: a `SymbolTile`'s symbol (Settings'
    sidebar, the welcome window's permissions), 16 pt semibold on a 32 pt
    square, and the logs window's dot (a notice's or an info line's), 6 pt;
  - a `WindowHeader`'s icon is 56 pt.

## Colors

Use the color tokens. A view never uses a raw color such as `.red` or
`Color.gray`. The one exception is a drawing of something that isn't
AutoHush's own interface, such as the warning window's dimmed screen with a
wallpaper's colours (`CheckWarningView`'s `DimmedScreenPicture`): it shows
that thing as it looks, in both modes. Each token is macOS's own color (the
user, 2026-10-17: "macOS's colors"), as macOS draws it in light and dark
mode; only Settings' sidebar keeps one of its own.

| Token | macOS's | For |
|---|---|---|
| `.primary` | label | Text and symbols |
| `.appSecondary` | secondary label | Descriptions, values, captions |
| `.appWarning` | orange | Things that need the user: warning symbols, a status line with a problem |
| `.appAccent` | accent color | The accent color as text on its own tint: the "Recommended" `HeadingBadge` |
| `.appSuccess` | green | Symbols for what works (Diagnostics, the welcome window's permissions); never text |
| `.chipFill` / `.chipHoverFill` | quaternary / tertiary system fill | Search fields; AutoHush's own rows under the pointer, outside the menu and Settings (the welcome window's tiles); the check panel's steps to come |
| `.focusTint` | the system accent color (`controlAccentColor`) at 14 % | The menu's and Settings' highlighted control (the arrow keys' or the pointer's) or the one with the keyboard's focus: a rounded tint behind the row, chip, chevron, button, slider or switch's row (`HighlightableControl`, `Highlightable`, `HighlightTint`), instead of macOS's focus ring; in Settings, a switch's, slider's or choice's row takes it whole, and so does a row of a title and one button; kept on a row whose side window is open; not on a dimmed one, nor on rows that light up in the accent color themselves (`MenuRowButtonStyle`) |
| `.cardFocusTint` | the system accent color at 24 % | The same over the menu card's glass, which blends a fainter tint away |
| `.warningBadgeFill` | orange 15% | Behind a `HeadingBadge`, a step's warning |
| `.nextStepFill` | accent 15% | Behind what the user must do now, in `.appAccent`: what a check's panel asks |
| `.selectedRowFill` | accent 16% | Behind a list row the user selected (Settings → Sound Sources); the accent `HeadingBadge`'s capsule |
| `.selectedTileFill` | accent 20% | Behind the chosen player's tile (`PlayerTiles`), the selected row of Choose an App's list |
| `.symbolTileFill` | accent 18% | The square behind a `SymbolTile`'s symbol (the symbol is the accent color) |
| `.sidebarSelectionFill` | black 10% (light), quaternary (dark): its own | Behind the page shown in Settings' sidebar |

- **Problems** are orange with a warning triangle (`NoteLabel`), never red.
- **Disabled** controls show at 45% opacity, over macOS's own disabled
  look. A control that's dimmed twice, inside a dimmed group, stays at 45%.
- **Settings that only matter while a switch is on (or off)** always show,
  under it in the same card, greyed out and unclickable while they don't
  apply (`.unavailable(_:)`: disabled, at 45%): the fades' lengths under
  "Fade playback", AntiDot mode's ways and the silence threshold, Updates'
  "When an update is found" (its pop-up menu; options never hide, in
  Settings and in the menu). Under them, an info `NoteLabel` names the switch that's off,
  without a period: "AntiDot mode is off", "Fade playback is off", "Level
  the volume is off", "Automatic checks are off", "Resume playback is off"
  (the user, 2026-10-22). What the user can't change at all, because
  of the chosen player, is dimmed the same way, with a note saying why.

## Components

| Component | Use it for |
|---|---|
| `Card` | A group of related rows, drawn by macOS: in Settings, a section of its grouped form (`cardsAreFormSections`), its title, badge and note over it (`Card(_:badge:note:)`, or a `heading` of its own: Diagnostics' folding parts, Sound Sources' sort and search) and its footer under it (`RestoreDefaultsButton`, a list's note); in the other windows, macOS's group box, the title over it. The menu's card is AutoHush's own clear Liquid Glass (`clearGlass`, corner 18) from macOS 26, over the panel's own glass, with no shadow. Rows inside are 10 pt apart in a group box; a form draws its own lines between rows, so `CardDivider` draws nothing there. |
| `PlayerChecks` | What AutoHush can do with the chosen player, each with `checkmark.circle.fill` in `.appSuccess` or `minus.circle` in `.appSecondary`, in `appCaption`: its permission allowed ("Automation allowed", "Accessibility allowed"), and "Fades", "No fades" or "Fades off". Under the player's name in Settings → General, and at the foot of the menu's card under a line. |
| `SectionHeading` | A title over a group outside a form, e.g. in the other windows ("Steps"): `appHeadline`, primary, in line with the box's text. In Settings a `Card`'s title is the section's header instead. |
| `SectionLabel` | A section's title outside its box: in the windows `appHeadline`, primary, as Settings'; in the menu ("Turn off for", "Playing Now", "Recently Played") and its side windows ("Media Player") `appMenuHeading`, grey, as macOS's menus'. |
| `RowTitle` | A row's title, with an optional description under it. |
| `SwitchRow` + `PillToggleStyle` | An on/off setting: the title on the left, macOS's own switch on the right (`.toggleStyle(.switch)`), at its size in Settings and the windows, small in the menu (`MenuSpacing.switchSize`), where it stays in the accent color, the panel being the key window. |
| `ChoiceChips` | One choice among two to four options, as macOS's segmented control (Fine-Tuning's Detect by). |
| `.chip` button | Actions: "Check Now", "Reset List…": macOS's push button (`.bordered`). |
| `ChipButtonStyle(filled: true)` | macOS's push button (`.bordered`), such as the menu's durations ("5 min"); selected, the prominent one (`.borderedProminent`): a window's main button (Continue). |
| `ChipButtonStyle()` | Buttons that light up only under the pointer: the menu's toolbar, the players' tiles. In the menu and Settings, the accent tint (`.focusTint`) replaces the light-up. |
| `CardChip`, `PlayerFixButtons` | The small chips under the menu card's status line (`CardChip`: `ChipButtonStyle(filled: true)`, `appCallout`), each with its symbol, one under the other: **Try Again** (`arrow.clockwise`; `TryAgainText`, as everywhere a button tries again), **Reopen** (`arrow.clockwise`) and **Unmute** (`speaker.wave.2`). Reopen and Unmute are the chosen player's fixes (`PlayerFixButtons`), which Settings → General's player card shows too, as `.chip` buttons side by side, with **Try Again** after a given-up resume (2026-10-25). |
| The card's status line with `info.circle` | When the media player couldn't be controlled ("Can’t control TIDAL right now", "Couldn’t pause — Safari is playing", "Couldn’t resume — Spotify didn’t answer", with **Try Again** under it), an `info.circle` in `.appSecondary` ends the line, kept with its last word by a no-break space; a click on the line closes the menu and opens an `InfoAlert`: what failed as its title ("Can’t Control TIDAL"), the cause in words, then, unless AutoHush is in English, the log's English for a bug report (E1, 2026-10-26: in English it said the same twice). Its one extra button, first (Return), with OK (Escape): **Open Menu Bar Settings…** when Now Playing is hidden, else **Try Again** for a given-up resume. Diagnostics shows the same as "Last error". |
| The card's Allow… | The player's missing permission is said once: on the card, in orange, "Needs Automation access" (or Accessibility, or Audio Recording), with **Allow…** under it (`CardChip`; VoiceOver hears "Allow <player> Automation Access…"), and no row asking again. Audio Recording missing while monitoring runs, which the card's line doesn't say, keeps its row under the card (`MenuActionRow`). |
| The card's Reopen and Unmute | A player that must be reopened to be controlled wherever its window is (an Electron app opened without its option) says "<player> needs reopening" in orange, with **Reopen** under it (the line names the player), whose tooltip says why. Choosing such a player asks first, in a warning alert: "Reopen <player>?", why, the checkbox "Always reopen <player> this way" (the alert's own suppression checkbox: from then on it's reopened without asking), then **Reopen <player>** (Return) and **Cancel** (Escape), which leaves the card saying so. A player muted instead of paused says "Muted — Safari is playing", with **Unmute**, which lets it be heard until the other apps stop. A player muted in place of a pause that didn't take says the same, with **Unmute** too (2026-10-25): heard again, it's the user's until the other apps stop. One that says it plays but isn't heard says "Playing silently", in grey with the icon of nothing playing, and has no button. |
| `IconChipButton` | An action with only a symbol, beside a heading or a pop-up: macOS's push button with the symbol: Settings → Sound Sources' sort arrow and magnifier. |
| `HeadingBadge` | A word in an orange capsule after a heading or a name that qualifies it: "Experimental" after "Safari Web Apps", "Checked by you" after "Other Apps", "Untested" after an untested web app, "Needed" after a permission a step can't go without, while it's missing. In `.appAccent` (`accent: true`, on `.selectedRowFill`) for a word that recommends: "Recommended" beside the way Add an App suggests. |
| `BadgedHeading` | A title (`SectionLabel`: `appHeadline`, primary; in the menu `appMenuHeading`, grey) with a `HeadingBadge` after it and a note under it, over a group of players in the menu and the welcome window: `WebAppsHeading` and `OtherAppsHeading` ("Other Apps", "Checked by you", "Controlled the ways a check found to work.") are made of it; in Settings the same title, badge and note are the group's section header. While no app was added, `OtherAppsHeading` drops its badge and says what Add… does instead ("Add any other app: a check finds how to pause and play it."), so the empty group doesn't read as checked already. |
| `PlayerTiles` | Where players are offered in a window (Settings → Media Player, the welcome window): tiles, three a row, each 44 pt tall. In Settings each group is a section of its own, its title (and badge) and note over it: "Supported Apps", "Other Apps" with an "Add…" tile, "Safari Web Apps" with an "Add…" tile (`plus`). In the welcome window, one box: the apps under "Supported Apps", a `CardDivider`, the apps added through a check under `OtherAppsHeading` with an "Add…" tile, a `CardDivider`, the web apps under `WebAppsHeading`, then an "Add…" tile. A tile is a chip (corner 10): the player's 24 pt icon, then its name in `appCallout` (on two lines where the tile is narrow) with what a row would say under it, shorter where it must fit: "Click to add" (a suggested web app), the "Untested" `HeadingBadge`, "Not installed" (dimmed), or, for an app added through a check that can only be muted, "Muted only" (its menu row: "Muted instead of paused"). In AntiDot mode, which hears no sound, such an app can't be chosen, nor one only its sound tells (a Now Playing row that never shows its state, Qobuz's): it's dimmed, saying "Not in AntiDot" ("Not in AntiDot mode" on its menu row), with why in its tooltip and VoiceOver hint; chosen already, its tile stays outlined. The other way round, while it's the player, Settings → Behavior's AntiDot mode switch is off and dimmed, with what the menu's card says of it in AntiDot mode under it ("AutoHush can only mute <player>, and muting needs Audio Recording, which AntiDot mode doesn't use." or "AutoHush needs Audio Recording to hear whether <player> is playing."; `AntiDotText`, one wording per fact), and no "Use AntiDot Mode Instead" is offered. Under the pointer, the arrow keys' highlight, or while it has the keyboard's focus, an added app's tile shows a × in its top-right corner (`xmark.circle.fill`, `title3`: 15 pt, white on `.appSecondary`), with its help tag "Remove <app>…"; a right-click offers "Remove <app>…" too, and VoiceOver gets it as an action. Delete, with the highlight or the focus on it, does the same. It asks first (`PlayerAlerts.remove`: **Remove**, the default button, which Return presses, and **Cancel**, Escape). Removing the chosen player opens the welcome window, to choose another. In the menu, holding Option turns each added app's row into "Remove <app>…" (an alternate item). The chosen (or picked) one is on `.selectedTileFill`, outlined in the accent color (2 pt), without a check, so its whole name fits. `maxVisibleRows` makes the tiles scroll inside the card past that many rows; a search keeps its height while you type. The menu keeps its rows. |
| `WebAppsHeading` | "Safari Web Apps", its "Experimental" badge and the note that every website works differently, over the web apps wherever players are offered. In the menu's player list it's the same view, as "Supported Apps" and "Other Apps" over their rows. |
| Pop-ups | SwiftUI's `Picker` with `.pickerStyle(.menu)`, always **without a border** (`.buttonStyle(.borderless)`). |
| `SearchField` | Every search. Its ✕ closes the search or, when the search can't close, clears it. |
| `NoteLabel` | A note with a symbol: `.warning` (orange triangle) or `.info` (grey "i"). |
| `.captionStyle()` | A description or note under a card or a control: small, grey, wrapping. |
| `BottomBar` | Buttons fixed at the foot of a Settings page with a list (Sound Sources, Diagnostics) and of the other windows, with a line above them, **20 pt** in from the sides: in line with a window's margins (`windowMargins`) and with the sections of Settings' grouped form. |
| `MainButton` | A window's main button, at the right of its `BottomBar` (Continue, Done, Choose, Start the Check): macOS's prominent push button, its title semibold, Return pressing it. `secondary`: the other way on beside it, grey and regular, with no key; `cancels`: Escape presses it instead (the check's Stop). A step's button (`inStep`: a checklist's, Add an App's) is one under the step's lines, on one line. |
| `FlowingButtons` | Buttons side by side when each fits on one line, else one under the other: a step's two buttons, Settings → Behavior's Audio Recording ones. |
| `CopyButton` | Copy Report and Copy Logs: a `.chip` that puts the text on the clipboard, then says "Copied" for 2 s (VoiceOver hears it); a click meanwhile starts the 2 s over. |
| `PlayerIcon` | The chosen player's icon, faded (50%) while it isn't installed, AutoHush's own while none is chosen: the menu's card (36 pt), Settings → General (56 pt). |
| `WindowHeader` | The top of the welcome, Add a Web App, learning, Add an App, Choose an App and warning windows, under the title in the title bar: the icon (AutoHush's, the player's, Safari's, the app to check's; 56 pt) and what the window is for in `appBody`, `.appSecondary`, the icon centered on the text. |
| `WindowPage` | Those windows' page: the `WindowHeader`, what the window shows under it **8 pt** apart (the welcome window's players **16 pt**), all in the window's margins (`windowMargins`), then its `BottomBar`, at the window's width, in `appBody`. |
| `SymbolTile` | A symbol in the accent color on a square tinted with it (`.symbolTileFill`, 32 pt, corner 8): Settings' sidebar pages, the welcome window's permissions. |
| Growing in the menu | As a part comes or goes (Playing Now, a warning, the card's lines), the panel's height follows (`MenuPanel.setContentHeight`, **0.25 s**, easing out), its top edge fixed; at once with Reduce Motion. The menu folds nothing since A1 (2026-10-25: the settings are Settings' only): the players and the ignored apps open in a side window instead, closed each time the menu opens. |
| `CardPlayerRow` | The menu card's last row (H4, 2026-10-25, in place of the Media Player part), under a `CardDivider`: `music.note.list` in `appSecondary`, "Change Player" ("Choose Player" while none is chosen) in `appCallout`, and a `callout` semibold `chevron.forward` (mirrored right to left) in the accent color (`ChevronRowLabel`, as `FineTuningRow`'s). As a `MenuSideRow`, the pointer resting on it (**0.15 s**) or a click opens the players in a side window beside the menu, level with it, and it stays tinted while that's open (corner 6); its own button, so a click on it doesn't turn Auto-Pause on or off. |
| `MenuIgnoredAppsView` | Ignored Apps' part, the same way, always there, so the first app to ignore can be added from it: while none is, its row says "None" by a `speaker.slash` in `appSecondary`, centered in the picture column as the other rows' symbols, over "Apps you ignore don’t pause your player.", as tall as the other rows. Otherwise the title over a `MenuSideRow` with up to three of the apps' 18 pt icons overlapping, their names (one or two; from three on, the first two "and 2 more") and "It doesn’t pause your player." for one app, "They don’t pause your player." for more; the pointer resting on it or a click opens them in a side window, each a `SourceSwitchRow` (as Playing Now's, but saying only "Ignored" under an ignored app: the side window's title says the rest), listed as they were when it opened, so one switched back on keeps its row; then **Ignore an App…** while none is ignored, **Ignore Another App…** once one is (a `MenuActionRow`: `plus.circle` in the rows' picture column, its text in line with the apps' names; the side window's highlight and tint), which closes the menu for the panel that picks apps to ignore, several at once (its title says so; `IgnoreAppsPicker`), as Settings → Sound Sources' button of the same name does; one alert names the apps it can't ignore. |
| Side window (`MenuSidePanelView`) | A submenu beside the menu: a `MenuPanel` **300 pt** wide, **6 pt** left of the menu (on its right when there's no room), its first row level with the row that opened it, as tall as its content up to the screen (it scrolls past that, with the menu's fade and chevron while more is below), its part's title at its top, **4 pt** over its first row as Playing Now's is. One at a time; it stays open while the pointer goes to it or stays on its row (its row's part; Change Player's own row, not the rest of the card), also across other parts while it heads toward it (as macOS's submenus: nearer its edge, inside the triangle from where it was to that edge's corners), and closes once the pointer has been over another part of the menu for **0.3 s** otherwise, or on Escape (then Escape again for the menu), choosing a player or a click elsewhere. The menu keeps the keyboard, so its switches stay drawn active: ↑ ↓ and Return (Space too, for the ignored apps) go to its rows, and ← closes it; typing goes to the players' search; a click in it, a dead key (é's ´) or an input method gives the side window the keyboard, its field focused, so they compose there (the menu's switches then draw inactive); otherwise only VoiceOver moves into it. |
| `MenuPlayerListView` | The players, in their side window: a search (`SearchField`, from eight players on), then "Supported Apps", "Other Apps" with **Add an App…**, and `WebAppsHeading` with **Add a Web App…**, each under its section title (`SectionLabel`, as the menu's other sections), parted by lines. A row (`MenuActionRow`, in a picture column of 18 pt with 8 pt to the name, Add an App… and Add a Web App… too): the icon (18 pt), the name, an "Untested" `HeadingBadge` after it for an untested web app, its subtitle ("Not installed", "Click to add", why it's greyed out in AntiDot mode), and a checkmark on the chosen one. The rows don't light up as menu items: as the menu's controls, they take the tint (`.focusTint`) under the pointer or the arrow keys' highlight, which goes through every row, Add an App… and Add a Web App… too; Return or Space presses it (Space only until something is typed in the search: then it types a space); with nothing highlighted, Return chooses the first player the search left while something is typed, and does nothing with the search empty; with ⌥ Option held, an added app's row reads "Remove X…". |
| The menu's rows (`MenuActionRow`, `MenuSwitchRow`, `MenuLine`, `MenuRowSymbol`) | Built once each, so their geometry stays the same down the menu (`MenuSpacing.row`): a row that acts (`MenuActionRow`: a warning, Use AntiDot Mode Instead, the update found, lighting up as a menu item; in a side window, the players and the rows that add, under the tint); a row with a switch (`MenuSwitchRow`: Playing Now's, Recently Played's and the ignored apps' apps), its title and words hidden from VoiceOver, the switch named by it, why it's dimmed on a line under it, and a click anywhere on it turning it on or off, as on its switch (2026-10-21); the line between parts (`MenuLine`, **14 pt** in from the sides); a grey symbol centered in the picture column (`MenuRowSymbol`: `speaker.slash` while no app is ignored). |
| `SettingsSwitchRow`, `TimingSliderRow` | The switches (Behavior) and timings (Fine-Tuning) Settings and Diagnostics share (`SettingsSwitch`, `SettingsTiming`): one place for their words, ranges and when one is dimmed. |
| `FineTuningRow` | A Behavior card's last row (L4, 2026-10-25): `slider.horizontal.3` in `appSecondary`, the settings' name ("Pause playback after", "Fade lengths", "Volume limits", "Detection"), what they're set to in `appSecondary` (none while the switch they follow is off), and a `callout` semibold `chevron.forward` in the accent color (`ChevronRowLabel`, as `CardPlayerRow`'s). A click, or Return or Space on its highlight, shows Fine-Tuning scrolled to that card, its heading at the top (`ScrollDriver` and `ScrollAnchor`: a grouped form's rows can't be reached by `ScrollViewReader`); the request is forgotten once it's done, or another page shows. |
| `SettingsSidebar` | Settings' pages as rows, in their named groups (see Settings pages): the page's `SymbolTile`, its name in `appSidebarRow`, the page shown on a grey `.sidebarSelectionFill`. At its foot, under a line: "AutoHush" (`appSidebarName`), the version, and the `SupportLine`. |
| `RestoreDefaultsButton` | In the footer of every card with settings (`SettingsCard`; `SettingsModel.isDefault` and `restoreDefaults`), on the right, shown only once one of them differs from its default (RD1, 2026-10-26: a dimmed one under every card was clutter): sets that card's settings back; what's greyed out stays as it is (Modes' turns AntiDot mode off; Detection's sets AntiDot mode's way back in AntiDot mode, the silence threshold out of it; Startup and Menu Bar's turns launch at login off and leaves the icon where it is; Updates' checks daily and installs automatically). |
| `SupportLine` | "Would you like to support me?" with its link, at the foot of Settings' sidebar (the question in `appCaption`, the cup on the link). |
| `LearningSteps` | What the user does so AutoHush can learn a player (play it; AutoHush then pauses it), each step ticked in `.appSuccess` once seen. The step to do now is semibold, with an arrow in the accent color (`StepSymbol`). A step AutoHush does itself shows a spinner meanwhile; one it couldn't do gets an orange `xmark.circle.fill`, its reason as a `NoteLabel`, and two buttons side by side, the way forward in blue ("Try Again") and the other way grey ("Pause It Yourself"), which adds the user's own step. A step's buttons stay on one line each: when two don't fit side by side (longer languages), they go one under the other (`FlowingButtons`). The permission learning needs first is a step of the checklist too (`ChecklistStepRow`, `LearningPermissionStep`), the step to do now, with its `PermissionButton` under its lines. They show only in windows: the learning window, and Add a Web App once it has made the web app. |
| `NumberedStepRow` | A step of a window whose steps go in order and are few (Add an App): its number in a circle while it's to come (`N.circle`, `.appSecondary`), filled with the accent color while it's the one to do (`N.circle.fill`, title semibold), a check in `.appSuccess` once done (title in `.appSecondary`), a spinner while AutoHush does it, an orange `xmark.circle.fill` once it failed (`StepSymbol` with its number, as a checklist's). All marks are 18 pt wide, so the titles line up. Under the title: its lines (`.captionStyle()`), what it needs (a list, permission rows, the ways found), a warning (`NoteLabel`), then its button, blue for the way forward (Return presses it), grey for another way on ("Skip"). The keyboard's focus moves to the main control of the step to do now. A failed check's **Show Log…** is dimmed while there's no log. The whole window shows every step from the start, so what's coming is clear before it begins. |
| Choice cards | Choosing one of a few options that each need a line of why (Add an App's last step, the ways that worked): each a card (corner 10) with its mark, name and grey note, outlined in `.separator` (1 pt); the chosen one on `.selectedTileFill`, outlined in the accent color (2 pt), as a chosen tile. The suggested one comes first, with an accent "Recommended" `HeadingBadge`, and is chosen until another is; when it works only in some window states, its mark is orange and so is its note, which says where it doesn't (W4, 2026-10-26). Options that can't be chosen are listed under them, not as cards, dimmed (60%), each with why (for one not checked, what was missing); in AntiDot mode, that includes a way only the app's sound tells about. Notes are fragments, without periods. The step's main button acts on the chosen one; while Now Playing is hidden in the menu bar, a grey **Check Again** sits beside it, and an **Open Menu Bar Settings…** chip above them (Control Center's on macOS 14 and 15) opens the pane where it's shown, as the alert about a failed pause through it does (its first button, Return; **OK**, Escape). |
| A warning window before a takeover | Before AutoHush takes over the Mac (Add an App's check): its own window, titled for what it does ("Check Deezer"), the app's 56 pt icon, what happens and for how long, pictures of it (`SymbolTile`s for the window's states, in a grid of 4 columns; a drawn dimmed screen), then **Cancel** and the action in blue ("Start the Check"). Nothing starts until that button. |
| A check's panel | While AutoHush takes over the Mac: a borderless panel at the bottom right of the main display, on every desktop, never taking the keyboard: the app's icon, "Checking <app>…" (two lines at most) with what it does, **Stop**; what it asks of the user (play it, pause it with its own Pause, allow Accessibility) in the accent color on `.nextStepFill`, with the time left, so the step to do now stands apart from the orange warnings (Player Check's panel too); the window states as segments, the one under test and what's pressed; and, while the mouse and keyboard are blocked, a line saying so (`hand.raised`, orange). The screen dims (black at 50%) except the panel while input is blocked. |
| `CountdownBanner` | How long is left to do a step, as a whole sentence ("You have 0:45 to pause it and click It’s Paused."): semibold `.appCallout` in `.appWarning` with a timer, on a `.warningBadgeFill` rounded line, above the step's button. |
| `PermissionButton` | The button that allows a missing permission, labeled for where it stands: "Open <player>" (Automation is asked only while the player runs), "Allow…" or the permission's "Allow … Access…" (macOS's prompt when it hasn't asked, else System Settings), "Reopen AutoHush" (Audio Recording switched on in System Settings). Nothing once it's allowed. `prominent` makes it the blue chip when it's the window's next step. |
| `PermissionRow` | A permission as a row, in the welcome window and Add an App's step 2: a `SymbolTile`, its name (with a badge after it in Add an App: **Needed**, *Optional*) and what it's for or how it stands under it in `captionStyle`, then the way to allow it, or, once allowed, "Allowed" in `.appSecondary` after a check in `.appSuccess` (`AllowedLabel`). |
| `WelcomePermissionsView` | The welcome window's second page: what the chosen player needs under "Permissions", a `PermissionRow` each (its `PermissionButton`; "Not needed" for Audio Recording in AntiDot mode), "Use AntiDot Mode Instead" under Audio Recording, Back and Done in the `BottomBar`. |

**Permission blocks.** Wherever something needs a permission that's
missing, say what's missing in a `NoteLabel` (`.warning`) with its
`PermissionButton` right under it, and keep the main action disabled
(Continue, Done) or its steps locked (`lock.circle`, grey) until it's
allowed. In a checklist, the step that asks for the permission is the step
to do now meanwhile (semibold, with its arrow). Follow the permission while
the window shows (about once a second), so it unlocks by itself; never ask
the user to click again. Audio Recording always offers "Use AntiDot Mode
Instead" beside it.

**Permissions a step can partly go without** (Add an App's): each row says
whether it's **Needed** (`HeadingBadge`, only while it's missing) or
*Optional* (grey caption) after its name, and what it's used for under it.
While one that's needed is missing, a `NoteLabel` says why it's needed and
there's no Continue. While only optional ones are missing, a `NoteLabel`
says what happens without them, with **Continue** (blue) under it; with
everything allowed, the step goes on by itself.

**App icons** come from `AppIcon` (or `PlayerOption.icon`), at the size for
where they appear:

| Size | Where |
|---|---|
| 18 pt | Menu rows: the players, the icons in Ignored Apps' row, the warnings |
| 20 pt | Compact lists: Playing Now and Recently Played, the ignored apps' side window, Choose an App's list |
| 24 pt | Settings lists: Sound Sources, Diagnostics; the players' tiles (`PlayerTiles`) |
| 34 pt | The app being checked, in a check's panel |
| 36 pt | The menu card's player |
| 56 pt | The chosen player in Settings → General; a `WindowHeader`'s icon |
| 64 pt | AutoHush's own icon in About |

A Safari web app's icon carries Safari's at its lower right, a little over
half its size (`AppIcon.webAppImage`, through `PlayerOption.icon`), wherever
it shows: so a web app is never taken for an app of the same name and icon
(Spotify's app and its website, both "Spotify"). Suggested web apps keep
their download symbol. A web app made by Chrome, Brave or another Chromium
browser carries that browser's icon the same way (`AppIcon.appImage`), in
Add an App's list and once it's added under Other Apps, with "<browser> web
app" under its name in the list: two web apps of one site, made by two
browsers, are told apart.

**Marking the chosen item:**
- In a list that acts on a click, as menus and pop-ups do, the chosen item
  has a checkmark on the left; in the menu's players side window, on the
  right, after its name, where the rows' pictures (the apps' icons) take
  the left (`MenuPlayerListView`).
- Among tiles (Settings → Media Player, the welcome window), the chosen or picked
  one is tinted and outlined with the accent color (no check, so the whole
  name fits): `.chosenOutline(_:)`, as Add an App's choice cards.

## Lists and searches

- **Order:** a list has an obvious order and keeps it. Settings → Sound Sources lets
  you choose the order, and remembers it. Where players are offered:
  - **Apps** are listed by how many people use them, with those that
    aren't installed after them, dimmed, and marked "Not installed".
  - **Safari web apps** come last, under the `WebAppsHeading` (with its
    "Experimental" badge and note): the tested sites' web apps by name
    (each named as its site), the tested sites not added yet, then any
    other web app by name, with an "Untested" `HeadingBadge` (under its
    name on a tile; in the menu, after it, the name cut short with "…" so
    the badge always shows).
  - **The headings** ("Supported Apps", "Other Apps", "Safari Web Apps")
    line up with the rows' icons in menus, and with the cards' text among
    tiles. A search keeps the web apps' heading only while a web app
    matches.
  - **Suggested web apps** (the tested sites not added yet) are marked
    "Click to add", in menus as on a tile, like a missing app but not
    dimmed, with the `arrow.down.circle` symbol for an icon: a click opens
    "Add a Web App" filled in with the address.
  - **A service with its own site in some countries** (Amazon Music,
    `CountrySites`) is suggested on the site for the Mac's region. While
    the address is one of its sites, Add a Web App's address card adds a
    row under the field, "Your account’s country", with a borderless
    pop-up of the countries with their own site, by name, then a divider
    and "Other Countries"; choosing one puts its site in the field. A
    caption under the card says why (a sign-in works only on the
    account's country's site).
  - **Apps added through a check** come after the apps, under
    `OtherAppsHeading`, then **Add an App…** (with `plus.circle`): in the
    menu as a row, among `PlayerTiles` as an "Add…" tile. The heading shows
    even with none added (Add an App… is under it), and during a search
    only while one matches.
  - **Add a Web App…** (with `plus.circle`) comes last: the menu's last
    row, and the last tile (as "Add…") among `PlayerTiles`.
  - **A long list to choose from** (Add an App's apps) opens in a window of
    its own, from a step's "Choose an App…": a search, the list in a card
    (those in Now Playing first, under small grey headings), the selection
    on `.selectedTileFill`; **Choose** (blue, Return, or a double click),
    **Cancel**, and **Other App…** at the left of the `BottomBar` for
    anything not listed (the Finder's open panel, in Applications).
  - The Add a Web App and learning windows show the heading's warning as a
    `NoteLabel` under their header (`WindowHeader`).
- **A web app's controls** have one place: a `ControlsRow` ("Controls",
  whether they're learned, and a `.chip`) at the foot of the menu's card and
  on Settings → General's player card, nowhere else. The button says
  **Learn Controls…** until they're learned and **Learn Again…** after,
  with an ellipsis since it opens a window: a new learning window that
  starts from the first step, closing one still open. What was learned
  keeps working, and the row keeps saying it's learned, until
  **It's Playing** is taken there; closing the window before that keeps
  it. Meanwhile the window leaves out its "presses nothing on the page"
  line, untrue then. Once learned, the row says only "Learned." and how to
  learn them again, so it fits the menu. In the menu its text is
  `appCallout`, as the menu's chips'.
- **Learning steps show only in a window** (the learning window, or Add a
  Web App once it made the web app), never in the menu or Settings.
- **A process the user waits for** shows its steps in a card, as the
  "Add a Web App" window does: done steps ticked in `.appSuccess` and dimmed,
  the current one semibold with an arrow in the accent color and a caption
  under it, the next ones as empty circles (`StepSymbol`, the same in every
  window). A tip on how to do a step (`.captionStyle()`)
  shows under that step only while it's the one to do. The window closes by
  itself once done. Its button says **Cancel** while closing it stops the
  process, and **Later** once what's left goes on anyway (as in the
  learning window).
  - **A step the user says is done** (It's Playing, It's Paused, Add to Dock)
    has its button under its caption while it's the one to do: a blue chip
    (`MainButton`'s `inStep`), outside the step's VoiceOver element, and Return
    presses it. Its caption ends by naming the button ("Then click It’s
    Paused."). The same steps and buttons show in both windows that show
    them (learning, Add a Web App).
  - **A time limit** shows as a `CountdownBanner`, a whole sentence that
    counts down ("You have 0:45 to pause it and click It’s Paused.").
  - **A click that couldn't be taken** says why in a `NoteLabel` under that
    step, until the next click.
  - **A step only some cases need** ("Answer the site in Safari") shows only
    once it's needed, and stays ticked afterwards.
- **Searches** appear where a list can grow long: always in Settings → Sound Sources,
  and in the menu and the welcome window once there are eight media players
  or more (not counting suggested web apps). Settings → Media Player shows every
  player's tile on a page that scrolls, without one.
  - A search matches anywhere in a name, ignoring case and accents
    (`localizedStandardContains`).
  - Results keep the list's order.
  - The window keeps its height while you type.
  - With no match, the list says so in its own words: "No apps match “…”."
  - A search starts empty again when its window or menu opens again.
  - **Edit → Find…** (⌘F) opens Settings → Sound Sources' search while it lists
    apps, and puts the cursor in the welcome window's player search when it
    has one, in the logs window's search and in Add an App's list of apps.
    Elsewhere it's dimmed: it only ever acts on a search.
- **Empty lists** say why they're empty and what fills them: "Apps appear
  here once they have played audio."
- **Removing from a list** (Settings → Sound Sources): a click on a row, anywhere but
  its switch, selects only it, behind a `.selectedRowFill` rounded
  rectangle; a second click on the only one selected deselects it. As in
  macOS's lists, ⌘-click adds a row or takes it
  out, and ⇧-click selects the rows from the last one clicked. From the
  keyboard, Tab reaches the rows (with keyboard navigation on) and Space
  adds the focused one or takes it out, as Return or Space on the arrow
  keys' highlight does. **Remove** sits in the bottom bar after the button
  that adds, disabled while nothing shown is selected, and removes every
  selected row the search shows. Removing something whose loss changes
  what AutoHush does (an app turned off would pause the player again) asks
  first, once for all of them, naming the app when only one of them is
  turned off, as **Reset List…** does; what changes nothing goes at once.
  The row's right-click menu offers the same (**Remove from List**), for
  the whole selection when the row is one of the selected, else for that
  row alone, and VoiceOver gets it as an action.

## Writing

**Short.** Every text is as short as it can be while it still makes sense:
people don't read long texts. Say what matters to the user, leave out the
rest; a title and one line usually do for an alert.

### Capitalization

| Title case | Sentence case |
|---|---|
| Window titles, page names | Row titles and switch labels: "Launch at login", "Pause playback after" |
| Buttons and menu items: "Check Now", "Ignore Another App…" | Lead-ins that read into their control: "Turn off for", "Sort by", "When an update is found" |
| Pop-up items: "Last Played" | Choice chips: "Notify me", "Install it automatically" |
| Section headings: "Apps", "Playing Now", "Apps with Sound" | Descriptions, notes and status lines |
| Alert titles: "Couldn’t Install the Update" | Tooltips and VoiceOver labels: "Search by name", "Reverse order"; notification titles: "AutoHush 1.0.0 is available" |
| Shortcuts action names and their choices, App Shortcut titles: "Turn Off Auto-Pause For", "15 Minutes", "Auto-Pause Off" | An action's summary and an App Shortcut's phrase: "Turn off Auto-Pause for 15 Minutes", "Turn on Auto-Pause in AutoHush" |

- **Title case** follows Apple's rules: capitalize every word except
  articles, and conjunctions and prepositions of four letters or fewer.
- **Notifications and alerts differ:** a notification's title is in
  sentence case, as macOS's own are ("Couldn’t update AutoHush to 1.0.0"),
  while an alert's title is in title case ("Couldn’t Install the Update").
- **A confirmation's title phrased as a question** keeps sentence case:
  "Reset the list of apps?", "Remove … from the list?".
- **Feature names** keep their capitals, even mid-sentence: **Auto-Pause**,
  **AntiDot mode**.

### Words and punctuation

- **Speak to the user** ("your player") and name AutoHush by its name
  ("AutoHush pauses it…"), not "the app".
- **Media, not just music.** AutoHush pauses music, podcasts and videos, so
  each word has its job: **media player** names the app the user chooses
  ("Choose Your Media Player", "Media Player"); **playback** is for short
  labels about pausing, resuming and fading ("Pause playback after", "Fade
  playback"); **your player** is for sentences about what
  AutoHush does to that app ("Pauses your player", or "Mutes your player"
  where the player is muted instead of paused; "Ignored — your player keeps
  playing"); **what's playing** describes the content, naming the media
  where it says what AutoHush does ("Pauses what's playing (music, podcasts
  or videos)…"). The feature is just **Auto-Pause**. "Music" stays
  only in names (Apple Music, YouTube Music).
- **Permissions:** you "allow" them, never "grant" them. Use the names macOS
  gives them: Automation, Accessibility, Audio Recording.
- **Contractions:** use them everywhere, status lines and errors included:
  couldn’t, can’t, isn’t, it’s, don’t. Never "could not" or "is not".
- **Apostrophes** are curly (’), as macOS writes them: "can’t", "Spotify’s",
  in English and in every language that has them ("l’app", "Mac’te"),
  and in the log's lines too, which the logs window shows. A straight '
  never shows; a test checks every catalog.
- **Ellipsis** (`…`, a single character) ends a button or menu item that
  opens a window or asks for something more before it acts (a panel, a
  dialog): "Learn Controls…", "Reset List…". It also ends a state in
  progress ("Checking…"). A button that acts at once has none.
- **Em dash with spaces** joins a state and its reason: "Paused — Safari is
  playing", "Ignored — your player keeps playing".
- **Quotation marks** are curly in English (“ ”). Each language uses its own
  («  », „ “, 「 」).
- **Periods** end full sentences: descriptions and notes. Fragments have
  none: subtitles ("Pauses your player"), the menu's short explanations
  and reasons ("Fades out and back in", "Off in AntiDot mode"), status
  lines, labels and buttons.
- **Numbers** are digits, with units in the user's format: "0.5 s",
  "-60 dB" (a hyphen for minus, as numbers are printed), "5 min".
- **Shortcuts** read like Apple's own actions: a name that says what the
  action does ("Set Auto-Pause", "Get Auto-Pause"), a summary that reads as
  a sentence with the choices in it ("Turn Auto-Pause On"), and a full
  sentence for the description. An App Shortcut's phrase names the app
  ("… in AutoHush"), as Siri requires: every translation keeps
  `${applicationName}`, and a test checks.

## Translations

AutoHush is translated into 37 languages besides English. DEVELOPMENT.md's
[Translations](DEVELOPMENT.md#translations) section explains how; for style:

- **Every change translates every language.** A new or changed English
  string is translated into all 37 before the change is done.
- **The comment says where.** Every string has a comment that says where it
  appears and what each placeholder holds.
- **A changed English string is a new key.** Carry its translations over,
  update them, and delete the old key.
- **A bottom bar's buttons stay on one line** (`.fixedSize()`). When a
  translation makes them wider than the window at its narrowest, that
  translation is shortened, keeping its meaning (in Settings → Sound Sources:
  Russian "Сбросить…", Greek "Επαναφορά…", German "App ignorieren …").
  `BottomBarFitTests` measures every bar in every language, with Liquid
  Glass's wider chip padding, and fails when one doesn't fit; a new bottom
  bar gets a row there.
- **Short slots stay short.** Measured at the windows' sizes: a Settings
  page's name in the sidebar has about 134 pt at 16 pt (about 16
  characters: German "Ein-/Ausblenden", not "Ein- und Ausblenden"), and the
  line under a player's name in a chip (`PlayerTiles`) about 90 pt at
  11 pt (about 12 characters: "Click to add" is "Añadir", "Hinzufügen"),
  which `BottomBarFitTests` checks in every language.
  The menu's Controls button may drop "controls", which its row's title
  already says (French "Apprendre").
- **Keep the menu card short.** The label under its switch shows whole and
  takes room from the status line beside it. So the feature's name stays
  short ("Autopauza", "Autopause"), and a status line fits in three lines
  ("Allow Automation access to control Spotify" rather than a full sentence).
- **Use macOS's own words** for its concepts in each language (Ajustes,
  Einstellungen, Réglages…), and the capitalization rules above as each
  language applies them.
  - Brazilian Portuguese, Turkish and Indonesian use title case on buttons
    and menu items; the other languages use sentence case everywhere.
  - German capitalizes its nouns everywhere.
  - Buttons follow each language's Apple style: imperatives in most
    languages ("Sta toe", "Tillåt"), infinitives in Czech, Slovak and
    Ukrainian ("Povolit"), nouns in Hungarian and Greek ("Kilépés",
    "Αναζήτηση"), the formal imperative in Romanian ("Permiteți").
- **Plurals:** a string with a count has plural forms in the catalog where
  the language needs them: Russian, Ukrainian, Polish, Czech, Slovak,
  Croatian and Romanian (one, few, many or other), Slovenian (also two) and
  Arabic (two, few, many, other).
- **Typography:**
  - French puts a no-break space before `: ; ? !` and inside « »; Canadian
    French doesn't before `; ? !`.
  - German puts a no-break space before "…".
  - Chinese puts spaces between Chinese and Latin text and uses full-width
    punctuation, with "⋯" in Traditional Chinese.
  - Catalan puts the article before AutoHush ("l’AutoHush"), but not before
    a placeholder.
  - Russian uses « » quotes.
  - Arabic uses its own comma, question mark and semicolon (، ؟ ؛) and « ».
  - Slovenian puts a space before "…".
  - Languages that inflect names never attach an ending to a placeholder:
    a noun in the right case goes before it ("aplikace %@", "appia %@"), or
    an ending that never changes ("%@-ig" in Hungarian). Hungarian writes
    "a(z)" before a name.

## Right to left

In Arabic, AutoHush reads right to left, and every screen mirrors.

- **Leading and trailing,** never left and right, in layouts and alignments.
- **Directional symbols** use their "forward" and "backward" forms
  (`chevron.forward`), which mirror. A rotated symbol keeps the same angle:
  SwiftUI mirrors the rotation too.
- **Check it** by starting the app with `-AppleLanguages "(ar)"
  -AppleTextDirection YES`, which runs it in Arabic, right to left, as
  Xcode's right-to-left option does.

## Accessibility

- **Labels:**
  - Every control with only a symbol has a VoiceOver label and a tooltip
    (`IconChipButton` sets both).
  - A control whose state the symbol shows also says it as its value, e.g.
    the sort arrow's "Newest first".
  - The menu bar icon says "AutoHush: " and what's happening; while
    something needs the user, while the player is closed, or while
    Auto-Pause is off (the icon dimmed),
    the menu's status line ("AutoHush: Spotify isn’t running", "AutoHush:
    Auto-Pause is off until 15:30"), never a word of AutoHush's own like
    "degraded". While an update waits, it adds ", update available".
  - A slider says what it sets (Fine-Tuning's: the row's
    title) and its value as the row shows it ("0.5 s"); the row's own text
    is hidden from VoiceOver, so it's read once.
  - What an image alone tells is said in words: a web app whose name is
    also an app's reads "Spotify, Safari web app" where players are offered
    (`PlayerOption.spokenName`), as its icon's Safari badge shows; an app
    added through a check that's a Chromium browser's web app always reads
    whose it is ("SoundCloud, Google Chrome web app"), as its browser badge
    shows; and an untested web app's menu row reads "Untested" after its
    name.
- **Switches are one stop:** a row's title and description are hidden
  from VoiceOver, the switch takes the title as its name and the
  description (or why it's dimmed) as its hint (`SwitchRow`; in the menu
  `MenuSwitchRow`: Playing Now's apps).
- **Decorative images** (app icons beside their names, symbols beside text,
  the menu toolbar's symbols, the chevrons, the chevron that says more is
  below) are hidden from VoiceOver.
- **Headings:** `SectionHeading`s, the menu's section and part titles
  ("Turn off for", "Playing Now", "Media Player"),
  and Diagnostics' headings carry the heading trait, so VoiceOver can move
  from one to the next. A heading or button that folds a part away
  (Diagnostics' headings) or opens a side window (the card's Change
  Player row, the menu's Ignored Apps row) says
  "Expanded" or "Collapsed" as its value, and the side window is named by
  its part ("Media Player", "Ignored Apps").
- **What changes away from VoiceOver's cursor is announced:** "Copied"
  after Copy Report and Copy Logs, why Add a Web App couldn't take the
  address, a step's warning when it shows or changes, the card's line after
  Try Again, why a window waits for a permission, when it opens and when it
  locks, and what a check's panel asks of the user, and that it stops.
- **Switches** read as switches, with their row's title (`PillToggleStyle`
  does this).
- **Chosen items** carry the "selected" trait.
- **Checklist steps** (adding a web app, learning a player) are one
  VoiceOver element each (`checklistStepAccessibility`): the step's words,
  notes, warning and countdown as its label, and where it stands as its
  value, "Completed", "In progress", "To do" or "Failed", never the
  "selected" trait. The element sets its own label instead of combining its
  texts (the step that asks for a permission too): combined, a value of its
  own would replace their words. A window's checklist announces the step to
  do now each time it changes (`announcesCurrentStep`), at high priority
  through AppKit, so the focus change a step brings doesn't cut it off.
- **Numbered steps** (`NumberedStepRow`, Add an App): each step's title is a
  heading read with its number ("Step 2 of 6, …"), with where it stands as
  its value ("Completed", "In progress", "To do", "Failed"), so VoiceOver
  moves from step to step; its mark is hidden, and its lines and buttons
  are read on their own. The window announces the step to do now, and a
  step's warning or failure, as they come.
- **Contrast:** text keeps at least 4.5:1, except in macOS's own colors,
  kept as macOS draws them (Principles).

## Keyboard

AutoHush has **no keyboard shortcuts of its own, and all of Apple's
standard ones**:
- **The menu bar** (`MainMenu`), while a window is open: the AutoHush menu
  (About, Settings… ⌘,, Services, Hide ⌘H, Hide Others ⌥⌘H, Show All,
  Quit ⌘Q), Edit (Undo ⌘Z, Redo ⇧⌘Z, Cut ⌘X, Copy ⌘C, Paste ⌘V, Delete,
  Select All ⌘A, Find… ⌘F), View (Back ⌘[, Forward ⌘]: Settings' pages,
  dimmed elsewhere or with nothing to go to) and Window (Close ⌘W,
  Minimize ⌘M, Zoom, Bring All to Front), in macOS's own words in every
  language; macOS shows ⌘[ and ⌘] as the keyboard layout has them (⌘Ñ and
  ⌘´ on a Spanish one). No tab or full-screen items: window tabbing is off
  and `NSFullScreenMenuItemEverywhere` false, or AppKit adds Show Tab Bar,
  Show All Tabs and Enter Full Screen to View and its tab items to Window
  (the user, 2026-10-25). The Edit menu is
  what makes text fields take ⌘V and the rest. **Find…** opens Settings →
  Sound Sources' search while it lists apps, and puts the cursor in the welcome
  window's player search when it has one, in the logs window's search and
  in Add an App's list of apps; it's dimmed wherever there's no search.
  **Minimize** works in every window: Settings, the welcome window, the
  guiding windows (Add a Web App, learning) and Add an App's windows.
- **Return** presses a window's main, blue button
  (`.keyboardShortcut(.defaultAction)`: Continue, Done) and an alert's
  first one; in a checklist, it presses the blue button of the step to do
  now (It’s Playing, It’s Paused, Add to Dock, Try Again); in Add a Web
  App's address field it's Continue. A step's blue permission button (the
  learning and Add a Web App windows) doesn't take Return: it opens System
  Settings. A search field keeps Return from the window's button (SwiftUI
  gives it to the focused field): with nothing typed it's the main button
  (Continue); with a search, it picks the one item the search narrowed
  down to (the welcome window's players), if just one; items that share a
  name count as one (the Spotify app and the suggested Spotify web app: the
  app).
- **The arrow keys in Settings** work as in the menu, whatever the keyboard
  navigation setting: ↑ and ↓ move the highlight
  through the page's controls row by row, in order through a list that
  scrolls and the buttons under it (Sound Sources with many apps), ← and →
  along a row of tiles; Return or Space presses the one it's on, ← and →
  change a slider or a choice; on any other control, ← goes to the
  sidebar, on the page shown, where ↑ and ↓ show each page at once, and →
  or Return goes back into the page (`SettingsKeys`, `HighlightKey`). The
  pointer moves the same highlight, one at a time on either side; it never
  jumps to the sidebar's first page by itself. A key with nothing to act
  on doesn't beep. A field being typed in keeps its keys.
- **Tab and Space** move and press as macOS's keyboard navigation does
  (when it's on), the focused control tinted as the highlight; in the
  menu and Settings, a control Tab reached takes Return, Space, ← and →
  itself.
  Settings → Sound Sources' rows take the focus too, and Space adds
  the focused one to the selection or takes it out, so **Remove** can
  take several. **Delete** removes what's selected there, as Remove does,
  and an added app's tile the highlight or focus is on (asking first). In Add an App's list of apps, ↑ and ↓ in its search move
  the selection, and Return chooses it.
- **Escape** presses Cancel or Later (`.cancelAction`, or
  `keyEquivalent = "\u{1b}"` on an alert's Later or Cancel); while a check
  runs, it's the check's Stop.
- **Never a shortcut Apple doesn't define**, and none on the menu's rows.
  ⌥-clicking Settings in the menu opens Diagnostics.

The menu's panel takes the keyboard as a menu does, without making
AutoHush the active app, whatever the keyboard navigation setting (the
user, 2026-10-18): ↑ and ↓ move its highlight row by row, from Auto-Pause
to Quit, wrapping at the ends (into a row of several, the one nearest
above or under, else its first), in order through the rows that scroll
and the buttons under them, and Return or Space presses the one it's on;
← and → move along a row of several (the durations, the buttons); →
opens a side window from its row, its first row lit (or lights that row
when the pointer opened it already), and ← closes it; on a slider or a
choice, ← and → change it; Escape closes the side window, then the menu
(`StatusMenuController.handleKey`, `KeyHighlight`, `HighlightKey`: one
mapping of the keys for the menu and Settings). A key with nothing to act
on doesn't beep. The pointer moves the same highlight, as in a menu. In
the player list, ↑ and ↓ move among the players, Return chooses the one
lit (with none, the first the search left while something is typed, else
nothing), and typing searches. With
keyboard navigation on, Tab and Space work too, the focus taking over from
the highlight. Both show as a tint of the accent color (`.focusTint`)
rather than a focus ring; rows that light up as menu items
(`MenuRowButtonStyle`) light up instead.

## Checking a change

Before a visible change is final:

1. **Propose it with pictures** of the real screens, before and after.
2. **Look at it:**
   - in **light and dark mode**;
   - in **English and German** (German is the longest), and in **Arabic**
     when the layout changes;
   - with **short and long lists** where lists are involved;
   - on **macOS 14.4** too when it touches Liquid Glass or its fallback
     (glass only shows from macOS 26).
3. **Check the text** against the rules above, and translate it.
4. **Update this guide** when the change adds or changes a pattern.
