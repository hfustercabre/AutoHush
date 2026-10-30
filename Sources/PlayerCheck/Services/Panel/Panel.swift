import AppKit
import AutoHushKit
import CheckedPlayers
import PlayerCheckKit
import ScriptablePlayers
import WebAppPlayers

// MARK: - The menu bar's Now Playing panel, as AutoHush reads it

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

/// Its `SongTexts`, read now.
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
