import Foundation
@testable import WebAppPlayers
@testable import AutoHushKit
import AutoHushTestSupport
import PlayersTestSupport

/// An added app's page in memory: its player bar's Play/Pause says "Play"
/// (with filler buttons, as a loaded page has) while its sound is on; out of
/// sight (`wordsCurrent` false), its word lags; a press runs `onPress`.
final class StubPage: WebPage {
    static let place = ButtonPlace(path: ["AXGroup", "AXToolbar"], distanceFromBottom: 40)
    private let released = Locked(0)
    private let pressed = Locked(0)
    private let current = Locked(true)
    var releases: Int { released.value }
    var presses: Int { pressed.value }
    var wordsCurrent: Bool {
        get { current.value }
        set { current.value = newValue }
    }
    let onPress = Locked<(@Sendable () -> Void)?>(nil)

    /// Its page's player, as an added app's: its button learned already.
    /// Waits on `clock`, which only `sleep` moves.
    func player(muter: any AudioMuting = FakeMuter(), clock: ManualClock = ManualClock()) -> SafariWebAppPlayer {
        let app = SafariWebApp(bundleID: "com.example.jukebox", name: "Jukebox", url: URL(fileURLWithPath: "/Applications/Jukebox.app"))
        let recipe = PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause", places: [Self.place])
        return SafariWebAppPlayer(app: app, kind: .app, page: self, store: MemoryRecipeStore([app.bundleID: recipe]), muter: muter,
                                  levelProbe: FakeLevelProbe(audible: true), processIdentifier: { 4242 },
                                  clock: { clock.now }, sleep: { clock.advance(by: $0) }, asyncSleep: { clock.advance(by: $0) },
                                  audioRecordingAllowed: { true })
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
    func press(_ handle: ButtonHandle) -> Bool {
        pressed.increment()
        onPress.value?()
        return true
    }
    func isPlayingSound(pid: pid_t) -> Bool { true }
    func wordsAreCurrent(pid: pid_t) -> Bool { wordsCurrent }
    func release() { released.increment() }
}
