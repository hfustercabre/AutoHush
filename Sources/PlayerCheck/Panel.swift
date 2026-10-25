import AppKit
import AutoHushKit
import CheckedPlayers
import PlayerCheckKit
import ScriptablePlayers
import WebAppPlayers

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

/// Where the Now Playing setting to put back is kept while a press shows it
/// (`NowPlayingSetting`): inside an AutoHush app (…/AutoHush.app/Contents/
/// Helpers/playercheck; a test copy has a bundle ID of its own), that app's
/// defaults, so its next start puts back what a check that died left;
/// elsewhere (the Player Check app, a build's folder) this tool's own.
var nowPlayingRecord: UserDefaults { hostAppID.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

/// The bundle ID of the app this tool is the helper of, when it's not this
/// tool's own bundle already (whose defaults are the standard ones).
let hostAppID: String? = {
    let helpers = URL(fileURLWithPath: executablePath(of: getpid()) ?? CommandLine.arguments[0]).deletingLastPathComponent()
    let contents = helpers.deletingLastPathComponent(), app = contents.deletingLastPathComponent()
    guard helpers.lastPathComponent == "Helpers", contents.lastPathComponent == "Contents", app.pathExtension == "app",
          let id = Bundle(url: app)?.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return nil }
    return id
}()

/// Whether the panel's item was in the menu bar at a press, and whether it
/// was missing at one: never there, Now Playing is hidden in the menu bar
/// (hidden in System Settings, macOS removes it), which `writeResult` says.
@MainActor var panelItemSeen = false
@MainActor var panelItemMissing = false
/// The app's row showed a state its sound didn't (one app's always shows
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
/// a web app's window may keep a generic title), each element read waiting
/// 0.5 s, as the page's are; none without a page or a bar.
@MainActor func playerBarTexts(_ pid: pid_t) -> [String] {
    guard page?.toggle != nil, pageToggleLabel(pid) != nil, let toggle = barToggle, let bar = playerBar(of: toggle) else { return [] }
    var texts: [String] = [], reads = 500
    func read(_ element: AXUIElement, depth: Int) {
        guard reads > 0 else { return }
        reads -= 1
        texts += [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].map { element.text($0) }.filter { !$0.isEmpty }
        if depth < 8 { element.children(timeout: AccessibilityWebPage.timeout).forEach { read($0, depth: depth + 1) } }
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
    guard let panelRowText, keptPanelRow() != panelRowText else { return }
    saveButton { $0.panelRow = panelRowText }
}

/// The row it changed with before, kept between runs (`rememberPanelRow`).
func keptPanelRow() -> String? { savedButtons()[bundleID]?.panelRow }

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

/// What tells the app's row, read before the panel opens (and before a
/// hidden Now Playing is shown for it): what AutoHush reads
/// (`PanelWay.Shown`), with its song in its player bar and by AppleScript
/// too, and its level, which tells how it is when its row doesn't follow it.
struct PanelRead {
    var texts: SongTexts
    var otherApps: Set<String>
    /// Heard by its level; nil when not measured.
    var heard: Bool?
    /// Pausing, whether it holds Now Playing.
    var holdsNowPlaying: Bool

    /// Its level as `heard` says, when a trial just measured it, else
    /// measured now (half a second).
    @MainActor init(_ pid: pid_t, pausing: Bool, heard: Bool?) {
        texts = songTexts(pid)
        otherApps = otherAppNames()
        self.heard = heard ?? audible(pid)
        holdsNowPlaying = pausing && nowPlayingHolder(pid).isThisApp
    }

    /// Whether `row` shows the app's song or its name.
    @MainActor func showsApp(_ row: PanelRow) -> Bool {
        !PanelRows.appRows([row], appName: appName, otherApps: otherApps, texts: texts.all).isEmpty
    }

    /// The app's row among the open panel's `rows`, as AutoHush's `PanelWay`
    /// takes it (`PanelRows.row`): showing Pause when `pausing`, Play
    /// otherwise, its song's or name's, else the one it changed with before
    /// (`remembered`), else, pausing, the only one playing while it holds Now
    /// Playing. `asToggle`: its own, whatever it shows.
    @MainActor func row(in rows: [PanelRow], pausing: Bool, remembered: String?, asToggle: Bool = false) -> PanelRow? {
        PanelRows.row(in: rows, pausing: pausing, appName: appName, otherApps: otherApps, texts: texts.all,
                      remembered: remembered, holdsNowPlaying: holdsNowPlaying, asToggle: asToggle)
    }

    /// Why `row` was taken as the app's, for the log (never its text).
    @MainActor func why(_ row: PanelRow, remembered: String?) -> String {
        if showsApp(row) { return rowFound(row, by: texts) }
        if row.text == remembered { return remembered == panelRowText ? "the row pressed before" : "the row it changed with before" }
        return "the only row playing, while it holds Now Playing"
    }
}

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

/// Which row to press: the app's (`PanelRead.row`), the row it changed
/// with before (kept between runs) as the one AutoHush remembers; the same
/// with the row pressed last as that one (a trial's play, after its pause
/// pressed it); or only the one pressed last (to put back a press that
/// changed it).
enum PanelRowChoice { case app, lastElseApp, lastOnly }

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

/// How a press by the panel went (`--via panel`).
enum PanelPress { case already, changed, pressed, notPressed }

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
    if !pageRead { _ = useRememberedBar(pid: pid) }
    var read = PanelRead(pid, pausing: pausing, heard: nil)
    let remembered = keptPanelRow()
    return withOpenPanel(failing: PanelPress.notPressed) { item, rows in
        var rows = rows
        var row = read.row(in: rows.map(\.row), pausing: pausing, remembered: remembered)
        var own = read.row(in: rows.map(\.row), pausing: pausing, remembered: remembered, asToggle: true)
        // None told by its song or by memory: its page's player bar may show its song.
        @MainActor func toldByIt(_ row: PanelRow) -> Bool { read.showsApp(row) || row.text == remembered }
        if own == nil, row.map({ toldByIt($0) }) != true, !pageRead, isWebApp || hiddenInterface != nil || hasWebPage(pid: pid) {
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
