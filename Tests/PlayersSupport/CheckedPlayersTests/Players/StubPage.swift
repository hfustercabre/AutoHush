import Foundation
@testable import WebAppPlayers
@testable import AutoHushKit
import AutoHushTestSupport
import PlayersTestSupport

/// An added app's page in memory: its player bar's Play/Pause says "Play"
/// (with filler buttons, as a loaded page has) while its sound is on, or
/// follows `playing` when given ("Pause" while it plays); out of sight
/// (`wordsCurrent` false), its word lags; a press runs `onPress`. One stand-in
/// for the module (the 2026-11-06 full check's T-12).
final class StubPage: WebPage {
    static let place = ButtonPlace(path: ["AXGroup", "AXToolbar"], distanceFromBottom: 40)
    private let playing: Locked<Bool>?
    private let released = Locked(0)
    private let pressed = Locked(0)
    private let shown = Locked(0)
    private let read = Locked(0)
    private let current: Locked<Bool>
    var releases: Int { released.value }
    var presses: Int { pressed.value }
    /// How many times its switch was turned on to show it (`showPage`).
    var shows: Int { shown.value }
    /// How many times its buttons were read.
    var reads: Int { read.value }
    var wordsCurrent: Bool {
        get { current.value }
        set { current.value = newValue }
    }
    let onPress = Locked<(@Sendable () -> Void)?>(nil)

    init(playing: Locked<Bool>? = nil, wordsCurrent: Bool = true) {
        self.playing = playing
        current = Locked(wordsCurrent)
    }

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
        read.increment()
        return [PageButton(handle: ButtonHandle(1), label: playing?.value == true ? "Pause" : "Play")]
            + (2..<14).map { PageButton(handle: ButtonHandle($0), label: "Item \($0)") }
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
    func showPage(pid: pid_t) { shown.increment() }
    func release() { released.increment() }
}
