import AppKit

// MARK: - The menu bar's Now Playing panel

let notNowPlaying = "nothing in it reports to Now Playing, so the Now Playing panel can't reach it"
let panelNotNowPlaying = "nothing in it reports to Now Playing, so it has no row in the panel"
/// Why the panel's item in the menu bar wasn't found: it's found and pressed
/// through Accessibility, so without that permission, that's why.
var noPanelItem: String {
    AXIsProcessTrusted()
        ? "no Now Playing item in the menu bar (it shows once something has played, unless System Settings → Control Center hides it)"
        : "this tool (or the app running it) needs the Accessibility permission: the panel is found and pressed through it"
}

/// One app's row in the menu bar's Now Playing panel (Control Center's): its
/// text ("Song, Artist – Album", or the app's name) and its Play/Pause.
struct PanelRow {
    let text: String
    let button: AXUIElement
    /// Read while the panel is open: its elements answer nothing once it closes.
    let playing: Bool
}

/// The menu bar's Now Playing item (macOS 26 on), found by hit-testing along
/// the menu bar: the menu bar's own list doesn't name it.
@MainActor func nowPlayingMenuItem() -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    // The primary display's: hit-test coordinates start at its top left, and
    // NSScreen.main is the one with the keyboard focus, maybe another.
    let width = Float(NSScreen.screens.first?.frame.width ?? 1470)
    var x = width - 20
    while x > width / 3 {
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(system, x, 12, &hit) == .success, let hit,
           hit.text(kAXIdentifierAttribute) == "com.apple.menuextra.now-playing" { return hit }
        x -= 6
    }
    return nil
}

/// The open panel's rows, from Control Center's windows; none while it's closed.
func panelRows() -> [PanelRow] {
    guard let center = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else { return [] }
    var found: [PanelRow] = []
    func walk(_ element: AXUIElement, _ depth: Int) {
        guard depth < 20 else { return }
        let children = element.children
        if let button = children.first(where: { ["play.fill", "pause.fill"].contains($0.text(kAXIdentifierAttribute)) }) {
            let text = children.map { $0.text(kAXValueAttribute) }.filter { !$0.isEmpty }.joined(separator: " ")
            found.append(PanelRow(text: text, button: button, playing: button.text(kAXIdentifierAttribute) == "pause.fill"))
            return
        }
        children.forEach { walk($0, depth + 1) }
    }
    for window in AXUIElementCreateApplication(center.processIdentifier).value(kAXWindowsAttribute) as? [AXUIElement] ?? [] {
        walk(window, 0)
    }
    return found
}

/// Opens the panel with its menu bar item and waits up to 2 s for its
/// rows; nil when the item didn't open. It shows under the menu bar, and
/// takes the keyboard while it's open.
func openPanel(_ item: AXUIElement) -> [PanelRow]? {
    guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else { return nil }
    var rows: [PanelRow] = []
    let deadline = Date().addingTimeInterval(2)
    while rows.isEmpty, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
        rows = panelRows()
    }
    return rows
}

/// Closes it, waiting up to 2 s for its rows to go.
func closePanel(_ item: AXUIElement) {
    _ = AXUIElementPerformAction(item, kAXPressAction as CFString)
    let deadline = Date().addingTimeInterval(2)
    while !panelRows().isEmpty, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
}

/// A text in lowercase, its letters and digits only, one space between
/// words: so "Song (Edit) - Artist" and "song edit artist" compare.
func normalized(_ text: String) -> String {
    text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
}

/// What a row's song can be: its text up to each ", " ahead of " – <album>",
/// since the song and the artist may both hold commas ("…(JAKE DILE
/// REWORK), Jake Dile - Mixes, Bootlegs, Mashups – "); the whole text
/// without one ("QuickTime Player"). A session with no song shows its app's
/// name ("TIDAL,  – ").
func songs(ofRow text: String) -> [String] {
    let end = text.range(of: " –", options: .backwards)?.lowerBound ?? text.endIndex
    var songs: [String] = [], from = text.startIndex
    while let comma = text.range(of: ", ", range: from..<end) {
        songs.append(String(text[..<comma.lowerBound]))
        from = comma.upperBound
    }
    return songs.isEmpty ? [text] : songs
}

/// The texts of the page's player bar (the song and the artist, where
/// SoundCloud's window keeps a generic title); none without a page or a bar.
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
/// its AppleScript current track or item show it: what tells its row.
@MainActor func songTexts(_ pid: pid_t) -> [String] {
    var texts = appWindows(of: pid).windows.map(\.title) + playerBarTexts(pid)
    if let song = scriptedSong() { texts.append(song) }
    return texts
}

/// The rows that show what the app plays: their song found whole in
/// `texts` (its windows' titles, its player bar, its current track), or,
/// with no song, its name. A row isn't taken for a word in common: a paused
/// Deezer's "Another One Bites The Dust" was pressed for SoundCloud for its
/// "the".
@MainActor func appRows(_ rows: [PanelRow], texts: [String]) -> [PanelRow] {
    let own = normalized(appName)
    // A session with no song shows its app's name: another app's.
    let others = Set(NSWorkspace.shared.runningApplications.compactMap { $0.localizedName.map(normalized) }).subtracting([own])
    let haystack = texts.map { " \(normalized($0)) " }
    return rows.filter { row in
        songs(ofRow: row.text).map(normalized).contains { shown in
            if shown == own { return true }
            guard shown.count >= 3, !others.contains(shown) else { return false }
            return haystack.contains { $0.contains(" \(shown) ") }
        }
    }
}

/// The row pressed last, to find it again; why the panel couldn't be used.
@MainActor var panelRowText: String?
@MainActor var panelProblem: String?

/// Keeps the row just pressed as the app's, between runs, once the app
/// changed with it: a later press finds it by its text when nothing shows
/// the app's song (a Play after a Pause, as a check's play does within one
/// run; VLC's window on another desktop gives no title).
@MainActor func rememberPanelRow() {
    guard let panelRowText, savedButtons()[bundleID]?.panelRow != panelRowText else { return }
    saveButton { $0.panelRow = panelRowText }
}

/// The one row whose text is the app's remembered row's, if exactly one is.
func rememberedRow(_ rows: [PanelRow]) -> PanelRow? {
    guard let text = savedButtons()[bundleID]?.panelRow else { return nil }
    let same = rows.filter { $0.text == text }
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
    // Read before the panel opens: a page takes a moment.
    let texts = choice == .lastOnly ? [] : songTexts(pid)
    let holdsNowPlaying = choice != .lastOnly && pausing && nowPlayingHolder(pid).isThisApp
    guard let item = nowPlayingMenuItem() else {
        panelProblem = noPanelItem
        return false
    }
    guard let rows = openPanel(item) else {
        panelProblem = "the Now Playing item didn't open"
        return false
    }
    let candidates = rows.filter { $0.playing == pausing }
    var row = choice == .app ? nil : candidates.first { $0.text == panelRowText }
    var mine: [PanelRow] = []
    if row == nil, choice != .lastOnly {
        mine = appRows(candidates, texts: texts)
        // Its song first; else the row it changed with before; else, pausing, the only one playing.
        row = mine.count == 1 ? mine[0] : !mine.isEmpty ? nil
            : rememberedRow(candidates) ?? (holdsNowPlaying && candidates.count == 1 ? candidates[0] : nil)
    }
    guard let row else {
        let state = pausing ? "Pause" : "Play"
        panelProblem = rows.isEmpty ? "the panel showed no rows"
            : choice == .lastOnly ? "the row pressed before (“\(panelRowText ?? "")”) no longer shows \(state)"
            : noRowProblem(rows: candidates.count, mine: mine.count, showing: state)
        closePanel(item)
        return false
    }
    panelRowText = row.text
    let pressed = AXUIElementPerformAction(row.button, kAXPressAction as CFString) == .success
    closePanel(item)
    return pressed
}

/// How a press by the panel went (`--via panel`).
enum PanelPress { case already, changed, pressed, notPressed }

/// A press by the panel (`--via panel`). The app's row is found by its song
/// in its windows' titles or what it plays by AppleScript (Deezer's title,
/// Spotify's current track and VLC's current item name it), else as the row
/// it changed with before (`rememberedRow`); only when none matches is its
/// page read, for its player bar's song (SoundCloud's title doesn't name
/// it), since reading a page can take seconds (Deezer's is built anew each
/// time). The row's own Play/Pause, as Now Playing knows the app, tells
/// whether it's that way already, and shows the press take before the panel
/// closes (2 s at most). A row told only by memory, or only by the app
/// holding Now Playing, may be another app's showing the same: it's pressed
/// as `.pressed`, so the app itself shows whether it changed.
@MainActor func panelPress(pid: pid_t, pausing: Bool) -> PanelPress {
    // Its one line comes after: what it reads meanwhile isn't said.
    let wasQuiet = quiet
    quiet = true
    defer { quiet = wasQuiet }
    // The remembered player bar, when it's there, costs a few reads.
    if !pageRead { _ = useRememberedBar(pid: pid) }
    var texts = songTexts(pid)
    guard let item = nowPlayingMenuItem() else {
        panelProblem = noPanelItem
        return .notPressed
    }
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
        texts += playerBarTexts(pid)
        guard let again = openPanel(item) else {
            panelProblem = "the Now Playing item didn't open"
            return .notPressed
        }
        rows = again
        mine = appRows(rows, texts: texts)
    }
    if mine.count == 1 {
        let row = mine[0]
        panelRowText = row.text
        if row.playing != pausing {
            closePanel(item)
            // A remembered row that's that way already may be another app's:
            // the app itself must be so too.
            guard byMemory, isPlaying(pid) == pausing else { return .already }
            panelProblem = "the row it changed with before (“\(row.text)”) shows another app's song now"
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
            changed = panelRows().first { $0.text == row.text }?.playing == !pausing
        }
        closePanel(item)
        return changed && !byMemory ? .changed : .pressed
    }
    let candidates = rows.filter { $0.playing == pausing }
    if mine.isEmpty, pausing, candidates.count == 1, nowPlayingHolder(pid).isThisApp {
        panelRowText = candidates[0].text
        let pressed = AXUIElementPerformAction(candidates[0].button, kAXPressAction as CFString) == .success
        closePanel(item)
        return pressed ? .pressed : .notPressed
    }
    closePanel(item)
    panelProblem = noRowProblem(rows: rows.count, mine: mine.count)
    return .notPressed
}
