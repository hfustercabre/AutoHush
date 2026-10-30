import AppKit
import AutoHushKit
import CheckedPlayers
import PlayerCheckKit
import ScriptablePlayers
import WebAppPlayers

// MARK: - Pressing its rows, as AutoHush presses them

/// A row that doesn't follow the app (`PanelRows.staleRow`), pressed as a
/// toggle, and kept so (`panelRowStale`).
@MainActor func staleRow(in rows: [PanelRow], pausing: Bool, read: PanelRead, remembered: String?) -> PanelRow? {
    guard let own = PanelRows.staleRow(in: rows, pausing: pausing, heard: read.heard, appName: appName, otherApps: read.otherApps,
                                       texts: read.texts.all, remembered: remembered) else { return nil }
    log("    its row shows \(pausing ? "Play" : "Pause") while it's \(pausing ? "heard" : "silent"): pressed as a toggle")
    panelRowStale = true
    return own
}

/// Presses `row`'s Play/Pause in the open panel, taken as the one pressed
/// (`notePanelRow`); whether it took.
@MainActor func pressRow(_ row: PanelRow, in rows: [ShownRow], why: String) -> Bool {
    guard let index = rows.firstIndex(where: { $0.row == row }) else { return false }
    notePanelRow(row, index, of: rows.count, why: why)
    return AXUIElementPerformAction(rows[index].button, kAXPressAction as CFString) == .success
}

/// Opens the panel, presses the Play/Pause of a row (the row shows Pause
/// when `pausing`, Play otherwise) and closes it; true once pressed. The
/// rows don't name their apps (only an icon shows it), so the app's row is
/// taken as AutoHush takes it (`PanelRead.row`), else a row that doesn't
/// follow it (`staleRow`), its level as `heard` says when the trial just
/// measured it. Nothing is pressed when that's not one row. In a trial, the
/// app's own signs judge whether the row was its own.
@MainActor func pressInPanel(pid: pid_t, pausing: Bool, choice: PanelRowChoice = .app, heard: Bool? = nil) -> Bool {
    // Read before the panel opens: a page takes a moment, its level half a second.
    let read = choice == .lastOnly ? nil : PanelRead(pid, pausing: pausing, heard: heard)
    let remembered = choice == .lastElseApp ? panelRowText ?? keptPanelRow() : keptPanelRow()
    return withOpenPanel(failing: false) { item, rows in
        defer { closePanel(item) }
        let shown = rows.map(\.row)
        let state = pausing ? "Pause" : "Play"
        guard let read else {
            guard let row = shown.first(where: { $0.playing == pausing && $0.text == panelRowText }) else {
                panelProblem = rows.isEmpty ? "the panel showed no rows" : "the row pressed before (\(panelRowSaid ?? "")) no longer shows \(state)"
                return false
            }
            return pressRow(row, in: rows, why: "the row pressed before")
        }
        if let row = read.row(in: shown, pausing: pausing, remembered: remembered) {
            return pressRow(row, in: rows, why: read.why(row, remembered: remembered))
        }
        if let row = staleRow(in: shown, pausing: pausing, read: read, remembered: remembered) {
            return pressRow(row, in: rows, why: "its own row, which doesn't follow it")
        }
        let candidates = shown.filter { $0.playing == pausing }
        panelProblem = rows.isEmpty ? "the panel showed no rows"
            : noRowProblem(rows: candidates.count, mine: candidates.filter { read.showsApp($0) }.count, showing: state)
        return false
    }
}

/// Opens the Now Playing panel for a press, and runs `body` with its menu
/// bar item and its rows (`body` closes it); `failed` when the item isn't
/// found or doesn't open, `panelProblem` saying which. Hidden by the user,
/// Now Playing is shown for this press only, as AutoHush does (the user,
/// 2026-10-16), and the log says so.
@MainActor func withOpenPanel<T>(failing failed: T, _ body: (_ item: AXUIElement, _ rows: [ShownRow]) -> T) -> T {
    func open() -> T {
        guard let item = nowPlayingMenuItem() else {
            log("    no Now Playing item found; in front: \(WindowStates.frontName)")
            panelItemMissing = true
            panelProblem = noPanelItem
            return failed
        }
        panelItemSeen = true
        guard let rows = openPanel(item) else {
            panelProblem = "the Now Playing item didn't open"
            return failed
        }
        return body(item, rows)
    }
    if nowPlayingMenuItem() == nil, NowPlayingSetting.isHidden,
       let result = NowPlayingSetting.whileShown(defaults: nowPlayingRecord, until: { nowPlayingMenuItem() != nil }, open) {
        log("    Now Playing, hidden in the menu bar, shown for the press and hidden again")
        return result
    }
    return open()
}

/// A press by the panel (`--via panel`), its row taken as AutoHush takes it
/// (`PanelRead.row`), else a row that doesn't follow it (`staleRow`). Its
/// song is read from its windows' titles and what it plays by AppleScript
/// (a window's title, a current track or a current item may name it); only
/// when no row is its own is its page read, for its player bar's song (a
/// web app's title may not name it), since reading a page can take seconds
/// (an Electron app's may be built anew each time). Its own row showing the
/// other state tells it's that way already, unless its sound says
/// otherwise; a row found by its song shows the press take before the panel
/// closes (2 s at most). A row told only by memory, or only by the app
/// holding Now Playing, may be another app's showing the same: it's pressed
/// as `.pressed`, so the app itself shows whether it changed.
@MainActor func panelPress(pid: pid_t, pausing: Bool) -> PanelPress {
    // Its one line comes after: what it reads meanwhile isn't said.
    let wasQuiet = quiet
    quiet = true
    defer { quiet = wasQuiet }
    // The remembered player bar, when it's there, costs a few reads.
    if !PageState.read { _ = useRememberedBar(pid: pid) }
    var read = PanelRead(pid, pausing: pausing, heard: nil)
    let remembered = keptPanelRow()
    return withOpenPanel(failing: PanelPress.notPressed) { item, rows in
        var rows = rows
        var row = read.row(in: rows.map(\.row), pausing: pausing, remembered: remembered)
        var own = read.row(in: rows.map(\.row), pausing: pausing, remembered: remembered, asToggle: true)
        // None told by its song or by memory: its page's player bar may show its song.
        @MainActor func toldByIt(_ row: PanelRow) -> Bool { read.showsApp(row) || row.text == remembered }
        if own == nil, row.map({ toldByIt($0) }) != true, !PageState.read, isWebApp || hiddenInterface != nil || hasWebPage(pid: pid) {
            closePanel(item)
            readPage()
            read.texts.bar = playerBarTexts(pid)
            guard let again = openPanel(item) else {
                panelProblem = "the Now Playing item didn't open"
                return .notPressed
            }
            rows = again
            row = read.row(in: rows.map(\.row), pausing: pausing, remembered: remembered)
            own = read.row(in: rows.map(\.row), pausing: pausing, remembered: remembered, asToggle: true)
        }
        if row == nil, let own {
            if let stale = staleRow(in: rows.map(\.row), pausing: pausing, read: read, remembered: remembered) {
                let pressed = pressRow(stale, in: rows, why: "its own row, which doesn't follow it")
                closePanel(item)
                return pressed ? .pressed : .notPressed
            }
            notePanelRow(own, rows.firstIndex { $0.row == own } ?? 0, of: rows.count, why: read.why(own, remembered: remembered))
            closePanel(item)
            // A remembered row that's that way already may be another app's:
            // the app itself must be so too.
            guard !read.showsApp(own), isPlaying(pid) == pausing else { return .already }
            panelProblem = "the row it changed with before shows another app's song now"
            return .notPressed
        }
        guard let row else {
            closePanel(item)
            panelProblem = noRowProblem(rows: rows.count, mine: rows.filter { read.showsApp($0.row) }.count)
            return .notPressed
        }
        guard pressRow(row, in: rows, why: read.why(row, remembered: remembered)) else {
            closePanel(item)
            panelProblem = "its row's \(pausing ? "Pause" : "Play") didn't take the press"
            return .notPressed
        }
        // Told by its song, it shows the press take.
        guard read.showsApp(row) else {
            closePanel(item)
            return .pressed
        }
        let changed = Polling.wait(seconds: 2, every: 0.05, lookingFirst: false) {
            panelRows().first { $0.row.text == row.text }?.row.playing == !pausing
        }
        closePanel(item)
        return changed ? .changed : .pressed
    }
}
