import AppKit
import CheckedPlayers
import PlayerCheckKit

// MARK: - The menu bar's Now Playing panel, as AutoHush reads and presses it

let notNowPlaying = "nothing in it reports to Now Playing, so the Now Playing panel can't reach it"
let panelNotNowPlaying = "nothing in it reports to Now Playing, so it has no row in the panel"
/// Why the panel's item in the menu bar wasn't found: it's found and pressed
/// through Accessibility, so without that permission, that's why.
var noPanelItem: String {
    AXIsProcessTrusted()
        ? "no Now Playing item in the menu bar (it shows once something has played, unless \(nowPlayingSettings) hides it)"
        : "this tool (or the app running it) needs the Accessibility permission: the panel is found and pressed through it"
}

/// Where Now Playing is shown in the menu bar or hidden.
var nowPlayingSettings: String {
    if #available(macOS 26, *) { "System Settings → Menu Bar" } else { "System Settings → Control Center" }
}

/// Whether the panel's item was in the menu bar at a press, and whether it
/// was missing at one: never there, Now Playing is hidden in the menu bar
/// (hidden in System Settings, macOS removes it), which `writeResult` says.
@MainActor var panelItemSeen = false
@MainActor var panelItemMissing = false
/// The app's row showed a state its sound didn't (Qobuz's always shows
/// paused, 2026-10-16), and was pressed as a toggle: kept in its setup
/// (`PlayerSetup.panelRowIsStale`) when the panel worked.
@MainActor var panelRowStale = false

/// One app's row in the open panel, with its Play/Pause, as AutoHush reads
/// it (`AccessibilityNowPlayingPanel`): its text ("Song, Artist – Album", or
/// the app's name) and whether it plays, read while the panel is open (its
/// elements answer nothing once it closes).
typealias ShownRow = AccessibilityNowPlayingPanel.ShownRow

/// The menu bar's Now Playing item (macOS 26 on), found by hit-testing along
/// the menu bar: the menu bar's own list doesn't name it.
func nowPlayingMenuItem() -> AXUIElement? { AccessibilityNowPlayingPanel.menuItem() }

/// The open panel's rows; none while it's closed.
func panelRows() -> [ShownRow] { AccessibilityNowPlayingPanel.rows() }

/// Opens the panel and waits up to 2 s for its rows; nil when the item
/// didn't open. It shows under the menu bar, and takes the keyboard.
func openPanel(_ item: AXUIElement) -> [ShownRow]? { AccessibilityNowPlayingPanel.open(item) }

/// Closes it, waiting up to 2 s for its rows to go.
func closePanel(_ item: AXUIElement) { AccessibilityNowPlayingPanel.close(item) }

/// The texts of the page's player bar (the song and the artist, where
/// a web app's window may keep a generic title); none without a page or a bar.
@MainActor func playerBarTexts(_ pid: pid_t) -> [String] {
    guard page?.toggle != nil, pageToggleLabel(pid) != nil, let toggle = barToggle, let bar = playerBar(of: toggle) else { return [] }
    var texts: [String] = [], reads = 500
    func read(_ element: AXUIElement, depth: Int) {
        guard reads > 0 else { return }
        reads -= 1
        texts += [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].map { element.text($0) }.filter { !$0.isEmpty }
        if depth < 8 { element.children.forEach { read($0, depth: depth + 1) } }
    }
    read(bar, depth: 0)
    return texts
}

/// What the app plays, as its windows' titles, its page's player bar and
/// its AppleScript current track or item show it: what tells its row. Only
/// matched, never written in the log.
struct SongTexts {
    var titles: [String] = []
    var bar: [String] = []
    var track: [String] = []
    var all: [String] { titles + bar + track }
}

@MainActor func songTexts(_ pid: pid_t) -> SongTexts {
    SongTexts(titles: appWindows(of: pid).windows.map(\.title), bar: playerBarTexts(pid), track: scriptedSong().map { [$0] } ?? [])
}

/// The other running apps' names: a row naming one (a session with no song)
/// is that app's, not this one's song.
func otherAppNames() -> Set<String> { Set(NSWorkspace.shared.runningApplications.compactMap(\.localizedName)) }

/// The rows that show what the app plays, as AutoHush tells them
/// (`PanelRows.appRows`): their song found whole in `texts` (its windows'
/// titles, its player bar, its current track), or, with no song, its name.
/// A row isn't taken for a word in common: another app's paused "Another
/// One Bites The Dust" was pressed for a web app for its "the".
@MainActor func appRows(_ rows: [ShownRow], texts: SongTexts) -> [ShownRow] {
    let mine = PanelRows.appRows(rows.map(\.row), appName: appName, otherApps: otherAppNames(), texts: texts.all)
    return rows.filter { shown in mine.contains(shown.row) }
}

/// What told that `row` was the app's, for the log: where its song showed,
/// or its name. Never the row's text, nor the song.
@MainActor func rowFound(_ row: PanelRow, by texts: SongTexts) -> String {
    if PanelRows.showsName(row, appName: appName) { return "showing \(appName)'s name" }
    let others = otherAppNames().subtracting([appName])
    let sources = [("its windows' titles", texts.titles), ("its player bar", texts.bar), ("what it plays, by AppleScript", texts.track)]
    let found = sources.filter { PanelRows.showsSong(row, in: $0.1, otherApps: others) }.map(\.0)
    return "its song found in " + (found.isEmpty ? "what it shows" : found.joined(separator: " and "))
}

/// The row pressed last, to find it again (only matched, never logged), and
/// how the log names it (`PrivateText.row`); why the panel couldn't be used.
@MainActor var panelRowText: String?
@MainActor var panelRowSaid: String?
@MainActor var panelProblem: String?

/// Takes `row`, the `index`th of `count`, as the one pressed.
@MainActor func notePanelRow(_ row: PanelRow, _ index: Int, of count: Int, why: String) {
    panelRowText = row.text
    panelRowSaid = PrivateText.row(index, of: count, why: why)
}

/// Keeps the row just pressed as the app's, between runs, once the app
/// changed with it: a later press finds it by its text when nothing shows
/// the app's song (a Play after a Pause, as a check's play does within one
/// run; a window on another desktop may give no title).
@MainActor func rememberPanelRow() {
    guard let panelRowText, savedButtons()[bundleID]?.panelRow != panelRowText else { return }
    saveButton { $0.panelRow = panelRowText }
}

/// The one row whose text is the app's remembered row's, if exactly one is.
func rememberedRow(_ rows: [ShownRow]) -> ShownRow? {
    guard let text = savedButtons()[bundleID]?.panelRow else { return nil }
    let same = rows.filter { $0.row.text == text }
    return same.count == 1 ? same[0] : nil
}

/// Why no row could be taken as the app's: `rows` rows (those showing
/// `state`, Play or Pause, when it says), `mine` of them showing its song.
@MainActor func noRowProblem(rows: Int, mine: Int, showing state: String? = nil) -> String {
    let with = state.map { " with \($0)" } ?? ""
    if rows == 0, state == nil { return "the panel showed no rows" }
    if mine > 1 { return "\(mine) of the panel's rows\(with) show \(appName)'s song: which is its own can't be told" }
    return "none of the panel's \(rows) rows\(with) shows \(appName)'s song (read from "
        + (["its windows' titles"] + (page?.toggle != nil ? ["its player bar"] : [])
            + (scripting?.namesItsSong == true ? ["what it plays, by AppleScript"] : [])).joined(separator: " or ")
        + ") or its name; the rows don't name their apps"
}

/// Which row to press: the app's; the one pressed last, else the app's; or
/// only the one pressed last (to put back a press that changed it).
enum PanelRowChoice { case app, lastElseApp, lastOnly }

/// Opens the panel, presses the Play/Pause of a row (the row shows Pause
/// when `pausing`, Play otherwise) and closes it; true once pressed. The
/// rows don't name their apps (only an icon shows it), so the app's row is
/// the one showing its song (`appRows`); else the row it changed with before
/// (`rememberedRow`); while pausing, else the only row playing when the app
/// is the Now Playing one. Nothing is pressed when that's not one row. In a
/// trial, the app's own signs judge whether the row was its own.
@MainActor func pressInPanel(pid: pid_t, pausing: Bool, choice: PanelRowChoice = .app) -> Bool {
    // Hidden by the user: shown for this press only, as AutoHush does (the user, 2026-10-16).
    if nowPlayingMenuItem() == nil, NowPlayingSetting.isHidden,
       let pressed = NowPlayingSetting.whileShown(until: { nowPlayingMenuItem() != nil }, { pressInPanel(pid: pid, pausing: pausing, choice: choice) }) {
        log("    Now Playing, hidden in the menu bar, shown for the press and hidden again")
        return pressed
    }
    // Read before the panel opens: a page takes a moment.
    let texts = choice == .lastOnly ? SongTexts() : songTexts(pid)
    let holdsNowPlaying = choice != .lastOnly && pausing && nowPlayingHolder(pid).isThisApp
    guard let item = nowPlayingMenuItem() else {
        log("    no Now Playing item found; in front: \(WindowStates.frontName)")
        panelItemMissing = true
        panelProblem = noPanelItem
        return false
    }
    panelItemSeen = true
    guard let rows = openPanel(item) else {
        panelProblem = "the Now Playing item didn't open"
        return false
    }
    let candidates = rows.filter { $0.row.playing == pausing }
    var row = choice == .app ? nil : candidates.first { $0.row.text == panelRowText }
    var why = "the row pressed before"
    var mine: [ShownRow] = []
    if row == nil, choice != .lastOnly {
        mine = appRows(candidates, texts: texts)
        // Its song first; else the row it changed with before; else, pausing, the only one playing.
        if mine.count == 1 {
            row = mine[0]
            why = rowFound(mine[0].row, by: texts)
        } else if mine.isEmpty, let remembered = rememberedRow(candidates) {
            row = remembered
            why = "the row it changed with before"
        } else if mine.isEmpty, holdsNowPlaying, candidates.count == 1 {
            row = candidates[0]
            why = "the only row playing, while it holds Now Playing"
        }
    }
    if row == nil, choice != .lastOnly, mine.isEmpty {
        // Its own row showing the other state: when its sound says otherwise
        // (heard while it shows paused, silent while it shows playing), a
        // row that doesn't follow it, pressed as a toggle. Its level is read
        // with the panel closed (half a second).
        let shown = appRows(rows.filter { $0.row.playing != pausing }, texts: texts)
        if shown.count == 1 {
            closePanel(item)
            if audible(pid) == pausing, let again = openPanel(item) {
                defer { closePanel(item) }
                if let own = again.first(where: { $0.row.text == shown[0].row.text }) {
                    log("    its row shows \(pausing ? "Play" : "Pause") while it's \(pausing ? "heard" : "silent"): pressed as a toggle")
                    panelRowStale = true
                    notePanelRow(own.row, again.firstIndex { $0.row == own.row } ?? 0, of: again.count, why: "its own row, which doesn't follow it")
                    return AXUIElementPerformAction(own.button, kAXPressAction as CFString) == .success
                }
            }
            panelProblem = noRowProblem(rows: candidates.count, mine: 0, showing: pausing ? "Pause" : "Play")
            return false
        }
    }
    guard let row else {
        let state = pausing ? "Pause" : "Play"
        panelProblem = rows.isEmpty ? "the panel showed no rows"
            : choice == .lastOnly ? "the row pressed before (\(panelRowSaid ?? "")) no longer shows \(state)"
            : noRowProblem(rows: candidates.count, mine: mine.count, showing: state)
        closePanel(item)
        return false
    }
    notePanelRow(row.row, rows.firstIndex { $0.row == row.row } ?? 0, of: rows.count, why: why)
    let pressed = AXUIElementPerformAction(row.button, kAXPressAction as CFString) == .success
    closePanel(item)
    return pressed
}

/// How a press by the panel went (`--via panel`).
enum PanelPress { case already, changed, pressed, notPressed }

/// A press by the panel (`--via panel`). The app's row is found by its song
/// in its windows' titles or what it plays by AppleScript (a window's
/// title, a current track or a current item may name it), else as the row
/// it changed with before (`rememberedRow`); only when none matches is its
/// page read, for its player bar's song (a web app's title may not name
/// it), since reading a page can take seconds (an Electron app's may be
/// built anew each time). The row's own Play/Pause, as Now Playing knows the app, tells
/// whether it's that way already, and shows the press take before the panel
/// closes (2 s at most). A row told only by memory, or only by the app
/// holding Now Playing, may be another app's showing the same: it's pressed
/// as `.pressed`, so the app itself shows whether it changed.
@MainActor func panelPress(pid: pid_t, pausing: Bool) -> PanelPress {
    // Hidden by the user: shown for this press only.
    if nowPlayingMenuItem() == nil, NowPlayingSetting.isHidden,
       let press = NowPlayingSetting.whileShown(until: { nowPlayingMenuItem() != nil }, { panelPress(pid: pid, pausing: pausing) }) {
        return press
    }
    // Its one line comes after: what it reads meanwhile isn't said.
    let wasQuiet = quiet
    quiet = true
    defer { quiet = wasQuiet }
    // The remembered player bar, when it's there, costs a few reads.
    if !pageRead { _ = useRememberedBar(pid: pid) }
    var texts = songTexts(pid)
    guard let item = nowPlayingMenuItem() else {
        log("    no Now Playing item found; in front: \(WindowStates.frontName)")
        panelItemMissing = true
        panelProblem = noPanelItem
        return .notPressed
    }
    panelItemSeen = true
    guard var rows = openPanel(item) else {
        panelProblem = "the Now Playing item didn't open"
        return .notPressed
    }
    var mine = appRows(rows, texts: texts)
    var byMemory = false
    // Else the row it changed with before, before reading its page (seconds).
    if mine.isEmpty, let remembered = rememberedRow(rows) {
        mine = [remembered]
        byMemory = true
    }
    if mine.isEmpty, !pageRead, isWebApp || hiddenInterface != nil || hasWebPage(pid: pid) {
        closePanel(item)
        readPage()
        texts.bar = playerBarTexts(pid)
        guard let again = openPanel(item) else {
            panelProblem = "the Now Playing item didn't open"
            return .notPressed
        }
        rows = again
        mine = appRows(rows, texts: texts)
    }
    func index(of shown: ShownRow) -> Int { rows.firstIndex { $0.row == shown.row } ?? 0 }
    if mine.count == 1 {
        let row = mine[0]
        notePanelRow(row.row, index(of: row), of: rows.count, why: byMemory ? "the row it changed with before" : rowFound(row.row, by: texts))
        if row.row.playing != pausing {
            closePanel(item)
            // A remembered row that's that way already may be another app's:
            // the app itself must be so too.
            guard byMemory, isPlaying(pid) == pausing else { return .already }
            panelProblem = "the row it changed with before shows another app's song now"
            return .notPressed
        }
        guard AXUIElementPerformAction(row.button, kAXPressAction as CFString) == .success else {
            closePanel(item)
            panelProblem = "its row's \(pausing ? "Pause" : "Play") didn't take the press"
            return .notPressed
        }
        let deadline = Date().addingTimeInterval(2)
        var changed = false
        while !changed, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            changed = panelRows().first { $0.row.text == row.row.text }?.row.playing == !pausing
        }
        closePanel(item)
        return changed && !byMemory ? .changed : .pressed
    }
    let candidates = rows.filter { $0.row.playing == pausing }
    if mine.isEmpty, pausing, candidates.count == 1, nowPlayingHolder(pid).isThisApp {
        notePanelRow(candidates[0].row, index(of: candidates[0]), of: rows.count, why: "the only row playing, while it holds Now Playing")
        let pressed = AXUIElementPerformAction(candidates[0].button, kAXPressAction as CFString) == .success
        closePanel(item)
        return pressed ? .pressed : .notPressed
    }
    closePanel(item)
    panelProblem = noRowProblem(rows: rows.count, mine: mine.count)
    return .notPressed
}
