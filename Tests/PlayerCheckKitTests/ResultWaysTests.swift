import Foundation
import Testing
@testable import PlayerCheckKit
@testable import CheckedPlayers
import ScriptablePlayers
@testable import WebAppPlayers

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

    @Test("a toggle with no state is kept only with another sign of the app's state; a pause and a play always")
    func toggles() {
        #expect(ResultWays.canRun(script, besides: [], reportsReadable: false))
        // A state found wrong (Apple TV's) is left out: its pause and play still run.
        var stateless = script
        stateless.state = nil
        #expect(ResultWays.canRun(stateless, besides: [], reportsReadable: false))
        #expect(!ResultWays.canRun(toggle, besides: [.script(toggle), .panel(rememberedRow: nil)], reportsReadable: false))
        #expect(ResultWays.canRun(toggle, besides: [.menu(menuName: "Controls")], reportsReadable: false))
        #expect(ResultWays.canRun(toggle, besides: [.page(.webKit)], reportsReadable: false))
        #expect(ResultWays.canRun(toggle, besides: [], reportsReadable: true))
    }

    private let url = URL(filePath: "/Applications/Jukebox.app")
    private let everywhere: [(state: CheckResult.WindowState, result: TrialResult)] = [(.visible, .worked), (.covered, .worked)]
    private let some: [(state: CheckResult.WindowState, result: TrialResult)] = [(.visible, .worked), (.minimized, .didNotPause),
                                                                                  (.hidden, .pausedOnly)]
    private let nowhere: [(state: CheckResult.WindowState, result: TrialResult)] = [(.visible, .didNotPause), (.covered, .pausedOnly)]

    private func findings(_ ways: [CheckResult.WayKind: CheckFindings.Way]) -> CheckFindings {
        CheckFindings(bundleID: "com.example.jukebox", appName: "Jukebox", appURL: url, ways: ways)
    }

    /// Each way tried over the window states: the script in some, the menu
    /// everywhere, the panel nowhere; the page not checked. A notification,
    /// the launch option and a stale row found too.
    private var overTheStates: CheckFindings {
        var found = findings([
            .script: .init(isThere: true, trials: some, first: .worked, setup: .script(script)),
            .menu: .init(isThere: true, trials: everywhere, first: .worked, setup: .menu(menuName: "Controls")),
            .page: .init(isThere: true, notChecked: .noAccessibility),
            .panel: .init(isThere: true, trials: nowhere, first: .didNotPause, setup: .panel(rememberedRow: nil)),
        ])
        found.stateNotification = "com.example.jukebox.state"
        found.needsLaunchOption = true
        found.panelRowIsStale = true
        return found
    }

    /// No window states: a toggle and the page, not checked but tried after
    /// all, each by its only run; no menu; Now Playing hidden.
    private var onlyRuns: CheckFindings {
        var found = findings([
            .script: .init(isThere: true, first: .worked, setup: .script(toggle)),
            .menu: .init(isThere: false),
            .page: .init(isThere: true, notChecked: .notChecked, first: .worked, setup: .page(.webKit)),
            .panel: .init(isThere: true, trials: nowhere, first: .didNotPause, setup: .panel(rememberedRow: "Song")),
        ])
        found.nowPlayingHidden = true
        return found
    }

    /// A toggle with nothing else to tell its state but the panel, whose row is stale.
    private var toggleAndPanel: CheckFindings {
        var found = findings([.script: .init(isThere: true, first: .worked, setup: .script(toggle)),
                              .panel: .init(isThere: true, first: .worked, setup: .panel(rememberedRow: nil))])
        found.panelRowIsStale = true
        return found
    }

    @Test("each way's mark is its trials' over the window states, with the states it failed in; one not checked says why")
    func marksOverTheStates() {
        let (result, _) = overTheStates.result()
        #expect(result.ways == [CheckResult.WayResult(kind: .script, mark: .some, failedStates: [.minimized, .hidden]),
                                CheckResult.WayResult(kind: .menu, mark: .works), CheckResult.WayResult(kind: .page, mark: .noAccessibility),
                                CheckResult.WayResult(kind: .panel, mark: .none)])
    }

    @Test("the setup has the ways that worked, everywhere first, with the check's notification and launch option; no stale row without the panel")
    func setupOfTheWaysThatWorked() {
        let (result, toggleLeftOut) = overTheStates.result()
        #expect(!toggleLeftOut)
        #expect(result.setup == PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox", appURL: url,
                                            ways: [.menu(menuName: "Controls"), .script(script)], stateNotification: "com.example.jukebox.state",
                                            needsLaunchOption: true)) // the stale row isn't kept: no panel way
    }

    @Test("with no window states, a way is marked by its only run; one not there, tried after all, or with Now Playing hidden is marked so")
    func marksOfOnlyRuns() {
        #expect(onlyRuns.result().result.ways.map(\.mark) == [.works, .notThere, .works, .menuBarHidden])
    }

    @Test("a toggle with no state is kept when the page tells the app's state")
    func toggleKeptWithThePage() {
        let (result, toggleLeftOut) = onlyRuns.result()
        #expect(!toggleLeftOut && result.setup?.ways == [.script(toggle), .page(.webKit)]) // the page tells the toggle's state
    }

    @Test("a toggle with nothing else to tell the app's state is left out, and marked so")
    func toggleAloneLeftOut() {
        let (result, toggleLeftOut) = toggleAndPanel.result()
        #expect(toggleLeftOut && result.ways.map(\.mark) == [.toggleOnly, .notThere, .notThere, .works])
        #expect(result.setup?.ways == [.panel(rememberedRow: nil)])
    }

    @Test("a stale row is kept with the panel way")
    func staleRowKeptWithThePanel() {
        #expect(toggleAndPanel.result().result.setup?.panelRowIsStale == true)
    }

    @Test("a toggle with no state is kept when what the app reports to Now Playing can be read")
    func toggleKeptWithReports() {
        var found = toggleAndPanel
        found.reportsReadable = true
        #expect(found.result().result.setup?.ways == [.script(toggle), .panel(rememberedRow: nil)])
    }

    @Test("with no way found, there's no setup and every way is not there")
    func nothingFound() {
        let nothing = findings([:]).result().result
        #expect(nothing.setup == nil && nothing.ways.map(\.mark) == [.notThere, .notThere, .notThere, .notThere])
    }

    @Test("a way that's there but wasn't tried is marked not tried")
    func notTried() {
        #expect(findings([.panel: .init(isThere: true)]).result().result.ways.last?.mark == .notTried)
    }

    @Test("where the app's song showed besides its windows' titles goes into its setup with the panel only, which reads it there")
    func panelClues() throws {
        let url = URL(filePath: "/Applications/Jukebox.app")
        let clues = try #require(PanelClues(page: PanelClues.Page(access: .webKit, labels: ["Pause", "Play"]), script: .currentTrack))
        var found = CheckFindings(bundleID: "com.example.jukebox", appName: "Jukebox", appURL: url, ways: [
            .menu: .init(isThere: true, first: .worked, setup: .menu(menuName: "Controls")),
            .panel: .init(isThere: true, first: .worked, setup: .panel(rememberedRow: nil)),
        ])
        found.panelClues = clues
        #expect(found.result().result.setup?.panelClues == clues)
        found.ways[.panel] = .init(isThere: true, first: .didNotPause, setup: .panel(rememberedRow: nil))
        #expect(found.result().result.setup?.ways == [.menu(menuName: "Controls")] && found.result().result.setup?.panelClues == nil)
        #expect(PanelClues(page: nil, script: nil) == nil) // nothing more than its titles
    }
}
