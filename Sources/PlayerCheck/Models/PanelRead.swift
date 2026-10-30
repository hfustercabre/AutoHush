import CheckedPlayers
import Foundation

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
        holdsNowPlaying = pausing && isNowPlaying(pid)
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
