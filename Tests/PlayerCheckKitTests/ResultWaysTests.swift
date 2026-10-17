import Foundation
import Testing
@testable import PlayerCheckKit
import CheckedPlayers
import ScriptablePlayers

@Suite("ResultWays")
struct ResultWaysTests {
    private let script = ScriptSetup(commands: .pauseAndPlay(pause: "jukePaus", play: "jukePlay"), state: .playerState, hasVolume: false)
    private let toggle = ScriptSetup(commands: .toggle("jukeTogl"), state: nil, hasVolume: false)

    @Test("the panel last; before it, those that worked everywhere first; then AppleScript, the page, the menu")
    func order() {
        let ordered = ResultWays.ordered([
            .init(way: .panel(rememberedRow: nil), kind: .panel, everywhere: true),
            .init(way: .menu(menuName: "Controls"), kind: .menu, everywhere: true),
            .init(way: .script(script), kind: .script, everywhere: false),
            .init(way: .page(.webKit), kind: .page, everywhere: true),
        ])
        #expect(ordered == [.page(.webKit), .menu(menuName: "Controls"), .script(script), .panel(rememberedRow: nil)])
    }

    @Test("a toggle with no state is kept only with another sign of the app's state")
    func toggles() {
        #expect(ResultWays.canRun(script, besides: [], reportsReadable: false))
        #expect(!ResultWays.canRun(toggle, besides: [.script(toggle), .panel(rememberedRow: nil)], reportsReadable: false))
        #expect(ResultWays.canRun(toggle, besides: [.menu(menuName: "Controls")], reportsReadable: false))
        #expect(ResultWays.canRun(toggle, besides: [.page(.webKit)], reportsReadable: false))
        #expect(ResultWays.canRun(toggle, besides: [], reportsReadable: true))
    }

    @Test("a check's findings: each way's mark over the window states, or its only run; not there, or not checked unless tried after all; Now Playing hidden; a toggle with no state left out unless another sign tells; a stale row kept only with the panel")
    func findings() {
        let url = URL(filePath: "/Applications/Jukebox.app")
        func findings(_ ways: [CheckResult.WayKind: CheckFindings.Way]) -> CheckFindings {
            CheckFindings(bundleID: "com.example.jukebox", appName: "Jukebox", appURL: url, ways: ways)
        }
        let everywhere: [(state: CheckResult.WindowState, result: TrialResult)] = [(.visible, .worked), (.covered, .worked)]
        let some: [(state: CheckResult.WindowState, result: TrialResult)] = [(.visible, .worked), (.minimized, .didNotPause), (.hidden, .pausedOnly)]
        let nowhere: [(state: CheckResult.WindowState, result: TrialResult)] = [(.visible, .didNotPause), (.covered, .pausedOnly)]

        var found = findings([
            .script: .init(isThere: true, trials: some, first: .worked, setup: .script(script)),
            .menu: .init(isThere: true, trials: everywhere, first: .worked, setup: .menu(menuName: "Controls")),
            .page: .init(isThere: true, notChecked: .noAccessibility),
            .panel: .init(isThere: true, trials: nowhere, first: .didNotPause, setup: .panel(rememberedRow: nil)),
        ])
        found.stateNotification = "com.example.jukebox.state"
        found.needsLaunchOption = true
        found.panelRowIsStale = true
        var (result, toggleLeftOut) = found.result()
        #expect(result.ways == [CheckResult.WayResult(kind: .script, mark: .some, failedStates: [.minimized, .hidden]),
                                CheckResult.WayResult(kind: .menu, mark: .works), CheckResult.WayResult(kind: .page, mark: .noAccessibility),
                                CheckResult.WayResult(kind: .panel, mark: .none)])
        #expect(!toggleLeftOut)
        #expect(result.setup == PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox", appURL: url,
                                            ways: [.menu(menuName: "Controls"), .script(script)], stateNotification: "com.example.jukebox.state",
                                            needsLaunchOption: true)) // the stale row isn't kept: no panel way

        // The page tried after all; no states, its only run counts; Now Playing hidden, the panel's none says so.
        found = findings([
            .script: .init(isThere: true, first: .worked, setup: .script(toggle)),
            .menu: .init(isThere: false),
            .page: .init(isThere: true, notChecked: .notChecked, first: .worked, setup: .page(.webKit)),
            .panel: .init(isThere: true, trials: nowhere, first: .didNotPause, setup: .panel(rememberedRow: "Song")),
        ])
        found.nowPlayingHidden = true
        (result, toggleLeftOut) = found.result()
        #expect(result.ways.map(\.mark) == [.works, .notThere, .works, .menuBarHidden])
        #expect(!toggleLeftOut && result.setup?.ways == [.script(toggle), .page(.webKit)]) // the page tells the toggle's state

        // A toggle with nothing else to tell: left out, and marked so; the stale row kept with the panel.
        found = findings([.script: .init(isThere: true, first: .worked, setup: .script(toggle)),
                          .panel: .init(isThere: true, first: .worked, setup: .panel(rememberedRow: nil))])
        found.panelRowIsStale = true
        (result, toggleLeftOut) = found.result()
        #expect(toggleLeftOut && result.ways.map(\.mark) == [.toggleOnly, .notThere, .notThere, .works])
        #expect(result.setup?.ways == [.panel(rememberedRow: nil)] && result.setup?.panelRowIsStale == true)
        found.reportsReadable = true
        #expect(found.result().result.setup?.ways == [.script(toggle), .panel(rememberedRow: nil)])

        let nothing = findings([:]).result().result
        #expect(nothing.setup == nil && nothing.ways.map(\.mark) == [.notThere, .notThere, .notThere, .notThere])
        #expect(findings([.panel: .init(isThere: true)]).result().result.ways.last?.mark == .notTried)
    }
}
