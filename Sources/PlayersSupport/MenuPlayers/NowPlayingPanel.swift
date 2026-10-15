import AppKit
import ApplicationServices
import AutoHushKit

/// One app's row in the menu bar's Now Playing panel (Control Center's): its
/// text ("Song, Artist – Album", or the app's name) and whether it plays.
/// The rows don't name their apps (only an icon shows it).
package struct PanelRow: Equatable, Sendable {
    package let text: String
    package let playing: Bool

    package init(text: String, playing: Bool) {
        self.text = text
        self.playing = playing
    }
}

/// The menu bar's Now Playing panel, opened, read and pressed through
/// Accessibility: the last way to pause or play an app nothing else
/// controls, since it opens on screen for about half a second and takes the
/// keyboard meanwhile (the user, 2026-10-15: only if nothing else works).
/// Calls block. A protocol, so tests can stand in for it.
package protocol NowPlayingPanel: Sendable {
    /// Opens the panel, then calls `pick` with its rows: the row it returns
    /// has its Play/Pause pressed. The panel is closed again either way.
    /// `nil` when the panel couldn't be opened; else whether a row was pressed.
    func pressRow(_ pick: ([PanelRow]) -> PanelRow?) -> Bool?
}

/// The real panel (macOS 26 on): its menu bar item found by hit-testing
/// along the menu bar, its rows read from Control Center's windows.
package struct AccessibilityNowPlayingPanel: NowPlayingPanel {
    package init() {}

    package func pressRow(_ pick: ([PanelRow]) -> PanelRow?) -> Bool? {
        guard let item = Self.menuItem(), AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else { return nil }
        defer { Self.close(item) }
        var rows: [(row: PanelRow, button: AXUIElement)] = []
        let deadline = Date().addingTimeInterval(2)
        while rows.isEmpty, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            rows = Self.rows()
        }
        guard let chosen = pick(rows.map(\.row)), let button = rows.first(where: { $0.row == chosen })?.button else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    /// The menu bar's Now Playing item: the menu bar's own list doesn't name
    /// it, so it's hit-tested along the primary display's menu bar.
    private static func menuItem() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        let width = Float(NSScreen.screens.first?.frame.width ?? 1470)
        var x = width - 20
        while x > width / 3 {
            var hit: AXUIElement?
            if AXUIElementCopyElementAtPosition(system, x, 12, &hit) == .success, let hit,
               hit.string(kAXIdentifierAttribute) == "com.apple.menuextra.now-playing" { return hit }
            x -= 6
        }
        return nil
    }

    /// The open panel's rows, with their Play/Pause; none while it's closed.
    private static func rows() -> [(row: PanelRow, button: AXUIElement)] {
        guard let center = NSRunningApplication.running("com.apple.controlcenter") else { return [] }
        var found: [(row: PanelRow, button: AXUIElement)] = []
        func walk(_ element: AXUIElement, _ depth: Int) {
            guard depth < 20 else { return }
            let children = element.children
            if let button = children.first(where: { ["play.fill", "pause.fill"].contains($0.string(kAXIdentifierAttribute)) }) {
                let text = children.compactMap { $0.string(kAXValueAttribute) }.filter { !$0.isEmpty }.joined(separator: " ")
                found.append((PanelRow(text: text, playing: button.string(kAXIdentifierAttribute) == "pause.fill"), button))
                return
            }
            children.forEach { walk($0, depth + 1) }
        }
        AXUIElementCreateApplication(center.processIdentifier).elements(kAXWindowsAttribute).forEach { walk($0, 0) }
        return found
    }

    /// Closes it, waiting up to 2 s for its rows to go.
    private static func close(_ item: AXUIElement) {
        _ = AXUIElementPerformAction(item, kAXPressAction as CFString)
        let deadline = Date().addingTimeInterval(2)
        while !rows().isEmpty, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    }
}

/// Which of the panel's rows is an app's, as Player Check tells it: the one
/// showing its song, found whole in what the app shows (its windows'
/// titles, what it plays by AppleScript, its page's player bar) or, with no
/// song, its name; else the row it changed with before; else, pausing, the
/// only row playing while the app holds Now Playing. Never a row for a word
/// in common (a paused Deezer's "Another One Bites The Dust" was taken for
/// SoundCloud's for its "the").
package enum PanelRows {
    /// A text in lowercase, its letters and digits only, one space between
    /// words: "Song (Edit) - Artist" and "song edit artist" compare.
    package static func normalized(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// What a row's song can be: its text up to each ", " ahead of
    /// " – <album>", since song and artist may both hold commas; the whole
    /// text without one ("QuickTime Player").
    package static func songs(ofRow text: String) -> [String] {
        let end = text.range(of: " –", options: .backwards)?.lowerBound ?? text.endIndex
        var songs: [String] = [], from = text.startIndex
        while let comma = text.range(of: ", ", range: from..<end) {
            songs.append(String(text[..<comma.lowerBound]))
            from = comma.upperBound
        }
        return songs.isEmpty ? [text] : songs
    }

    /// The rows showing the app's song (found whole in `texts`) or, with no
    /// song, its name `appName`; `otherApps`' names aren't the app's song.
    package static func appRows(_ rows: [PanelRow], appName: String, otherApps: Set<String>, texts: [String]) -> [PanelRow] {
        let own = normalized(appName)
        let others = Set(otherApps.map(normalized)).subtracting([own])
        let haystack = texts.map { " \(normalized($0)) " }
        return rows.filter { row in
            songs(ofRow: row.text).map(normalized).contains { shown in
                if shown == own { return true }
                guard shown.count >= 3, !others.contains(shown) else { return false }
                return haystack.contains { $0.contains(" \(shown) ") }
            }
        }
    }

    /// The row to press for the app, showing Pause when `pausing`, else
    /// Play: its song's or name's; else the one it changed with before,
    /// `remembered`; else, pausing, the only one playing when the app holds
    /// Now Playing. `nil` when that's not one row.
    package static func row(in rows: [PanelRow], pausing: Bool, appName: String, otherApps: Set<String>, texts: [String],
                            remembered: String?, holdsNowPlaying: Bool) -> PanelRow? {
        let candidates = rows.filter { $0.playing == pausing }
        let mine = appRows(candidates, appName: appName, otherApps: otherApps, texts: texts)
        if mine.count == 1 { return mine[0] }
        guard mine.isEmpty else { return nil }
        if let remembered {
            let same = candidates.filter { $0.text == remembered }
            if same.count == 1 { return same[0] }
        }
        return pausing && holdsNowPlaying && candidates.count == 1 ? candidates[0] : nil
    }
}
