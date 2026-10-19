import Foundation

/// Which of the panel's rows is an app's, as `PanelWay` and Player Check's
/// presses both tell it (a check passes a row only by AutoHush's rule): the
/// one showing its song, found whole in what the app shows (its windows'
/// titles, what it plays by AppleScript, its page's player bar) or, with no
/// song, its name; else the row it changed with before; else, pausing, the
/// only row playing while the app holds Now Playing. Never a row for a word
/// in common (a paused Deezer's "Another One Bites The Dust" was taken for
/// SoundCloud's for its "the").
package enum PanelRows {
    /// A text in lowercase, its letters and digits only, one space between
    /// words: "Song (Edit) - Artist" and "song edit artist" compare.
    static func normalized(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// What a row's song can be: its text up to each ", " ahead of
    /// " – <album>", since song and artist may both hold commas ("…(JAKE
    /// DILE REWORK), Jake Dile - Mixes, Bootlegs, Mashups – "); the whole
    /// text without one ("QuickTime Player"). A session with no song shows
    /// its app's name ("TIDAL,  – ").
    static func songs(ofRow text: String) -> [String] {
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
        let others = otherApps.filter { normalized($0) != own }
        return rows.filter { showsName($0, appName: appName) || showsSong($0, in: texts, otherApps: others) }
    }

    /// Whether `row` shows the app by its name (a session with no song).
    package static func showsName(_ row: PanelRow, appName: String) -> Bool {
        songs(ofRow: row.text).map(normalized).contains(normalized(appName))
    }

    /// Whether one of `texts` holds `row`'s song whole (three letters or
    /// more, and not one of `otherApps`' names): which of the app's texts
    /// told its row, for a log that names neither.
    package static func showsSong(_ row: PanelRow, in texts: [String], otherApps: Set<String>) -> Bool {
        let others = Set(otherApps.map(normalized))
        let haystack = texts.map { " \(normalized($0)) " }
        return songs(ofRow: row.text).map(normalized).contains { shown in
            shown.count >= 3 && !others.contains(shown) && haystack.contains { $0.contains(" \(shown) ") }
        }
    }

    /// The row to press for the app, showing Pause when `pausing`, else
    /// Play: its song's or name's; else the one it changed with before,
    /// `remembered`; else, pausing, the only one playing when the app holds
    /// Now Playing. `asToggle`: whatever it shows, for a row that doesn't
    /// follow the app (`PlayerSetup.panelRowIsStale`), its song's, name's or
    /// remembered only. `nil` when that's not one row.
    package static func row(in rows: [PanelRow], pausing: Bool, appName: String, otherApps: Set<String>, texts: [String],
                            remembered: String?, holdsNowPlaying: Bool, asToggle: Bool = false) -> PanelRow? {
        let candidates = asToggle ? rows : rows.filter { $0.playing == pausing }
        let mine = appRows(candidates, appName: appName, otherApps: otherApps, texts: texts)
        if mine.count == 1 { return mine[0] }
        guard mine.isEmpty else { return nil }
        if let remembered {
            let same = candidates.filter { $0.text == remembered }
            if same.count == 1 { return same[0] }
        }
        return !asToggle && pausing && holdsNowPlaying && candidates.count == 1 ? candidates[0] : nil
    }

    /// The app's own row when it doesn't follow the app: its sound says the
    /// app isn't as wanted yet (heard while `pausing`, silent while playing
    /// it), so the row is pressed as a toggle, as AutoHush presses such a row
    /// (`PlayerSetup.panelRowIsStale`). `nil` otherwise, or unmeasured.
    package static func staleRow(in rows: [PanelRow], pausing: Bool, heard: Bool?, appName: String, otherApps: Set<String>,
                                 texts: [String], remembered: String?) -> PanelRow? {
        guard heard == pausing else { return nil }
        return row(in: rows, pausing: pausing, appName: appName, otherApps: otherApps, texts: texts,
                   remembered: remembered, holdsNowPlaying: false, asToggle: true)
    }
}
