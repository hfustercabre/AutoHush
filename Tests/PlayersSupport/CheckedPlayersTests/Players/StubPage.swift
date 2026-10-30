import Foundation
@testable import WebAppPlayers
@testable import AutoHushKit
import AutoHushTestSupport
import PlayersTestSupport

/// An added app's page in memory: its player bar's Play/Pause says "Play"
/// (with filler buttons, as a loaded page has) while its sound is on.
final class StubPage: WebPage {
    static let place = ButtonPlace(path: ["AXGroup", "AXToolbar"], distanceFromBottom: 40)
    private let released = Locked(0)
    var releases: Int { released.value }

    /// Its page's player, as an added app's: its button learned already.
    func player(muter: any AudioMuting = FakeMuter()) -> SafariWebAppPlayer {
        let app = SafariWebApp(bundleID: "com.example.jukebox", name: "Jukebox", url: URL(fileURLWithPath: "/Applications/Jukebox.app"))
        let recipe = PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause", places: [Self.place])
        return SafariWebAppPlayer(app: app, kind: .app, page: self, store: MemoryRecipeStore([app.bundleID: recipe]), muter: muter,
                                  levelProbe: FakeLevelProbe(audible: true), processIdentifier: { 4242 }, audioRecordingAllowed: { true })
    }

    func isTrusted(prompt: Bool) -> Bool { true }
    func buttons(pid: pid_t) -> [PageButton]? {
        [PageButton(handle: ButtonHandle(1), label: "Play")] + (2..<14).map { PageButton(handle: ButtonHandle($0), label: "Item \($0)") }
    }
    func hasWindow(pid: pid_t) -> Bool { true }
    func button(_ handle: ButtonHandle) -> PageButton? { buttons(pid: 0)?.first { $0.handle == handle } }
    func place(of handle: ButtonHandle) -> ButtonPlace? {
        handle == ButtonHandle(1) ? Self.place : ButtonPlace(path: ["AXGroup", "AXGroup:AXLandmarkMain"], distanceFromBottom: 600)
    }
    func standing(of handle: ButtonHandle) -> ButtonStanding? { ButtonStanding() }
    func press(_ handle: ButtonHandle) -> Bool { true }
    func isPlayingSound(pid: pid_t) -> Bool { true }
    func release() { released.increment() }
}
