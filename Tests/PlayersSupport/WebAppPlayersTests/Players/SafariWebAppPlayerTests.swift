import Foundation
import Testing
import AutoHushKit
@testable import WebAppPlayers
import AutoHushTestSupport
import PlayersTestSupport

@Suite("SafariWebAppPlayer", .waitsTimeLimit)
struct SafariWebAppPlayerTests {
    static let app = SafariWebApp(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                                  url: URL(fileURLWithPath: "/Users/test/Applications/YT Music.app"))
    static let learned = PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause", places: [ButtonPlaces.playerBar])

    struct Setup {
        let page = FakeWebPage()
        let store: MemoryRecipeStore
        let clock = ManualClock.webAppTests()
        let muter = FakeMuter()
        let probe = FakeLevelProbe()
        let pid = Locked<pid_t>(4242)
        let key = PlayPauseKeyBox()
        let nowPlaying = NowPlayingBox()
        let player: SafariWebAppPlayer

        init(recipe: PlayPauseRecipe? = nil, running: Bool = true, kind: MusicPlayerKind = .safariWebApp, canMute: Bool = true) {
            store = MemoryRecipeStore(recipe.map { [SafariWebAppPlayerTests.app.bundleID: $0] } ?? [:])
            player = SafariWebAppPlayer(
                app: SafariWebAppPlayerTests.app, kind: kind, page: page, canMute: canMute, store: store, muter: muter, levelProbe: probe,
                processIdentifier: { [pid] in running ? pid.value : nil },
                clock: { [clock] in clock.now },
                sleep: { [clock] in clock.advance(by: $0) },
                pressKey: { [key] in key.press() },
                nowPlaying: { [nowPlaying] in nowPlaying.answer }, audioRecordingAllowed: { true })
        }

        /// A page with its player bar at the bottom, a playlist's own Play
        /// higher up, and filler.
        func showPage(_ bar: String = "Play") {
            var buttons: [Int: FakeWebPage.Button] = [
                1: .init(label: bar, place: ButtonPlaces.playerBar),
                2: .init(label: "Play", place: ButtonPlaces.main),
            ]
            for number in 3..<14 { buttons[number] = .init(label: "Item \(number)", place: ButtonPlaces.main) }
            page.buttonsByNumber = buttons
        }

        /// Two windows of the web app, each with the page: the first one's
        /// buttons are 1 to 13, the second one's 21 to 33.
        func showTwoWindows(_ first: String, _ second: String) {
            showPage(first)
            var buttons = page.buttonsByNumber
            buttons[21] = .init(label: second, place: ButtonPlaces.playerBar)
            buttons[22] = .init(label: "Play", place: ButtonPlaces.main)
            for number in 23..<34 { buttons[number] = .init(label: "Item \(number)", place: ButtonPlaces.main) }
            page.buttonsByNumber = buttons
        }
    }

    @Test("it's a Safari web app, controlled through Accessibility, without fades, read about once a second, checking its own presses")
    func basics() async throws {
        let setup = Setup()
        #expect(setup.player.kind == .safariWebApp)
        #expect(setup.player.name == "YT Music")
        #expect(setup.player.controlPermission == .accessibility(player: "YT Music"))
        #expect(!setup.player.canFade)
        #expect(await setup.player.volume() == nil)
        try await setup.player.setVolume(30) // nothing to set
        #expect(setup.player.stateReportDelay == PolledStateObserver.reportDelay) // a change is seen up to a read later
        #expect(setup.player.checksItsPresses) // one the page refuses mutes it: never pressed again by the arbiter
        #expect(setup.player.installedURL == SafariWebAppPlayerTests.app.url)
        #expect(!setup.player.isUntested)
    }

    @Test("its page's switch is released when asked (it's no longer the player), and again each time")
    func releasesPage() async {
        let setup = Setup(recipe: SafariWebAppPlayerTests.learned)
        #expect(setup.page.releases == 0)
        await setup.player.releasePage()
        #expect(setup.page.releases == 1)
        await setup.player.releasePage()
        #expect(setup.page.releases == 2)
    }
}
