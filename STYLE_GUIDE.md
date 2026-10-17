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

- **It looks like macOS.** Menus, pop-ups, alerts and file panels are the
  system's own. AutoHush's views use cards, chips and switches in the style
  of Control Center.
- **Liquid Glass from macOS 26, the same app before.** On macOS 26 and later
  cards and filled chips are Liquid Glass (see [Components](#components)),
  and macOS draws its own controls with it too; on macOS 14.4 to 25 they look
  as they always have. Glass only ever goes behind `if #available(macOS
  26, *)`, with today's look as the fallback: AutoHush still runs on macOS
  14.4. `Scripts/build-app.sh` records the SDK the app was built with, or
  macOS 26 and later would draw all of it the old way. Before macOS 26,
  Settings' title bar is see-through (the toolbar would draw a lighter
  band of its own over the page); the thin line beside its sidebar is
  macOS 14 and 15's own, as in Finder and System Settings, and stays.
- **One way to do each thing.** Use the shared components below rather than
  styling a screen by hand. A new pattern goes into the shared files, and
  into this guide, before it's used.
- **Easy to read.** Text is one step larger than the system's. In light
  mode, text has a contrast of at least 4.5:1 against its background.
- **Calm.** Nothing is red. Things move only when they change: rows that
  reorder slide into place. Besides that, only what shows AutoHush at work
  moves: a spinner while it does a step itself, and a countdown while time
  runs out; and a note that answers a click blinks for a moment (see
  `ChoiceChips`).

The shared files are in `Sources/AutoHushApp/Views/Components/`, one
component and its small parts per file: `Font+AutoHush.swift` holds the
text sizes, `AppearanceStyle.swift` the colors and `View+CaptionStyle.swift`
the caption style, `AccessibilityText.swift` what VoiceOver says of a
control that shows or hides what's under it (Expanded, Collapsed);
`ButtonStyles.swift`, `Card.swift`, `SectionHeading.swift`,
`SwitchRow.swift`, `ChoiceChips.swift`, `BottomBar.swift`, `PlayerTiles.swift`,
`WindowHeader.swift`, `ChecklistStepRow.swift`, `PermissionButton.swift`,
`NoteLabel.swift`, `SearchField.swift`, `IconChipButton.swift`,
`SymbolTile.swift`, `SupportLine.swift`, `BadgedHeading.swift`,
`WebAppsHeading.swift` and `OtherAppsHeading.swift` the components, and
`PlayerAlerts.swift` the alert before an added app is removed.

## Layout

| Where | Rule |
|---|---|
| Settings window | Laid out as System Settings: a sidebar of pages (`SettingsSidebar`) beside the page shown, whose name is the window's title, in the toolbar. No back or forward buttons. The user resizes it: **715 to 875 pt** wide and **560 to 900 pt** tall, opening at **760 × 620** the first time; it keeps its place and size between launches. The sidebar stays **235 pt**; the page grows from **480 to 640 pt**, with **16 pt** margins. Cards are **8 pt** apart. |
| Settings pages | General, Sound Sources · Detection, Fades, Advanced · Diagnostics, Updates, About, a gap between the groups. Each page fills the window and scrolls when it's taller (`SettingsPageScroll`). |
| Pages with a list | The heading and its controls stay at the top, and the buttons stay at the window's foot in a [`BottomBar`](#components); only the list between them scrolls (Apps, Diagnostics). |
| Diagnostics | Each part (how AutoHush is doing, the apps, the player, the detection, the permissions, AutoHush, the Mac) folds away when its heading is clicked, leaving a one-line summary; the heading's chevron points forward while folded and down while open. "Updated as it happens." heads the page, in `captionStyle`, above the first part (beside the foot's buttons it left them too little room in several languages). After a click, **Copy Report** says "Copied" for 2 s, as Copy Logs does. **Show Logs…** sits left of Copy Report and opens the logs window. |
| Other windows | The welcome, Add a Web App, learning and Add an App windows, and Add an App's Choose an App and warning windows (`HostedWindowController`), look like a Settings page: the title bar is part of the window (no band, no line), with the window's title in it in bold, as a page's name; the welcome window's title is its page's ("Choose Your Media Player", "Allow AutoHush to Work"). The content starts **2 pt** under the title bar with a [`WindowHeader`](#components) (the icon and what the window is for), has **20 pt** margins (`windowMargins`), groups under `SectionHeading`s in cards **8 pt** apart, and ends with the buttons in a [`BottomBar`](#components) across the window, the main one blue at the right. Their height follows their content; their width is fixed (below: the welcome window and the guiding windows; Add an App's three are **460 pt** wide and open centered, at the normal level, the Add an App window floating above other apps only while it waits for the app to play, so its steps stay in view). Like any window, each can be minimized (⌘M, or its yellow button). |
| Welcome window | Both pages **540 pt** wide, so the window keeps its width and its `PlayerTiles` go three a row as in Settings. Past **five rows** of tiles (the apps' and the web apps' together), they scroll inside their card. |
| The Dock | AutoHush lives in the menu bar, with no Dock icon, except while one of its windows is open, minimized ones included (`DockPresence`): then it's in the Dock and the app switcher, with the Mac's standard menu bar (`MainMenu`, see [Keyboard](#keyboard)), so its window keeps its place when the user leaves its desktop and comes back. |
| Menu | AutoHush's own rows are **345 pt** wide (`menuContentWidth`). Its sections ("Turn off for", "Playing Now") have **14 pt** side margins and **6 pt** above and below. The card at the top has **10 pt** of padding. The menu's own rows (players, Ignored Apps) are drawn by macOS, a point larger than its menu font; the players come under "Supported Apps" (`NSMenuItem.supportedAppsHeading`), then the apps added through a check under "Other Apps" (`NSMenuItem.otherAppsHeading`) with **Add an App…** after them, then the web apps under `WebAppsHeading` with **Add a Web App…** last. A menu row's image is set with `shownImage`: from macOS 27, AppKit hides menu items' images unless the item asks to show it (`preferredImageVisibility = .visible`). The toolbar's **Updates** checks in place: it says "Checking…" and the menu stays open until the result, then closes for the alert that tells it. |
| Menu bar icon | `MenuBarIcon`: a 17 pt template image in the 22 pt square item, centered. While an update waits (found, downloaded or installing: while the menu offers it), the image is the item's full **22 pt**, the tile still centered, with a disc of **8 pt** in its bottom-right corner, reaching into the room around the tile, a down arrow cut out of it and a **1.2 pt** gap cut out of the tile around it; the item keeps its width, and the image is drawn as it is (`imageScaling = .scaleNone`). |
| Guiding windows | **440 pt** wide. A window that walks the user through other apps (Add a Web App, learning a web app: Safari and the web app come in front meanwhile) floats above every app (`floatsInCorner`), in the top-right corner of the screen the pointer is on, **16 pt** from its edges, keeping its top edge as its steps come and go. Other windows open centered, at the normal level. |
| About | Centered, under AutoHush's icon at **96 pt**. Every gap between its parts shows **24 pt**. |
| Logs window | Opened by Diagnostics' **Show Logs…**; its title, "AutoHush Logs", in the title bar as in the other windows. The user resizes it: **760 × 440 pt** at least, opening centered at **960 × 640** the first time; it keeps its place and size between launches. At the top, the `SearchField`, then the time pop-up (This Launch, Last 24 Hours) and the level pop-up (All Levels, Problems Only). Under them, the columns' titles (Level, Time, Area, Message, in the user's language) in `appCaption` semibold, `.appSecondary`, in line with the rows and still while the entries scroll; each column is as wide as its title or its widest entry, **12 pt** apart. The entries fill one card, oldest first, a `CardDivider` between them: a mark (a problem's orange `exclamationmark.triangle.fill`; otherwise a small grey dot, filled for a notice, hollow for an info line), when (the date, the 24-hour time and the Mac's offset from UTC then, `15/10/2026 14:05:09 UTC+2`, as copies and saves say it too), the area (Player, Detection, Web Apps, Updates, Settings, App) in `appCaption`, and the message, selectable. Times, areas and entries are always in English, whatever the Mac's language: the log is never translated. It opens at the newest entry and follows new ones while **Follow new entries**, the switch at the left of the `BottomBar`, is on; **Save…** and **Copy Logs** sit at the right, and Copy Logs says "Copied" for 2 s, as Copy Report does. With nothing to show, the card says why: no match for the search, no problems, or nothing logged yet. |
| Full screen | No window goes full screen (`.fullScreenNone`): Settings' and the logs window's green button zooms them instead. The guiding windows are `.fullScreenAuxiliary`, so they float over an app that's full screen. |
| Section headings | **4 pt** in from the card's edge, in line with its text, with **6 pt** above (none for the first one on a page). In the other windows a heading has **8 pt** more above it than in Settings, so its group stands apart from the header and its notes. |

## Text sizes

Use the `Font` tokens. Never set a text's size by hand.

| Token | Size | For |
|---|---|---|
| `appLargeTitle` | 24 bold | The app's name in About |
| `appBody` | 14 | Plain text, row titles, and buttons in Settings and the windows (the default) |
| `appHeadline` | 14 bold | A card's title (the player's name in the menu), Diagnostics' headings |
| `appCallout` | 13 | The menu's chips, values, notes, search fields |
| `appSubheadline` | 12 | The status line under the menu card's title |
| `appCaption` | 11 | Descriptions under rows, section labels, captions |
| `appSidebarRow` | 16 | A page's name in Settings' sidebar |
| `appSidebarName` | 15 semibold | "AutoHush" at the foot of Settings' sidebar |

- **Numbers that change** (levels, timings) use `.monospacedDigit()`, so they don't jitter.
- **Symbols** may have their own sizes. The ones in use:
  - the menu toolbar's symbols are 15 pt;
  - the card's chevron is 9 pt bold;
  - Diagnostics' fold chevron is 11 pt semibold;
  - Diagnostics' status symbol is 28 pt;
  - a `SymbolTile`'s symbol (Settings' sidebar, the welcome window's
    permissions) is 16 pt semibold, on a 32 pt square;
  - a `WindowHeader`'s icon is 56 pt;
  - the "Add…" tile's `plus` is 14 pt medium;
  - the logs window's dot (a notice's or an info line's) is 6 pt;
  - the menu's headings over its players ("Supported Apps", "Other Apps",
    "Safari Web Apps") use a menu section header's font: the small system
    size, semibold.

## Colors

Use the color tokens. A view never uses a raw color such as `.red` or
`Color.gray`. The one exception is a drawing of something that isn't
AutoHush's own interface, such as the warning window's dimmed screen with a
wallpaper's colours (`CheckWarningView`'s `DimmedScreenPicture`): it shows
that thing as it looks, in both modes.

| Token | Light mode | Dark mode | For |
|---|---|---|---|
| `.primary` | system | system | Text and symbols |
| `.appSecondary` | black 68% | system secondary | Descriptions, section labels, values, captions |
| `.appWarning` | #B03000 | system orange | Things that need the user: warning symbols, a status line with a problem |
| `.appAccent` | accent mixed 45% with black | accent color | The accent color as text on its own tint: the "Recommended" `HeadingBadge` (4.5:1 or more with every macOS accent, inside a chosen card too) |
| `.appSuccess` | system green | system green | Symbols for what works (Diagnostics, the welcome window's permissions); never text, too faint in light mode |
| accent color | system | system | Switches that are on, the selected chip, links, the main button |
| `.cardFill` / `.cardBorder` | black 5% / 10% | quaternary 60% / none | A card's background and outline |
| `.chipFill` / `.chipHoverFill` | black 8% / 13% | quaternary 60% / quaternary | A chip at rest / under the pointer; search fields |
| `.switchOffFill` | black 26% | quaternary | A switch's track while off |
| `.warningBadgeFill` | deep orange 12% | orange 18% | Behind a `HeadingBadge` |
| `.selectedRowFill` | accent 14% | accent 18% | Behind a list row the user selected (Settings → Sound Sources); the accent `HeadingBadge`'s capsule |
| `.selectedTileFill` | accent 18% | accent 22% | Behind the chosen player's tile (`PlayerTiles`), the selected row of Choose an App's list, and the chosen choice card |
| `.sidebarSelectionFill` | black 10% | quaternary | Behind the page shown in Settings' sidebar |
| `.symbolTileFill` | accent 16% | accent 20% | The square behind a `SymbolTile`'s symbol (the symbol is the accent color) |

- **Problems** are orange with a warning triangle (`NoteLabel`), never red.
- **Disabled** controls show at 45% opacity. A control that's dimmed twice,
  inside a dimmed group, stays at 45%. A disabled main (blue) button has
  grey text (the primary color, dimmed), not white: disabled, it loses most
  of its blue, and white text would be unreadable in light mode.
- **Settings that only matter while a switch is on** show only then, under
  it in the same card (the fades' lengths under "Fade playback"). What the
  user can't change at all, because of the chosen player, is dimmed
  instead, with a note saying why.

## Components

| Component | Use it for |
|---|---|
| `Card` | A group of related rows on a rounded, tinted background (corner 12, padding 12); on macOS 26 and later a Liquid Glass panel (`.glassEffect(.regular)`, corner 18, padding 14). The menu's card is clear glass (`clearGlass`): its row ends just under it, and the regular glass's shadow would be cut off there in a straight line. Rows inside are 10 pt apart, with a `CardDivider` between rows that are separate items. |
| `SectionHeading` | The heading over a card in Settings and the other windows, e.g. "Timing", "Steps". |
| `SectionLabel` | A small grey label: the menu's headings ("Playing Now") and lead-ins above a control ("When an update is found"). |
| `RowTitle` | A row's title, with an optional description under it. |
| `SwitchRow` + `PillToggleStyle` | An on/off setting: the title on the left, the switch on the right. Switches are 36 × 21 pt; in lists of apps, 30 × 18 pt. |
| `ChoiceChips` | One choice among two to four options, as chips. The chosen one is filled with the accent color. |
| `.chip` button | Actions: "Check Now", "Reset List…". Corner 8; on macOS 26 and later a Liquid Glass capsule. |
| `ChipButtonStyle(filled: true)` | Chips in a row, such as the menu's durations ("5 min"). On macOS 26 and later Liquid Glass (corner 12), interactive, and tinted with the accent color when selected (`ChoiceChips`). |
| `ChipButtonStyle()` | Rows and buttons that light up only under the pointer: the menu's toolbar, the players' tiles, the player search's rows. |
| `ChipButtonStyle(cornerRadius: 6)` | The small button inside the menu card that lights up only under the pointer: the player button. |
| `ChipButtonStyle(filled: true, cornerRadius: 6)` | The small chips under the menu card's status line, each with its symbol: **Retry** (`arrow.clockwise`), **Reopen** (`arrow.clockwise`) and **Unmute** (`speaker.wave.2`). Settings → General's player card shows Reopen and Unmute too, as `.chip` buttons. |
| The card's status line with `info.circle` | When the media player couldn't be controlled ("Can’t control TIDAL right now", "Couldn’t pause — Safari is playing"), an `info.circle` in `.appSecondary` ends the line, kept with its last word by a no-break space; a click on the line closes the menu and opens an `InfoAlert`: what failed as its title ("Can’t Control TIDAL"), the cause in words, then the log's English for a bug report. Diagnostics shows the same as "Last error". |
| The card's Reopen and Unmute | A player that must be reopened to be controlled wherever its window is (an Electron app opened without its option) says "<player> needs reopening" in orange, with **Reopen** under it (the line names the player), whose tooltip says why. Choosing such a player asks first, in a warning alert: "Reopen <player>?", why, the checkbox "Always reopen <player> this way" (the alert's own suppression checkbox: from then on it's reopened without asking), then **Reopen <player>** (Return) and **Cancel** (Escape), which leaves the card saying so. A player muted instead of paused says "Muted — Safari is playing", with **Unmute**, which lets it be heard until the other apps stop. |
| `IconChipButton` | An action with only a symbol, beside a heading or a pop-up (22 × 20 pt, corner 6): the sort arrow, the magnifiers. |
| `HeadingBadge` | A word in an orange capsule after a heading or a name that qualifies it: "Experimental" after "Safari Web Apps", "Checked by you" after "Other Apps", "Untested" after an untested web app, "Needed" after a permission a step can't go without, while it's missing. In `.appAccent` (`accent: true`, on `.selectedRowFill`) for a word that recommends: "Recommended" beside the way Add an App suggests. |
| `BadgedHeading` | A heading with a `HeadingBadge` after it and a note under it, over a group of players: `WebAppsHeading` and `OtherAppsHeading` ("Other Apps", "Checked by you", "Controlled the ways a check found to work.") are made of it. While no app was added, `OtherAppsHeading` drops its badge and says what Add… does instead ("Add any other app: a check finds how to pause and play it."), so the empty group doesn't read as checked already. |
| `PlayerTiles` | Where players are offered in a window (Settings → General, the welcome window): a card of tiles, three a row, each 44 pt tall: the apps under "Supported Apps", a `CardDivider`, the apps added through a check under `OtherAppsHeading` with an "Add…" tile, a `CardDivider`, the web apps under `WebAppsHeading`, then an "Add…" tile (`plus`). A tile is a chip (corner 10): the player's 24 pt icon, then its name in `appCallout` with what a row would say under it, shorter where it must fit: "Click to add" (a suggested web app), the "Untested" `HeadingBadge`, "Not installed" (dimmed), or, for an app added through a check that can only be muted, "Muted only" (its menu row: "Muted instead of paused"). In AntiDot mode, which hears no sound, such an app can't be chosen, nor one only its sound tells (a Now Playing row that never shows its state, Qobuz's): it's dimmed, saying "Not in AntiDot" ("Not in AntiDot mode" on its menu row), with why in its tooltip and VoiceOver hint; chosen already, its tile stays outlined. The other way round, while it's the player, Settings → Detection's AntiDot mode switch is off and dimmed, with "Unavailable with <player>: AutoHush can only mute it, which needs Audio Recording, and AntiDot mode doesn't use it." (or "…: only its sound tells whether it plays, which needs Audio Recording, and AntiDot mode doesn't use it.") under it, and no "Use AntiDot Mode Instead" is offered. Under the pointer, or while it has the keyboard's focus, an added app's tile shows a × in its top-right corner (`xmark.circle.fill`, 16 pt, white on `.appSecondary`), with its help tag "Remove <app>…"; a right-click offers "Remove <app>…" too, and VoiceOver gets it as an action. It asks first (`PlayerAlerts.remove`: **Remove**, the default button, which Return presses, and **Cancel**, Escape). Removing the chosen player opens the welcome window, to choose another. In the menu, holding Option turns each added app's row into "Remove <app>…" (an alternate item). The chosen (or picked) one is on `.selectedTileFill`, outlined in the accent color (2 pt), without a check, so its whole name fits. `maxVisibleRows` makes the tiles scroll inside the card past that many rows; a search keeps its height while you type. The menu keeps its rows. |
| `WebAppsHeading` | "Safari Web Apps", its "Experimental" badge and the note that every website works differently, over the web apps wherever players are offered. In the menu it's a drawn row (`NSMenuItem.webAppsHeading`), since a section header can't show a badge; "Supported Apps" over the apps is drawn the same way, so the two match. |
| Pop-ups | The system's pop-up (`NSPopUpButton` or a SwiftUI `Picker` with `.menu`), always **without a border**: `isBordered = false` or `.buttonStyle(.borderless)`. |
| `SearchField` | Every search. Its ✕ closes the search or, when the search can't close, clears it. |
| `NoteLabel` | A note with a symbol: `.warning` (orange triangle) or `.info` (grey "i"). |
| `.captionStyle()` | A description or note under a card or a control: small, grey, wrapping. |
| `BottomBar` | Buttons fixed at the foot of a Settings page with a list, with a line above them only while the list scrolls under them, and at the foot of the other windows, always with its line (`margin: 20`, the windows' margin). |
| `WindowHeader` | The top of the welcome, Add a Web App, learning, Add an App, Choose an App and warning windows, under the title in the title bar: the icon (AutoHush's, the player's, Safari's, the app to check's; 56 pt) and what the window is for in `appBody`, `.appSecondary`, the icon centered on the text. |
| `SymbolTile` | A symbol in the accent color on a square tinted with it (`.symbolTileFill`, 32 pt, corner 8): Settings' sidebar pages, the welcome window's permissions. |
| `MoreSettingsRowView` | The menu's More Settings, under Ignored Apps: a small chevron (10 pt bold, `appSecondary`) on a **44 × 16 pt** `.chipFill` capsule, centered, pointing down while folded and up while open; open, Detection's, Fades' and Advanced's rows above it, each page's name (`SectionLabel`) over its first row, as Settings shows them (`SettingsSwitchRow` without subtitles, `TimingSliderRow(compact:)`: callout title and value, a small slider, no help). Each is a menu row of its own (`MoreSettingsRow`), shown or hidden whole: a menu doesn't follow a row whose height changes while it's open, even after the click (2026-10-17). Unfolding, or a switch that shows rows, brings them in from the top within **0.2 s**, close together at first and easing apart, each one's content fading in and drifting down **8 pt** on a soft spring (0.35 s, bounce 0.2); folding, or a switch that hides rows, fades them out from the bottom up, each row going once faded (0.12 s). Always once the click is handled (rows hidden during it crop the menu's top); at once with Reduce Motion, or while the menu is closed. |
| `SettingsSwitchRow`, `TimingSliderRow` | The switches and timings Settings → Detection, → Fades and → Advanced share with the menu (`SettingsSwitch`, `SettingsTiming`): one place for their words, ranges and when one is dimmed. |
| `SettingsSidebar` | Settings' pages as rows: the page's `SymbolTile`, its name in `appSidebarRow`, the page shown on a grey `.sidebarSelectionFill`. At its foot, under a line: "AutoHush" (`appSidebarName`), the version, and the compact `SupportLine`. |
| `RestoreDefaultsButton` | Under a page's cards on the right: sets that page's settings back (Detection's timings, or the fades), dimmed while they're the defaults. |
| `SupportLine` | "Would you like to support me?" with its link, in About and, compact, at the foot of Settings' sidebar. |
| `LearningSteps` | What the user does so AutoHush can learn a player (play it; AutoHush then pauses it), each step ticked in `.appSuccess` once seen. The step to do now is semibold, with an arrow in the accent color (`StepSymbol`). A step AutoHush does itself shows a spinner meanwhile; one it couldn't do gets an orange `xmark.circle.fill`, its reason as a `NoteLabel`, and two buttons side by side, the way forward in blue ("Try Again") and the other way grey ("Pause It Manually"), which adds the user's own step. A step's buttons stay on one line each: when two don't fit side by side (longer languages), they go one under the other. They show only in windows: the learning window, and Add a Web App once it has made the web app. |
| `NumberedStepRow` | A step of a window whose steps go in order and are few (Add an App): its number in a circle while it's to come (`N.circle`, `.appSecondary`), filled with the accent color while it's the one to do (`N.circle.fill`, title semibold), a check in `.appSuccess` once done (title in `.appSecondary`), a spinner while AutoHush does it, an orange `xmark.circle.fill` once it failed. All marks are 18 pt wide, so the titles line up. Under the title: its lines (`.captionStyle()`), what it needs (a list, permission rows, the ways found), a warning (`NoteLabel`), then its button, blue for the way forward (Return presses it), grey for another way on ("Skip"). The keyboard's focus moves to the main control of the step to do now. A failed check's **Show Log…** is dimmed while there's no log. The whole window shows every step from the start, so what's coming is clear before it begins. |
| Choice cards | Choosing one of a few options that each need a line of why (Add an App's last step, the ways that worked): each a card (corner 10) with its mark, name and grey note, outlined in `.separator` (1 pt); the chosen one on `.selectedTileFill`, outlined in the accent color (2 pt), as a chosen tile. The suggested one comes first, with an accent "Recommended" `HeadingBadge`, and is chosen until another is. Options that can't be chosen are listed under them, not as cards, dimmed (60%), each with why (for one not checked, what was missing); in AntiDot mode, that includes a way only the app's sound tells about. Notes are fragments, without periods. The step's main button acts on the chosen one; while Now Playing is hidden in the menu bar, a grey **Check Again** sits beside it, and an **Open Menu Bar Settings…** chip above them (Control Center's on macOS 15) opens the pane where it's shown, as the alert about a failed pause through it does (its first button, Return; **OK**, Escape). |
| A warning window before a takeover | Before AutoHush takes over the Mac (Add an App's check): its own window, titled for what it does ("Check Deezer"), the app's 56 pt icon, what happens and for how long, pictures of it (`SymbolTile`s for the window's states, in a grid of 4 columns; a drawn dimmed screen), then **Cancel** and the action in blue ("Start the Check"). Nothing starts until that button. |
| A check's panel | While AutoHush takes over the Mac: a borderless panel at the bottom right of the main display, on every desktop, never taking the keyboard: the app's icon, "Checking <app>…" (two lines at most) with what it does, **Stop**; what it asks of the user on an orange line with the time left; the window states as segments, the one under test and what's pressed; and, while the mouse and keyboard are blocked, a line saying so (`hand.raised`, orange). The screen dims (black at 50%) except the panel while input is blocked. |
| `CountdownBanner` | How long is left to do a step, as a whole sentence ("You have 0:45 to pause it and click It’s Paused."): semibold `.appCallout` in `.appWarning` with a timer, on a `.warningBadgeFill` rounded line, above the step's button. |
| `PermissionButton` | The button that allows a missing permission, labeled for where it stands: "Open <player>" (Automation is asked only while the player runs), "Allow…" or the permission's "Allow … Access…" (macOS's prompt when it hasn't asked, else System Settings), "Reopen AutoHush" (Audio Recording switched on in System Settings). Nothing once it's allowed. `prominent` makes it the blue chip when it's the window's next step. |
| `WelcomePermissionsView` | The welcome window's second page: what the chosen player needs under "Permissions", a row each (a `SymbolTile`, `RowTitle`, then the `PermissionButton` or "Allowed" in `.appSecondary` after a check in `.appSuccess`), "Use AntiDot Mode Instead" under Audio Recording, Back and Done in the `BottomBar`. |

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
says what happens without each, then "Allow it now, or go on without it.",
with **Continue** (blue) under it; with everything allowed, the step goes
on by itself.

**App icons** come from `AppIcon` (or `PlayerOption.icon`), at the size for
where they appear:

| Size | Where |
|---|---|
| 16 pt | Menu rows and pop-up items |
| 20 pt | Compact lists: Playing Now, the player search |
| 24 pt | Settings lists: Apps, Diagnostics; the players' tiles (`PlayerTiles`) |
| 34 pt | The app being checked, in a check's panel |
| 36 pt | The menu card's player |
| 56 pt | The chosen player in Settings → General; a `WindowHeader`'s icon |
| 96 pt | AutoHush's own icon in About |

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
  has a checkmark on the left.
- Among tiles (Settings → General, the welcome window), the chosen or picked
  one is tinted and outlined with the accent color (no check, so the whole
  name fits).

## Lists and searches

- **Order:** a list has an obvious order and keeps it. Settings → Sound Sources lets
  you choose the order, and remembers it. Where players are offered:
  - **Apps** are listed by how many people use them, with those that
    aren't installed after them, dimmed, and marked "Not installed".
  - **Safari web apps** come last, under the `WebAppsHeading` (with its
    "Experimental" badge and note): the tested sites' web apps by name
    (each named as its site), the tested sites not added yet, then any
    other web app by name, with an "Untested" `HeadingBadge` (under its
    name on a tile; in menus and pop-ups, after it:
    `NSMenuItem.setTitle(_:badge:font:maxWidth:)` draws it into the title,
    cutting a long name short with "…" so the badge always shows).
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
    (`StepActionButton`), outside the step's VoiceOver element, and Return
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
  or more (not counting suggested web apps). Settings → General shows every
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
  its switch, selects it, behind a `.selectedRowFill` rounded rectangle; a
  second click deselects it. From the keyboard, Tab reaches the rows (with
  keyboard navigation on) and Space selects the focused one. **Remove** sits
  in the bottom bar after the button that adds, disabled while nothing is
  selected. Removing something whose loss changes what AutoHush does (an
  app turned off would pause the player again) asks first, as
  **Reset List…** does; one that changes nothing goes at once. The row's
  right-click menu offers the same (**Remove from List**), and VoiceOver
  gets it as an action.

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
| Section headings: "Pauses Playback", "Playing Now", "Apps with Sound" | Descriptions, notes and status lines |
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
  ("Choose Your Media Player", "Media player"); **playback** is for short
  labels about pausing, resuming and fading ("Pause playback after", "Fade
  playback", "Pauses Playback"); **your player** is for sentences about what
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
  in English and in every language that has them ("l’app", "Mac’te"). A
  straight ' never shows; a test checks every catalog.
- **Ellipsis** (`…`, a single character) ends a button or menu item that
  opens a window or asks for something more before it acts (a panel, a
  dialog): "Learn Controls…", "Reset List…". It also ends a state in
  progress ("Checking…"). A button that acts at once has none.
- **Em dash with spaces** joins a state and its reason: "Paused — Safari is
  playing", "Ignored — your player keeps playing".
- **Quotation marks** are curly in English (“ ”). Each language uses its own
  («  », „ “, 「 」).
- **Periods** end full sentences: descriptions and notes. Fragments have
  none: subtitles ("Pauses your player"), status lines, labels and buttons.
- **Numbers** are digits, with units in the user's format: "0.5 s",
  "-60 dB" (a hyphen for minus, as numbers are printed), "5 min".
- **Shortcuts** read like Apple's own actions: a name that says what the
  action does ("Set Auto-Pause", "Get Auto-Pause"), a summary that reads as
  a sentence with the choices in it ("Turn Auto-Pause On"), and a full
  sentence for the description. An App Shortcut's phrase names the app
  ("… in AutoHush"), as Siri requires: every translation keeps
  `${applicationName}`, and a test checks.

## Translations

AutoHush is translated into 34 languages besides English. DEVELOPMENT.md's
[Translations](DEVELOPMENT.md#translations) section explains how; for style:

- **Every change translates every language.** A new or changed English
  string is translated into all 34 before the change is done.
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
    something needs the user, or while Auto-Pause is off (the icon dimmed),
    the menu's status line ("AutoHush: Spotify isn’t running", "AutoHush:
    Auto-Pause is off until 15:30"), never a word of AutoHush's own like
    "degraded". While an update waits, it adds ", update available".
  - A slider says what it sets (Detection's and Fades' timings: the row's
    title) and its value as the row shows it ("0.5 s"); the row's own text
    is hidden from VoiceOver, so it's read once.
  - What an image alone tells is said in words: a web app whose name is
    also an app's reads "Spotify, Safari web app" where players are offered
    (`PlayerOption.spokenName`), as its icon's Safari badge shows; an app
    added through a check that's a Chromium browser's web app always reads
    whose it is ("SoundCloud, Google Chrome web app"), as its browser badge
    shows; and an untested web app's menu row, whose "Untested" badge is
    drawn into its title, reads "Untested" after its name.
- **Decorative images** (app icons beside their names, symbols beside text,
  the menu toolbar's symbols, the card's chevron) are hidden from VoiceOver.
- **Headings:** `SectionHeading`s, the menu's "Turn off for" and "Playing
  Now", and Diagnostics' headings carry the heading trait, so VoiceOver can
  move from one to the next. A heading or button that folds a part away
  (Diagnostics' headings, the menu card's player button) says "Expanded"
  or "Collapsed" as its value.
- **What changes away from VoiceOver's cursor is announced:** "Copied"
  after Copy Report and Copy Logs, why Add a Web App couldn't take the
  address, a step's warning when it shows or changes, the card's line after
  Retry, why a window waits for a permission, when it opens and when it
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
  do now each time it changes (`announcesCurrentStep`).
- **Numbered steps** (`NumberedStepRow`, Add an App): each step's title is a
  heading read with its number ("Step 2 of 6, …"), with where it stands as
  its value ("Completed", "In progress", "To do", "Failed"), so VoiceOver
  moves from step to step; its mark is hidden, and its lines and buttons
  are read on their own. The window announces the step to do now, and a
  step's warning or failure, as they come.
- **Contrast:** text in light mode keeps at least 4.5:1.

## Keyboard

AutoHush has **no keyboard shortcuts of its own, and all of Apple's
standard ones**:
- **The menu bar** (`MainMenu`), while a window is open: the AutoHush menu
  (About, Settings… ⌘,, Services, Hide ⌘H, Hide Others ⌥⌘H, Show All,
  Quit ⌘Q), Edit (Undo ⌘Z, Redo ⇧⌘Z, Cut ⌘X, Copy ⌘C, Paste ⌘V, Delete,
  Select All ⌘A, Find… ⌘F) and Window (Close ⌘W, Minimize ⌘M, Zoom, Bring
  All to Front), in macOS's own words in every language. The Edit menu is
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
- **Tab and Space** move and press as macOS's keyboard navigation does
  (when it's on). Settings → Sound Sources' rows take the focus too, and Space
  selects the focused one, so **Remove** can be reached. In Add an App's
  list of apps, ↑ and ↓ in its search move the selection, and Return
  chooses it.
- **Escape** presses Cancel or Later (`.cancelAction`, or
  `keyEquivalent = "\u{1b}"` on an alert's Later or Cancel); while a check
  runs, it's the check's Stop.
- **Never a shortcut Apple doesn't define**, and none on the status menu's
  rows. ⌥-clicking Settings in the menu opens Diagnostics.

A field in the open status menu needs AppKit to give it the keyboard (see
`StatusMenuController`). The menu's own SwiftUI rows (the card's switch
and buttons, Turn off for, Playing Now, the toolbar) are for the pointer
and VoiceOver: an open menu gives SwiftUI no keyboard focus.

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
