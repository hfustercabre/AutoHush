import Foundation
import Testing
@testable import PlayerCheckKit
import CheckedPlayers

/// Why an app can be in Now Playing, as the helper writes it, is read back the same.
@Suite("NowPlayingReasonsLine")
struct NowPlayingReasonsLineTests {
    @Test("why an app can be in Now Playing: its reason, the interface a switch shows, the switches, the interface's kind, a web app's browser; each empty when none")
    func nowPlayingReasons() {
        let electron = NowPlayingReasonsLine(path: "/Applications/Discs.app", reason: "MediaPlayer, through Electron",
                                             interface: "Electron 38.4.0", switches: "Electron's switch", kind: .electron)
        #expect(NowPlayingReasonsLine(line: electron.line) == electron)
        let webApp = NowPlayingReasonsLine(path: "/Users/someone/Applications/Chrome Apps.localized/Music.app",
                                           reason: "Chromium, as a Google Chrome web app", interface: "Google Chrome web app",
                                           switches: "Google Chrome's VoiceOver switch", kind: .chromiumWebApp, browser: "Google Chrome")
        #expect(NowPlayingReasonsLine(line: webApp.line) == webApp)
        let none = NowPlayingReasonsLine(path: "/Applications/Notes.app", reason: nil)
        #expect(none.line == "/Applications/Notes.app\t\t\t\t\t")
        #expect(NowPlayingReasonsLine(line: none.line) == none)
        #expect(NowPlayingReasonsLine(line: "") == nil)
    }
}
