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
}
