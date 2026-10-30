import Foundation
import Testing
@testable import PlayerCheckKit
import CheckedPlayers

/// Each answer as the helper writes it is read back the same by whoever ran it.
@Suite("CheckAnswers")
struct CheckAnswersTests {
    @Test("the Now Playing list: each app's line, then the active one's process")
    func nowPlayingList() {
        let app = NowPlayingListLine(bundleID: "com.example.player", pid: 412, state: NowPlayingListLine.playing, isActive: true, name: "Player")
        #expect(app.line == "com.example.player\t412\tPlaying\t1\tPlayer")
        #expect(NowPlayingListLine(line: app.line) == app)
        let removed = NowPlayingListLine(bundleID: "com.example.gone", pid: 12, state: NowPlayingListLine.removed, isActive: false, name: "")
        #expect(NowPlayingListLine(line: removed.line) == removed)
        #expect(NowPlayingListLine.activeLine(412) == "#active\t412")
        #expect(NowPlayingListLine.active(in: NowPlayingListLine.activeLine(-1)) == -1)
        #expect(NowPlayingListLine(line: NowPlayingListLine.activeLine(412)) == nil)
        #expect(NowPlayingListLine.active(in: app.line) == nil)
        #expect(NowPlayingListLine(line: "can't read macOS's log") == nil)
    }

    @Test("why an app can be in Now Playing: its reason, the interface a switch shows, the switches, the interface's kind, a web app's browser; each empty when none")
    func nowPlayingReasons() {
        let electron = NowPlayingReasonsLine(path: "/Applications/Deezer.app", reason: "MediaPlayer, through Electron",
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

    @Test("the launch option: the one it needs and whether it runs with it, or none needed")
    func launchOption() {
        for running in [LaunchOptionAnswer.Running.yes, .no, .notRunning] {
            let answer = LaunchOptionAnswer(option: "--disable-backgrounding-occluded-windows", running: running)
            #expect(LaunchOptionAnswer(line: answer.line + "\n") == answer)
        }
        let none = LaunchOptionAnswer(option: nil, running: nil)
        #expect(none.line == "\t" && LaunchOptionAnswer(line: none.line) == none)
        #expect(LaunchOptionAnswer(line: CommandLineOptions.AppQuery.noApp) == nil)
    }

    @Test("the window's state: each one by its title, no window, not running; no app is none of them")
    func windowState() {
        let answers = CheckResult.WindowState.allCases.map(WindowStateAnswer.state) + [.noWindow, .notRunning]
        for answer in answers {
            #expect(WindowStateAnswer(line: answer.line + "\n") == answer)
        }
        #expect(WindowStateAnswer.state(.covered).windowState == .covered && WindowStateAnswer.noWindow.windowState == nil)
        #expect(WindowStateAnswer(line: CommandLineOptions.AppQuery.noApp) == nil)
    }
}
