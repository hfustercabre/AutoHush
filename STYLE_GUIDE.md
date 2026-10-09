# AutoHush Style Guide

How AutoHush looks and reads, so every change fits in. It covers the menu, the
Settings window, the welcome window and every text the app shows. When
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
| Settings window | Every tab is **480 pt** wide, with **16 pt** margins. Cards are **8 pt** apart. |
| Settings tab height | A tab is as tall as its content. Apps grows with its list, from 440 pt up to Advanced's height. Diagnostics scrolls at a fixed height. |
| Scrolling tabs | The heading and its controls stay at the top, and the buttons stay at the bottom in a [`BottomBar`](#components); only the list between them scrolls. |
| Welcome window | **420 pt** wide, with **24 pt** margins. With eight players or more, the list scrolls at a fixed height (about six rows), so the window doesn't change size. |
| Menu | AutoHush's own rows are **345 pt** wide (`menuContentWidth`). Its sections ("Turn off for", "Playing Now") have **14 pt** side margins and **6 pt** above and below. The card at the top has **10 pt** of padding. The menu's own rows (players, Ignored Apps) are drawn by macOS, a point larger than its menu font. |
| About | Centered. Every gap between its parts shows **24 pt**. |
| Section headings | **4 pt** in from the card's edge, in line with its text, with **6 pt** above (none for the first one on a tab). |

## Text sizes

Use the `Font` tokens. Never set a text's size by hand.

| Token | Size | For |
|---|---|---|
| `appLargeTitle` | 24 bold | The app's name in About |
| `appTitle` | 18 bold | A window's title inside its content, e.g. "Choose Your Music Player" |
| `appBody` | 14 | Plain text and row titles (the default) |
| `appHeadline` | 14 bold | A card's title (the player's name in the menu), Diagnostics' headings |
| `appCallout` | 13 | Buttons, values, notes, search fields |
| `appSubheadline` | 12 | The status line under the menu card's title |
| `appCaption` | 11 | Descriptions under rows, section labels, captions |

- **Numbers that change** (levels, timings) use `.monospacedDigit()`, so they don't jitter.
- **Symbols** may have their own sizes. The ones in use:
  - the menu toolbar's symbols are 15 pt;
  - the card's chevron is 9 pt bold;
  - Diagnostics' fold chevron is 11 pt semibold;
  - the welcome window's pick circles are 18 pt;
  - the symbols on the welcome window's permission tiles are 14 pt semibold;
  - Diagnostics' status symbol is 28 pt.

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
| `.controlPermissionTile` / `.audioPermissionTile` | system green / purple | system green / purple | The square behind a permission's symbol (the welcome window) |
| `.onColorSymbol` | white | white | A symbol on a colored square or on the accent color (a permission's tile, the welcome window's pick circle) |

- **Problems** are orange with a warning triangle (`NoteLabel`), never red.
- **Disabled** controls show at 45% opacity. A control that's dimmed twice,
  inside a dimmed group, stays at 45%.
- **Settings that only matter while a switch is on** show only then, under
  it in the same card (the fades' lengths under "Fade the music"). What the
  user can't change at all, because of the chosen player, is dimmed
  instead, with a note saying why.

## Components

| Component | Use it for |
|---|---|
| `Card` | A group of related rows on a rounded, tinted background (corner 12, padding 12). Rows inside are 10 pt apart, with a `CardDivider` between rows that are separate items. |
| `SectionHeading` | The heading over a card in Settings, e.g. "Music". |
| `SectionLabel` | A small grey label: the menu's headings ("Playing Now") and lead-ins above a control ("When an update is found"). |
| `RowTitle` | A row's title, with an optional description under it. |
| `SwitchRow` + `PillToggleStyle` | An on/off setting: the title on the left, the switch on the right. Switches are 36 × 21 pt; in lists of apps, 30 × 18 pt. |
| `ChoiceChips` | One choice among two to four options, as chips. The chosen one is filled with the accent color. |
| `.chip` button | Actions: "Check Now", "Reset List…". Corner 8. |
| `ChipButtonStyle(filled: true)` | Chips in a row, such as the menu's durations ("5 min"). |
| `ChipButtonStyle()` | Rows and buttons that light up only under the pointer: the menu's toolbar, the welcome window's players, the player search's rows. |
| `ChipButtonStyle(cornerRadius: 6)` | Small buttons inside the menu card: the player button and Retry. |
| The card's status line with `info.circle` | When the music player couldn't be controlled ("Can't control TIDAL right now", "Couldn't pause — Safari is playing"), an `info.circle` in `.appSecondary` ends the line, kept with its last word by a no-break space; a click on the line closes the menu and opens an `InfoAlert`: what failed as its title ("Can't Control TIDAL"), the cause in words, then the log's English for a bug report. Diagnostics shows the same as "Last error". |
| `IconChipButton` | An action with only a symbol, beside a heading or a pop-up (22 × 20 pt, corner 6): the sort arrow, the magnifiers. |
| `HeadingBadge` | A word in an orange capsule after a heading or a name that qualifies it: "Experimental" after "Safari Web Apps", "Untested" after an untested web app. |
| `WebAppsHeading` | "Safari Web Apps", its "Experimental" badge and the note that every website works differently, over the web apps wherever players are offered. In menus and pop-ups it's a drawn row (`NSMenuItem.webAppsHeading`), since a section header can't show a badge. |
| Pop-ups | The system's pop-up (`NSPopUpButton` or a SwiftUI `Picker` with `.menu`), always **without a border**: `isBordered = false` or `.buttonStyle(.borderless)`. |
| `SearchField` | Every search. Its ✕ closes the search or, when the search can't close, clears it. |
| `NoteLabel` | A note with a symbol: `.warning` (orange triangle) or `.info` (grey "i"). |
| `.captionStyle()` | A description or note under a card or a control: small, grey, wrapping. |
| `BottomBar` | Buttons fixed at the foot of a scrolling tab, with a line above them only while content scrolls under them. |
| `SupportLine` | "Would you like to support me?" with its link, at the foot of General and About. |
| `LearningSteps` / `LearningSummary` | What the user does so AutoHush can learn a player (play it; AutoHush then pauses it), each step ticked in `.appSuccess` once seen. The step to do now is semibold. A step AutoHush does itself shows a spinner meanwhile; one it couldn't do gets an orange `xmark.circle.fill`, its reason as a `NoteLabel`, and two buttons side by side, the way forward in blue ("Try Again") and the other way grey ("Pause It Manually"), which adds the user's own step. A step's buttons stay on one line each: when two don't fit side by side (the menu, longer languages), they go one under the other. `LearningSummary` adds a headline and a caption: a card of its own under the menu's card, and a section under the player in Settings → General. |
| `CountdownBanner` | How long is left to do a step, as a whole sentence ("You have 0:45 to pause it and click It's Paused."): semibold `.appCallout` in `.appWarning` with a timer, on a `.warningBadgeFill` rounded line, above the step's button. |
| `PermissionButton` | The button that allows a missing permission, labeled for where it stands: "Open <player>" (Automation is asked only while the player runs), "Allow…" or the permission's "Allow … Access…" (macOS's prompt when it hasn't asked, else System Settings), "Reopen AutoHush" (Audio Recording switched on in System Settings). Nothing once it's allowed. `prominent` makes it the blue chip when it's the window's next step. |
| `WelcomePermissionsView` | The welcome window's second page: what the chosen player needs, a row each (a symbol on a colored square, `RowTitle`, then the `PermissionButton` or an "Allowed" check in `.appSuccess`), "Use AntiDot Mode Instead" under Audio Recording, Back and Done. |

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
| 24 pt | Settings lists: Apps, Diagnostics |
| 32 pt | The welcome window's players |
| 36 pt | The menu card's player |

**Marking the chosen item:**
- In a list that acts on a click, as menus and pop-ups do, the chosen item
  has a checkmark on the left.
- In the welcome window, where you pick and then press Continue, it's a
  filled circle on the right.

## Lists and searches

- **Order:** a list has an obvious order and keeps it. Settings → Apps lets
  you choose the order, and remembers it. Music players are listed by how
  many people use them, with those that aren't installed after them,
  dimmed, and marked "Not installed". Safari web apps come last, under the
  `WebAppsHeading` (with its "Experimental" badge and note): those of the
  tested sites by name, the tested sites not added yet, then any other web
  app by name, with an "Untested" `HeadingBadge` after its name (a
  `RowTitle` badge; in menus and pop-ups, `NSMenuItem.setTitle(_:badge:font:maxWidth:)`
  draws it into the title, cutting a long name short with "…" so the badge
  always shows). A tested site's web app is named as the site. They're in
  line with the rows' icons in menus and pop-ups and with the cards' text in
  the welcome window. A search keeps the heading only while a web app
  matches. The "Add a Web App" and learning windows show the same warning
  as a `NoteLabel` under their title. Suggested web apps (the tested sites
  not added yet) are marked
  "Not installed" like a missing app but not dimmed, with the
  `arrow.down.circle` symbol for an icon and no pick circle in the welcome
  window: a click opens "Add a Web App" filled in with the address.
  **Add a Web App…** (with `plus.circle`) comes last
  wherever players are offered: the menu's last row, the pop-up's last item
  after a separator, and a `.chip` under the welcome window's list. Once the
  chosen web app's controls are learned, **Learn Controls Again…** (with
  `arrow.clockwise`) comes just before it in the menu and the pop-up, with
  the web app's name as the item's subtitle: the menu's width can't take the
  name in the title in most languages. Settings → General then shows a
  **Controls** row with a **Learn Again** `.chip`.
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
    and buttons show wherever the steps do (the menu's card, Settings).
  - **A time limit** shows as a caption line that counts down ("Back to the
    first step in 0:45").
  - **A click that couldn't be taken** says why in a `NoteLabel` under that
    step, until the next click.
  - **A step only some cases need** ("Answer the site in Safari") shows only
    once it's needed, and stays ticked afterwards.
- **Searches** appear where a list can grow long: always in Settings → Apps,
  and wherever music players are offered once there are eight or more (not
  counting suggested web apps).
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
  music again) asks first, as **Reset List…** does; one that changes nothing
  goes at once. The row's right-click menu offers the same (**Remove from
  List**), and VoiceOver gets it as an action.

## Writing

### Capitalization

| Title case | Sentence case |
|---|---|
| Window titles, tab names | Row titles and switch labels: "Launch at login", "Pause music after" |
| Buttons and menu items: "Check Now", "Ignore Another App…" | Lead-ins that read into their control: "Turn off for", "Sort by", "When an update is found" |
| Pop-up items: "Last Played" | Choice chips: "Notify me", "Install it automatically" |
| Section headings: "Pauses Music", "Playing Now", "Apps with Sound" | Descriptions, notes and status lines |
| Alert titles: "Couldn't Install the Update" | Tooltips and VoiceOver labels: "Search by name", "Reverse order" |

- **Title case** follows Apple's rules: capitalize every word except
  articles, and conjunctions and prepositions of four letters or fewer.
- **Feature names** keep their capitals, even mid-sentence: **Auto-Pause**,
  **AntiDot mode**.

### Words and punctuation

- **Speak to the user** ("your music") and name AutoHush by its name
  ("AutoHush pauses it…"), not "the app".
- **Permissions:** you "allow" them, never "grant" them. Use the names macOS
  gives them: Automation, Accessibility, Audio Recording.
- **Contractions:** use them: couldn't, can't, isn't, it's, don't. Never
  "could not".
- **Ellipsis** (`…`, a single character) ends a button or menu item that
  asks for something more before it acts (a panel, a dialog, another
  window), and a state in progress ("Checking…"). A button that acts at once
  has none.
- **Em dash with spaces** joins a state and its reason: "Paused — Safari is
  playing", "Ignored — music keeps playing".
- **Quotation marks** are curly in English (“ ”). Each language uses its own
  («  », „ “, 「 」).
- **Periods** end full sentences: descriptions and notes. Fragments have
  none: subtitles ("Pauses your music"), status lines, labels and buttons.
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
- **Keep the menu card short.** The label under its switch shows whole and
  takes room from the status line beside it. So the feature's name stays
  short ("Autopauza", "Autopause"), and a status line fits in three lines
  ("Allow Automation access for Spotify" rather than a full sentence).
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
  (`announcesCurrentStep`); the menu and Settings, showing the same steps,
  don't, so nothing is said twice.
- **Contrast:** text in light mode keeps at least 4.5:1.

## Keyboard

AutoHush has **no keyboard shortcuts at all**:
- no key equivalents on menu items;
- no `.keyboardShortcut`;
- no default button that Return presses.

Alerts are shown with `runModalWithoutShortcuts()`. The one exception is
⌥-clicking Settings in the menu, which opens Diagnostics. Typing into a
search field is, of course, fine; a field in an open menu needs AppKit to
give it the keyboard (see `StatusMenuController`).

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
