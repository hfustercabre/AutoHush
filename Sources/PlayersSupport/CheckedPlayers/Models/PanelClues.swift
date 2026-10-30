import Foundation
import ScriptablePlayers
import WebAppPlayers

/// What shows the song an app plays besides its windows' titles, as its check
/// found it: its page's player bar and what it plays by AppleScript. The
/// check tells the app's row in the Now Playing panel by all three, so
/// `PanelWay` reads the same in use, and a panel way the check approved
/// finds its row there too (2026-10-19). Kept in the setup with the panel
/// (`PlayerSetup.panelClues`).
package struct PanelClues: Codable, Equatable, Sendable {
    /// The page whose player bar names the song: how it shows
    /// (`PageAccess`), and its Play/Pause's words, by which its bar is found.
    package struct Page: Codable, Equatable, Sendable {
        var access: PageAccess
        var labels: [String]

        package init(access: PageAccess, labels: [String]) {
            self.access = access
            self.labels = labels
        }
    }

    var page: Page?
    var script: ScriptedSong?

    /// `nil` when neither is there.
    package init?(page: Page?, script: ScriptedSong?) {
        guard page != nil || script != nil else { return nil }
        self.page = page
        self.script = script
    }
}
