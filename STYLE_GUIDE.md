# AutoHush Style Guide

How AutoHush looks and reads, so every change fits in. It covers the menu, the
Settings window, the other windows (welcome, Add a Web App, learning) and
every text the app shows. When
something isn't covered here, match the screens that already exist, then
macOS's own conventions ([Apple's Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)).

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
  and macOS draws its own controls with it too; on macOS 15 to 25 they look
  as they always have. Glass only ever goes behind `if #available(macOS
  26, *)`, with today's look as the fallback: AutoHush still runs on macOS
  15. `Scripts/build-app.sh` records the SDK the app was built with, or
  macOS 26 and later would draw all of it the old way.
- **One way to do each thing.** Use the shared components below rather than
  styling a screen by hand. A new pattern goes into the shared files, and
  into this guide, before it's used.
- **Easy to read.** Text is one step larger than the system's. In light
  mode, text has a contrast of at least 4.5:1 against its background.
- **Calm.** Nothing is red. Things move only when they change: rows that
  reorder slide into place, and nothing else animates.

The shared files are in `Sources/AutoHushApp/General/`: `CardStyles.swift`
(text sizes, colors and most components), `SearchField.swift`,
`NoteLabel.swift`, `SupportLine.swift` and `AppIcon.swift`.

## Layout

| Where | Rule |
|---|---|
| Settings window | Laid out as System Settings: a sidebar of pages (`SettingsSidebar`) beside the page shown, whose name is the window's title, in the toolbar. No back or forward buttons. The user resizes it: **715 to 875 pt** wide and **560 to 900 pt** tall, opening at **760 × 620** the first time; it keeps its place and size between launches. The sidebar stays **235 pt**; the page grows from **480 to 640 pt**, with **16 pt** margins. Cards are **8 pt** apart. |
| Settings pages | General, Apps · Detection, Fades · Diagnostics, Updates, About, a gap between the groups. Each page fills the window and scrolls when it's taller (`SettingsPageScroll`). |
| Pages with a list | The heading and its controls stay at the top, and the buttons stay at the window's foot in a [`BottomBar`](#components); only the list between them scrolls (Apps, Diagnostics). |
| Other windows | The welcome, Add a Web App and learning windows (`HostedWindowController`) look like a Settings page: the title bar is part of the window (no band, no line), with the window's title in it in bold, as a page's name; the welcome window's title is its page's ("Choose Your Media Player", "Allow AutoHush to Work"). The content starts **2 pt** under the title bar with a [`WindowHeader`](#components) (the icon and what the window is for), has **20 pt** margins (`windowMargins`), groups under `SectionHeading`s in cards **8 pt** apart, and ends with the buttons in a [`BottomBar`](#components) across the window, the main one blue at the right. They're sized to their content. |
| Welcome window | Both pages **540 pt** wide, so the window keeps its width and its `PlayerTiles` go three a row as in Settings. Past **five rows** of tiles (the apps' and the web apps' together), they scroll inside their card. |
| The Dock | AutoHush lives in the menu bar, with no Dock icon, except while one of its windows is open, minimized ones included (`DockPresence`): then it's in the Dock and the app switcher, with the Mac's standard menu bar (`MainMenu`, see [Keyboard](#keyboard)), so its window keeps its place when the user leaves its desktop and comes back. |
| Menu | AutoHush's own rows are **345 pt** wide (`menuContentWidth`). Its sections ("Turn off for", "Playing Now") have **14 pt** side margins and **6 pt** above and below. The card at the top has **10 pt** of padding. The menu's own rows (players, Ignored Apps) are drawn by macOS, a point larger than its menu font; the players come under "Supported Apps" (`NSMenuItem.supportedAppsHeading`), then the web apps under `WebAppsHeading`. A menu row's image is set with `shownImage`: from macOS 27, AppKit hides menu items' images unless the item asks to show it (`preferredImageVisibility = .visible`). |
| Guiding windows | **440 pt** wide. A window that walks the user through other apps (Add a Web App, learning a web app: Safari and the web app come in front meanwhile) floats above every app (`floatsInCorner`), in the top-right corner of the screen the pointer is on, **16 pt** from its edges, keeping its top edge as its steps come and go. Other windows open centered, at the normal level. |
| About | Centered. Every gap between its parts shows **24 pt**. |
| Section headings | **4 pt** in from the card's edge, in line with its text, with **6 pt** above (none for the first one on a page). |

## Text sizes

Use the `Font` tokens. Never set a text's size by hand.

| Token | Size | For |
|---|---|---|
| `appLargeTitle` | 24 bold | The app's name in About |
| `appBody` | 14 | Plain text and row titles (the default) |
| `appHeadline` | 14 bold | A card's title (the player's name in the menu), Diagnostics' headings |
| `appCallout` | 13 | Buttons, values, notes, search fields |
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
  - the menu's headings over its players ("Supported Apps", "Safari Web
    Apps") use a menu section header's font: the small system size,
    semibold.

## Colors

Use the color tokens. A view never uses a raw color such as `.red` or
`Color.gray`.

| Token | Light mode | Dark mode | For |
|---|---|---|---|
| `.primary` | system | system | Text and symbols |
| `.appSecondary` | black 68% | system secondary | Descriptions, section labels, values, captions |
| `.appWarning` | #B03000 | system orange | Things that need the user: warning symbols, a status line with a problem |
| `.appSuccess` | system green | system green | Symbols for what works (Diagnostics) |
| accent color | system | system | Switches that are on, the selected chip, links, the main button |
| `.cardFill` / `.cardBorder` | black 5% / 10% | quaternary 60% / none | A card's background and outline |
| `.chipFill` / `.chipHoverFill` | black 8% / 13% | quaternary 60% / quaternary | A chip at rest / under the pointer; search fields |
| `.switchOffFill` | black 26% | quaternary | A switch's track while off |
| `.warningBadgeFill` | deep orange 12% | orange 18% | Behind a `HeadingBadge` |
| `.selectedRowFill` | accent 14% | accent 18% | Behind a list row the user selected (Settings → Apps) |
| `.sidebarSelectionFill` | black 10% | quaternary | Behind the page shown in Settings' sidebar |
| `.symbolTileFill` | accent 16% | accent 20% | The square behind a `SymbolTile`'s symbol (the symbol is the accent color) |

- **Problems** are orange with a warning triangle (`NoteLabel`), never red.
- **Disabled** controls show at 45% opacity. A control that's dimmed twice,
  inside a dimmed group, stays at 45%.
- **Settings that only matter while a switch is on** show only then, under
  it in the same card (the fades' lengths under "Fade playback"). What the
  user can't change at all, because of the chosen player, is dimmed
  instead, with a note saying why.

## Components

| Component | Use it for |
|---|---|
| `Card` | A group of related rows on a rounded, tinted background (corner 12, padding 12); on macOS 26 and later a Liquid Glass panel (`.glassEffect(.regular)`, corner 18, padding 14). Rows inside are 10 pt apart, with a `CardDivider` between rows that are separate items. |
| `SectionHeading` | The heading over a card in Settings and the other windows, e.g. "Timing", "Steps". |
| `SectionLabel` | A small grey label: the menu's headings ("Playing Now") and lead-ins above a control ("When an update is found"). |
| `RowTitle` | A row's title, with an optional description under it. |
| `SwitchRow` + `PillToggleStyle` | An on/off setting: the title on the left, the switch on the right. Switches are 36 × 21 pt; in lists of apps, 30 × 18 pt. |
| `ChoiceChips` | One choice among two to four options, as chips. The chosen one is filled with the accent color. |
| `.chip` button | Actions: "Check Now", "Reset List…". Corner 8; on macOS 26 and later a Liquid Glass capsule. |
| `ChipButtonStyle(filled: true)` | Chips in a row, such as the menu's durations ("5 min"). On macOS 26 and later Liquid Glass (corner 12), interactive, and tinted with the accent color when selected (`ChoiceChips`). |
| `ChipButtonStyle()` | Rows and buttons that light up only under the pointer: the menu's toolbar, the players' tiles, the player search's rows. |
| `ChipButtonStyle(cornerRadius: 6)` | Small buttons inside the menu card: the player button and Retry. |
| The card's status line with `info.circle` | When the media player couldn't be controlled ("Can't control TIDAL right now", "Couldn't pause — Safari is playing"), an `info.circle` in `.appSecondary` ends the line, kept with its last word by a no-break space; a click on the line closes the menu and opens an `InfoAlert`: what failed as its title ("Can't Control TIDAL"), the cause in words, then the log's English for a bug report. Diagnostics shows the same as "Last error". |
| `IconChipButton` | An action with only a symbol, beside a heading or a pop-up (22 × 20 pt, corner 6): the sort arrow, the magnifiers. |
| `HeadingBadge` | A word in an orange capsule after a heading or a name that qualifies it: "Experimental" after "Safari Web Apps", "Untested" after an untested web app. |
| `PlayerTiles` | Where players are offered in a window (Settings → General, the welcome window): a card of tiles, three a row, each 44 pt tall: the apps under "Supported Apps", a `CardDivider`, the web apps under `WebAppsHeading`, then an "Add…" tile (`plus`). A tile is a chip (corner 10): the player's 24 pt icon, then its name in `appCallout` with what a row would say under it: "Click to add" (a suggested web app), the "Untested" `HeadingBadge`, or "Not installed" (dimmed). The chosen (or picked) one is on `.selectedTileFill`, outlined in the accent color (2 pt), without a check, so its whole name fits. `maxVisibleRows` makes the tiles scroll inside the card past that many rows; a search keeps its height while you type. The menu keeps its rows. |
| `WebAppsHeading` | "Safari Web Apps", its "Experimental" badge and the note that every website works differently, over the web apps wherever players are offered. In the menu it's a drawn row (`NSMenuItem.webAppsHeading`), since a section header can't show a badge; "Supported Apps" over the apps is drawn the same way, so the two match. |
| Pop-ups | The system's pop-up (`NSPopUpButton` or a SwiftUI `Picker` with `.menu`), always **without a border**: `isBordered = false` or `.buttonStyle(.borderless)`. |
| `SearchField` | Every search. Its ✕ closes the search or, when the search can't close, clears it. |
| `NoteLabel` | A note with a symbol: `.warning` (orange triangle) or `.info` (grey "i"). |
| `.captionStyle()` | A description or note under a card or a control: small, grey, wrapping. |
| `BottomBar` | Buttons fixed at the foot of a Settings page with a list, with a line above them only while the list scrolls under them, and at the foot of the other windows, always with its line (`margin: 20`, the windows' margin). |
| `WindowHeader` | The top of the welcome, Add a Web App and learning windows, under the title in the title bar: the icon (AutoHush's, the player's, Safari's; 56 pt) and what the window is for in `appBody`, `.appSecondary`, the icon centered on the text. |
| `SymbolTile` | A symbol in the accent color on a square tinted with it (`.symbolTileFill`, 32 pt, corner 8): Settings' sidebar pages, the welcome window's permissions. |
| `SettingsSidebar` | Settings' pages as rows: the page's `SymbolTile`, its name in `appSidebarRow`, the page shown on a grey `.sidebarSelectionFill`. At its foot, under a line: "AutoHush" (`appSidebarName`), the version, and the compact `SupportLine`. |
| `RestoreDefaultsButton` | Under a page's cards on the right: sets that page's settings back (Detection's timings, or the fades), dimmed while they're the defaults. |
| `SupportLine` | "Would you like to support me?" with its link, in About and, compact, at the foot of Settings' sidebar. |
| `LearningSteps` | What the user does so AutoHush can learn a player (play it; AutoHush then pauses it), each step ticked in `.appSuccess` once seen. The step to do now is semibold. A step AutoHush does itself shows a spinner meanwhile; one it couldn't do gets an orange `xmark.circle.fill`, its reason as a `NoteLabel`, and two buttons side by side, the way forward in blue ("Try Again") and the other way grey ("Pause It Manually"), which adds the user's own step. A step's buttons stay on one line each: when two don't fit side by side (the menu, longer languages), they go one under the other. They show only in the learning window. |
| `CountdownBanner` | How long is left to do a step, as a whole sentence ("You have 0:45 to pause it and click It's Paused."): semibold `.appCallout` in `.appWarning` with a timer, on a `.warningBadgeFill` rounded line, above the step's button. |
| `PermissionButton` | The button that allows a missing permission, labeled for where it stands: "Open <player>" (Automation is asked only while the player runs), "Allow…" or the permission's "Allow … Access…" (macOS's prompt when it hasn't asked, else System Settings), "Reopen AutoHush" (Audio Recording switched on in System Settings). Nothing once it's allowed. `prominent` makes it the blue chip when it's the window's next step. |
| `WelcomePermissionsView` | The welcome window's second page: what the chosen player needs under "Permissions", a row each (a `SymbolTile`, `RowTitle`, then the `PermissionButton` or an "Allowed" check in `.appSuccess`), "Use AntiDot Mode Instead" under Audio Recording, Back and Done in the `BottomBar`. |

**Permission blocks.** Wherever something needs a permission that's
missing, say what's missing in a `NoteLabel` (`.warning`) with its
`PermissionButton` right under it, and keep the main action disabled
(Continue, Done) or its steps locked (`lock.circle`, grey) until it's
allowed. Follow the permission while the window shows (about once a
second), so it unlocks by itself; never ask the user to click again.
Audio Recording always offers "Use AntiDot Mode Instead" beside it.

**App icons** come from `AppIcon` (or `PlayerOption.icon`), at the size for
where they appear:

| Size | Where |
|---|---|
| 16 pt | Menu rows and pop-up items |
| 20 pt | Compact lists: Playing Now, the player search |
| 24 pt | Settings lists: Apps, Diagnostics; the players' tiles (`PlayerTiles`) |
| 36 pt | The menu card's player |
| 56 pt | The chosen player in Settings → General; a `WindowHeader`'s icon |

**Marking the chosen item:**
- In a list that acts on a click, as menus and pop-ups do, the chosen item
  has a checkmark on the left.
- Among tiles (Settings → General, the welcome window), the chosen or picked
  one is tinted and outlined with the accent color (no check, so the whole
  name fits).

## Lists and searches

- **Order:** a list has an obvious order and keeps it. Settings → Apps lets
  you choose the order, and remembers it. Media players are listed by how
  many people use them, with those that aren't installed after them,
  dimmed, and marked "Not installed". Safari web apps come last, under the
  `WebAppsHeading` (with its "Experimental" badge and note): those of the
  tested sites by name, the tested sites not added yet, then any other web
  app by name, with an "Untested" `HeadingBadge` (under its name on a
  tile; in menus and pop-ups, after it: `NSMenuItem.setTitle(_:badge:font:maxWidth:)`
  draws it into the title, cutting a long name short with "…" so the badge
  always shows). A tested site's web app is named as the site. They're in
  line with the rows' icons in menus and with the cards' text among tiles. A search keeps the heading only while a web app
  matches. The "Add a Web App" and learning windows show the same warning
  as a `NoteLabel` under their title. Suggested web apps (the tested sites
  not added yet) are marked
  "Not installed" in menus ("Click to add" on a tile) like a missing app but
  not dimmed, with the `arrow.down.circle` symbol for an icon: a click opens
  "Add a Web App" filled in with the address.
  **Add a Web App…** (with `plus.circle`) comes last
  wherever players are offered: the menu's last row, and the last tile (as
  "Add…") among `PlayerTiles`.
- **A web app's controls** have one place: a `ControlsRow` ("Controls",
  whether they're learned, and a `.chip`) at the foot of the menu's card and
  on Settings → General's player card, nowhere else. The button says
  **Learn Controls** until they're learned and **Learn Again** after; it
  opens a new learning window that starts from the first step, closing one
  still open. What was learned keeps working, and the row keeps saying it's
  learned, until **It's Playing** is taken there; closing the window before
  that keeps it. Meanwhile the window leaves out its "presses nothing on the
  page" line, untrue then. Once learned, the row says only "Learned." and
  how to learn them again, so it fits the menu. In the menu its text is `appCallout`, as the menu's chips'.
- **Learning steps show only in a window** (the learning window, or Add a
  Web App once it made the web app), never in the menu or Settings.
- **A process the user waits for** shows its steps in a card, as the
  "Add a Web App" window does: done steps ticked in `.appSuccess` and dimmed,
  the current one bold with an accent arrow and a caption under it, the
  next ones as empty circles. A tip on how to do a step (`.captionStyle()`)
  shows under that step only while it's the one to do. The window closes by
  itself once done. Its button says **Cancel** while closing it stops the
  process, and **Later** once what's left goes on anyway (as in the
  learning window).
  - **A step the user says is done** (It's Playing, It's Paused, Add to Dock)
    has its button under its caption while it's the one to do: a blue chip
    (`StepActionButton`), outside the step's VoiceOver element. Its caption
    ends by naming the button ("Then click It's Paused."). The same steps
    and buttons show in both windows that show them (learning, Add a Web
    App).
  - **A time limit** shows as a `CountdownBanner`, a whole sentence that
    counts down ("You have 0:45 to pause it and click It's Paused.").
  - **A click that couldn't be taken** says why in a `NoteLabel` under that
    step, until the next click.
  - **A step only some cases need** ("Answer the site in Safari") shows only
    once it's needed, and stays ticked afterwards.
- **Searches** appear where a list can grow long: always in Settings → Apps,
  and in the menu and the welcome window once there are eight media players
  or more (not counting suggested web apps). Settings → General shows every
  player's tile on a page that scrolls, without one.
  - A search matches anywhere in a name, ignoring case and accents
    (`localizedStandardContains`).
  - Results keep the list's order.
  - The window keeps its height while you type.
  - With no match, the list says so in its own words: "No apps match “…”."
  - A search starts empty again when its window or menu opens again.
- **Empty lists** say why they're empty and what fills them: "Apps appear
  here once they have played audio."
- **Removing from a list** (Settings → Apps): a click on a row, anywhere but
  its switch, selects it, behind a `.selectedRowFill` rounded rectangle; a
  second click deselects it. **Remove** sits in the bottom bar after the
  button that adds, disabled while nothing is selected. Removing something
  whose loss changes what AutoHush does (an app turned off would pause the
  player again) asks first, as **Reset List…** does; one that changes nothing
  goes at once. The row's right-click menu offers the same (**Remove from
  List**), and VoiceOver gets it as an action.

## Writing

### Capitalization

| Title case | Sentence case |
|---|---|
| Window titles, page names | Row titles and switch labels: "Launch at login", "Pause playback after" |
| Buttons and menu items: "Check Now", "Ignore Another App…" | Lead-ins that read into their control: "Turn off for", "Sort by", "When an update is found" |
| Pop-up items: "Last Played" | Choice chips: "Notify me", "Install it automatically" |
| Section headings: "Pauses Playback", "Playing Now", "Apps with Sound" | Descriptions, notes and status lines |
| Alert titles: "Couldn't Install the Update" | Tooltips and VoiceOver labels: "Search by name", "Reverse order" |

- **Title case** follows Apple's rules: capitalize every word except
  articles, and conjunctions and prepositions of four letters or fewer.
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
  AutoHush does to that app ("Pauses your player", "Ignored — your player
  keeps playing"); **what's playing** describes the content, naming the
  media where it says what AutoHush does ("Pauses what's playing (music,
  podcasts or videos)…"). The feature is just **Auto-Pause**. "Music" stays
  only in names (Apple Music, YouTube Music).
- **Permissions:** you "allow" them, never "grant" them. Use the names macOS
  gives them: Automation, Accessibility, Audio Recording.
- **Contractions:** use them: couldn't, can't, isn't, it's, don't. Never
  "could not".
- **Ellipsis** (`…`, a single character) ends a button or menu item that
  asks for something more before it acts (a panel, a dialog, another
  window), and a state in progress ("Checking…"). A button that acts at once
  has none.
- **Em dash with spaces** joins a state and its reason: "Paused — Safari is
  playing", "Ignored — your player keeps playing".
- **Quotation marks** are curly in English (“ ”). Each language uses its own
  («  », „ “, 「 」).
- **Periods** end full sentences: descriptions and notes. Fragments have
  none: subtitles ("Pauses your player"), status lines, labels and buttons.
- **Numbers** are digits, with units in the user's format: "0.5 s",
  "−60 dB", "5 min".

## Translations

AutoHush is translated into 34 languages besides English. The README's
[Translations](README.md#translations) section explains how; for style:

- **Every change translates every language.** A new or changed English
  string is translated into all 34 before the change is done.
- **The comment says where.** Every string has a comment that says where it
  appears and what each placeholder holds.
- **A changed English string is a new key.** Carry its translations over,
  update them, and delete the old key.
- **A bottom bar's buttons stay on one line** (`.fixedSize()`). When a
  translation makes them wider than the window, that translation is
  shortened, keeping its meaning (in Settings → Apps: Russian "Сбросить…",
  Greek "Παράβλεψη εφαρμογής…", Hungarian "Lista visszaállítása…"). Check
  by rendering the window in every language.
- **Short slots stay short.** Measured at the windows' sizes: a Settings
  page's name in the sidebar has about 134 pt at 16 pt (about 16
  characters: German "Ein-/Ausblenden", not "Ein- und Ausblenden"), and the
  line under a player's name in a chip (`PlayerTiles`) about 88 pt at
  11 pt (about 12 characters: "Click to add" is "Añadir", "Hinzufügen").
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
  - Catalan puts the article before AutoHush ("l'AutoHush"), but not before
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
- **Decorative images** (app icons beside their names, symbols beside text)
  are hidden from VoiceOver.
- **Switches** read as switches, with their row's title (`PillToggleStyle`
  does this).
- **Chosen items** carry the "selected" trait.
- **Checklist steps** (adding a web app, learning a player) are one
  VoiceOver element each: the step's words and caption as its label, then
  where it stands as its value, "Completed", "In progress", "To do" or
  "Failed"
  (`checklistStepAccessibility`), never the "selected" trait. (Combined
  text keeps its words in its value: a value of its own would replace them.) A window's
  checklist announces the step to do now each time it changes
  (`announcesCurrentStep`).
- **Contrast:** text in light mode keeps at least 4.5:1.

## Keyboard

AutoHush has **no keyboard shortcuts of its own, and all of Apple's
standard ones**:
- **The menu bar** (`MainMenu`), while a window is open: the AutoHush menu
  (About, Settings… ⌘,, Services, Hide ⌘H, Hide Others ⌥⌘H, Show All,
  Quit ⌘Q), Edit (Undo ⌘Z, Redo ⇧⌘Z, Cut ⌘X, Copy ⌘C, Paste ⌘V, Delete,
  Select All ⌘A) and Window (Close ⌘W, Minimize ⌘M, Zoom, Bring All to
  Front), in macOS's own words in every language. The Edit menu is what
  makes text fields take ⌘V and the rest.
- **Return** presses a window's main, blue button (`.keyboardShortcut(.defaultAction)`:
  Continue, Done) and an alert's first one; in Add a Web App's address
  field it's Continue. A search field keeps Return from the window's
  button (SwiftUI gives it to the focused field): with nothing typed it's
  the main button (Continue); with a search, it picks the one item the
  search narrowed down to (the welcome window's players), if just one;
  items that share a name count as one (the Spotify app and the suggested
  Spotify web app: the app).
  **Escape** presses Cancel or Later
  (`.cancelAction`, or `keyEquivalent = "\u{1b}"` on an alert's Later).
- **Never a shortcut Apple doesn't define**, and none on the status menu's
  rows. ⌥-clicking Settings in the menu opens Diagnostics.

A field in the open status menu needs AppKit to give it the keyboard (see
`StatusMenuController`).

## Checking a change

Before a visible change is final:

1. **Propose it with pictures** of the real screens, before and after.
2. **Look at it:**
   - in **light and dark mode**;
   - in **English and German** (German is the longest), and in **Arabic**
     when the layout changes;
   - with **short and long lists** where lists are involved.
3. **Check the text** against the rules above, and translate it.
4. **Update this guide** when the change adds or changes a pattern.
