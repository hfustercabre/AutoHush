import Foundation
import Testing
import AutoHushKit
@testable import WebAppPlayers

@Suite("SafariWebAppPlayer", .timeLimit(.minutes(1)))
struct SafariWebAppPlayerTests {
    static let app = SafariWebApp(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                                  url: URL(fileURLWithPath: "/Users/test/Applications/YT Music.app"))
    static let learned = PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause", places: [Places.playerBar])

    private struct Setup {
        let page = FakeWebPage()
        let store: MemoryRecipeStore
        let clock = TestClock()
        let muter = FakeMuter()
        let probe = FakeLevelProbe()
        let pid = PIDBox(4242)
        let player: SafariWebAppPlayer

        init(recipe: PlayPauseRecipe? = nil, running: Bool = true) {
            store = MemoryRecipeStore(recipe.map { [SafariWebAppPlayerTests.app.bundleID: $0] } ?? [:])
            player = SafariWebAppPlayer(
                app: SafariWebAppPlayerTests.app, page: page, store: store, muter: muter, levelProbe: probe,
                processIdentifier: { [pid] in running ? pid.value : nil },
                clock: { [clock] in clock.now },
                sleep: { [clock] in clock.advance($0) }
            )
        }

        /// A page with its player bar at the bottom, a playlist's own Play
        /// higher up, and filler.
        func showPage(_ bar: String = "Play") {
            var buttons: [Int: FakeWebPage.Button] = [
                1: .init(label: bar, place: Places.playerBar),
                2: .init(label: "Play", place: Places.main),
            ]
            for number in 3..<14 { buttons[number] = .init(label: "Item \(number)", place: Places.main) }
            page.buttonsByNumber = buttons
        }
    }

    @Test("it's a Safari web app, controlled through Accessibility, without fades")
    func basics() {
        let setup = Setup()
        #expect(setup.player.kind == .safariWebApp)
        #expect(setup.player.name == "YT Music")
        #expect(setup.player.controlPermission == .accessibility(player: "YT Music"))
        #expect(!setup.player.canFade)
        #expect(setup.player.installedURL == SafariWebAppPlayerTests.app.url)
        #expect(!setup.player.isUntested)
    }

    @Test("it learns the button while its state is read, then reads the state from it")
    func learns() async throws {
        let setup = Setup()
        setup.showPage()
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))
        #expect(await setup.player.playerState() == .paused) // its sound is off

        // The user plays: the bar's button and the playlist's change, then the sound comes on.
        setup.page.set(1, label: "Pause")
        setup.page.set(2, label: "Pause")
        setup.clock.advance(1)
        _ = await setup.player.playerState()
        setup.page.sound = true
        setup.clock.advance(1)
        #expect(await setup.player.playerState() == .playing)
        #expect(setup.player.learningStatus == .learning(hasPlayed: true))

        // The user pauses; once the sound goes off it's learned, and the bar's
        // button is the one, at the bottom.
        setup.page.set(1, label: "Play")
        setup.page.set(2, label: "Play")
        setup.clock.advance(1)
        #expect(await setup.player.playerState() == .playing) // WebKit's sound lingers
        #expect(setup.player.learningStatus == .learning(hasPlayed: true))
        setup.page.sound = false
        setup.clock.advance(7)
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.player.learningStatus == .learned)
        #expect(setup.store.recipe(for: Self.app.bundleID) == Self.learned)

        setup.page.set(1, label: "Pause")
        #expect(await setup.player.playerState() == .playing)
    }

    @Test("learning is reported as it goes, starting with where it stands")
    func updates() async {
        let setup = Setup()
        setup.showPage()
        var updates = setup.player.learningUpdates().makeAsyncIterator()
        #expect(await updates.next() == .learning(hasPlayed: false))
        _ = await setup.player.playerState() // the first look
        setup.page.set(1, label: "Pause")
        setup.page.sound = true
        setup.clock.advance(1)
        _ = await setup.player.playerState() // sees the change and the sound
        #expect(await updates.next() == .learning(hasPlayed: true))
        setup.page.set(1, label: "Play")
        setup.page.sound = false
        setup.clock.advance(1)
        _ = await setup.player.playerState()
        #expect(await updates.next() == .learned)
    }

    @Test("it presses only from the opposite state, and waits for the page to follow")
    func presses() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Pause")
        #expect(setup.player.learningStatus == .learned)
        try await setup.player.pause()
        #expect(setup.page.presses == [1])
        #expect(await setup.player.playerState() == .paused)
        try await setup.player.pause() // paused already
        #expect(setup.page.presses == [1])
        try await setup.player.play()
        #expect(setup.page.presses == [1, 1])
        #expect(await setup.player.playerState() == .playing)
    }

    @Test("a press the page doesn't follow is an error when the web app can't be muted either")
    func ignoredPress() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Pause")
        setup.page.onPress = { _, _ in }
        setup.muter.canMute = false
        await #expect(throws: MusicPlayerError.self) { try await setup.player.pause() }
        #expect(setup.page.presses == [1])
    }

    @Test("a pause that takes never mutes")
    func pauseNeverMutes() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Pause")
        try await setup.player.pause()
        try await setup.player.play()
        #expect(setup.muter.log.isEmpty)
    }

    @Test("a press the page doesn't follow mutes it instead; playing unmutes, and plays it if it paused late")
    func ignoredPressMutes() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Pause")
        setup.page.onPress = { _, _ in }
        try await setup.player.pause()
        #expect(setup.muter.muted == [4242])
        #expect(await setup.player.playerState() == .paused)

        // The press took after all, late: the page is paused.
        setup.page.set(1, label: "Play")
        setup.page.onPress = nil
        try await setup.player.play()
        #expect(setup.muter.log == ["mute 4242", "unmute 4242"])
        #expect(setup.page.presses == [1, 1])
        #expect(await setup.player.playerState() == .playing)
    }

    @Test("a disabled Pause (an ad) is never pressed: muted instead, and only unmuted after")
    func disabledPauseMutes() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Pause")
        setup.page.buttonsByNumber[1]?.isEnabled = false
        try await setup.player.pause()
        #expect(setup.page.presses.isEmpty)
        #expect(setup.muter.muted == [4242])
        #expect(await setup.player.playerState() == .paused)

        // The ad ends and the music goes on, muted; the user doesn't touch it.
        setup.page.buttonsByNumber[1]?.isEnabled = true
        try await setup.player.play()
        #expect(setup.muter.muted.isEmpty)
        #expect(setup.page.presses.isEmpty)
        #expect(await setup.player.playerState() == .playing)
    }

    @Test("once a disabled Pause can be pressed (the ad is over), it's paused for real and unmuted; playing presses Play")
    func disabledPauseThenPaused() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Pause")
        setup.page.buttonsByNumber[1]?.isEnabled = false
        try await setup.player.pause()
        #expect(setup.muter.muted == [4242])

        setup.page.buttonsByNumber[1]?.isEnabled = true
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.page.presses == [1])
        #expect(setup.page.buttonsByNumber[1]?.label == "Play")
        #expect(setup.muter.muted.isEmpty)

        try await setup.player.play()
        #expect(setup.page.presses == [1, 1])
        #expect(await setup.player.playerState() == .playing)
    }

    @Test("heard while its button says Play (an ad): muted, nothing pressed, and playing only unmutes")
    func playsAnywayMutes() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Play")
        setup.page.sound = true
        setup.probe.audible = true
        #expect(await setup.player.muteIfPlayingAnyway())
        #expect(setup.muter.muted == [4242])
        #expect(setup.page.presses.isEmpty)
        #expect(await setup.player.playerState() == .paused)

        // The other app stops while the ad still plays: it's heard again.
        try await setup.player.play()
        #expect(setup.muter.muted.isEmpty)
        #expect(setup.page.presses.isEmpty)
    }

    @Test("once the ad is over and the music plays, it's paused for real and unmuted; playing presses Play")
    func playsAnywayThenPaused() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Play")
        setup.page.sound = true
        setup.probe.audible = true
        #expect(await setup.player.muteIfPlayingAnyway())

        setup.page.set(1, label: "Pause") // the song starts after the ad
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.page.presses == [1])
        #expect(setup.muter.log == ["mute 4242", "unmute 4242"])

        try await setup.player.play()
        #expect(setup.page.presses == [1, 1])
        #expect(await setup.player.playerState() == .playing)
    }

    @Test("a pause after the ad that doesn't take keeps it muted; playing then plays it if it paused late")
    func playsAnywayPressIgnored() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Play")
        setup.page.sound = true
        setup.probe.audible = true
        #expect(await setup.player.muteIfPlayingAnyway())
        setup.page.set(1, label: "Pause")
        setup.page.onPress = { _, _ in }
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.muter.muted == [4242])

        setup.page.set(1, label: "Play") // the press took, late
        setup.page.onPress = nil
        try await setup.player.play()
        #expect(setup.muter.muted.isEmpty)
        #expect(setup.page.presses == [1, 1])
        #expect(await setup.player.playerState() == .playing)
    }

    @Test("the silent sound a page keeps open after a pause is measured, and not muted")
    func silentAfterPauseNotMuted() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Play")
        setup.page.sound = true
        #expect(!(await setup.player.muteIfPlayingAnyway()))
        #expect(setup.probe.listens == 1)
        #expect(setup.muter.log.isEmpty)
    }

    @Test("with its sound off, or playing as its button says, it isn't even measured")
    func notMeasured() async {
        let setup = Setup(recipe: Self.learned)
        setup.probe.audible = true
        setup.showPage("Play")
        #expect(!(await setup.player.muteIfPlayingAnyway())) // sound off
        setup.showPage("Pause")
        setup.page.sound = true
        #expect(!(await setup.player.muteIfPlayingAnyway())) // it plays: it's paused instead
        #expect(setup.probe.listens == 0)
        #expect(setup.muter.log.isEmpty)
    }

    @Test("an ad isn't muted in AntiDot mode, nor before the button is learned")
    func playsAnywayNotAllowed() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Play")
        setup.page.sound = true
        setup.probe.audible = true
        setup.player.allowTaps(false)
        #expect(!(await setup.player.muteIfPlayingAnyway()))

        let learning = Setup()
        learning.showPage("Play")
        learning.page.sound = true
        learning.probe.audible = true
        #expect(!(await learning.player.muteIfPlayingAnyway()))
        #expect(setup.probe.listens == 0 && learning.probe.listens == 0)
        #expect(setup.muter.log.isEmpty && learning.muter.log.isEmpty)
    }

    @Test("stopping monitoring lifts a mute without playing")
    @MainActor
    func stopUnmutes() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Pause")
        setup.page.buttonsByNumber[1]?.isEnabled = false
        try await setup.player.pause()
        let observer = setup.player.makeStateObserver { _ in }
        observer.start()
        observer.stop()
        for _ in 0..<100 where !setup.muter.muted.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(setup.muter.muted.isEmpty)
        #expect(setup.page.presses.isEmpty)
    }

    @Test("a muted web app opened again is unmuted and read afresh")
    func reopenedUnmutes() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Pause")
        setup.page.buttonsByNumber[1]?.isEnabled = false
        try await setup.player.pause()
        setup.pid.value = 5151
        setup.page.buttonsByNumber[1]?.isEnabled = true
        #expect(await setup.player.playerState() == .playing)
        #expect(setup.muter.muted.isEmpty)
    }

    @Test("before it has learned, pausing presses nothing")
    func notLearned() async {
        let setup = Setup()
        setup.showPage("Pause")
        setup.page.sound = true
        await #expect(throws: MusicPlayerError.stillLearning) { try await setup.player.pause() }
        #expect(setup.page.presses.isEmpty)
    }

    @Test("muting isn't allowed in AntiDot mode: a disabled Pause is then an error, and nothing is muted")
    func mutingNotAllowed() async {
        let setup = Setup(recipe: Self.learned)
        setup.player.allowTaps(false)
        setup.showPage("Pause")
        setup.page.buttonsByNumber[1]?.isEnabled = false
        await #expect(throws: MusicPlayerError.self) { try await setup.player.pause() }
        #expect(setup.muter.muted.isEmpty)
        #expect(setup.page.presses.isEmpty)

        setup.player.allowTaps(true)
        try? await setup.player.pause()
        #expect(setup.muter.muted == [4242])
    }

    @Test("after a reload the button is found again by its place, not by another Play")
    func reload() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage()
        #expect(await setup.player.playerState() == .paused)
        let looks = setup.page.looks
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.page.looks == looks) // the button is read, not looked for
        setup.page.reload(offset: 100)
        setup.page.set(101, label: "Pause")
        #expect(await setup.player.playerState() == .playing)
        #expect(setup.page.looks == looks + 1)
    }

    @Test("without a window it's stopped, and windows aren't looked for again for a while")
    func noWindow() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage()
        setup.page.hasWindow = false
        #expect(await setup.player.playerState() == .stopped)
        let looks = setup.page.looks
        setup.clock.advance(1)
        #expect(await setup.player.playerState() == .stopped)
        #expect(setup.page.looks == looks)
        setup.page.hasWindow = true
        setup.clock.advance(WebAppControl.noWindowPause)
        #expect(await setup.player.playerState() == .paused)
    }

    @Test("a button missing a minute from a page that shows is learned again, keeping the old place")
    func relearns() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage()
        // The site shows another layout: its Play/Pause sits elsewhere.
        setup.page.buttonsByNumber[1] = .init(label: "Play", place: Places.fullScreen)
        #expect(await setup.player.playerState() == .unknown)
        setup.clock.advance(WebAppControl.missingBeforeLearning)
        _ = await setup.player.playerState()
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))

        setup.page.set(1, label: "Pause")
        setup.page.sound = true
        setup.clock.advance(1)
        _ = await setup.player.playerState()
        setup.page.set(1, label: "Play")
        setup.page.sound = false
        setup.clock.advance(1)
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.player.learningStatus == .learned)
        #expect(setup.store.recipe(for: Self.app.bundleID)?.places == [Places.fullScreen, Places.playerBar])
    }

    @Test("a missing button that turns up again ends the learning")
    func buttonBack() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage()
        setup.page.buttonsByNumber[1] = .init(label: "Play", place: Places.fullScreen)
        _ = await setup.player.playerState()
        setup.clock.advance(WebAppControl.missingBeforeLearning)
        _ = await setup.player.playerState()
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))
        setup.page.buttonsByNumber[1] = .init(label: "Play", place: Places.playerBar)
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.player.learningStatus == .learned)
    }

    @Test("a page still loading (few buttons) never starts learning again")
    func loading() async {
        let setup = Setup(recipe: Self.learned)
        setup.page.buttonsByNumber = [1: .init(label: "Sign In", place: Places.main)]
        _ = await setup.player.playerState()
        setup.clock.advance(WebAppControl.missingBeforeLearning * 2)
        #expect(await setup.player.playerState() == .unknown)
        #expect(setup.player.learningStatus == .learned)
    }

    @Test("a disabled Pause (an ad playing) is never pressed, even when it can't be muted")
    func disabledPause() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Pause")
        setup.page.buttonsByNumber[1]?.isEnabled = false
        setup.muter.canMute = false
        #expect(await setup.player.playerState() == .playing)
        await #expect(throws: MusicPlayerError.self) { try await setup.player.pause() }
        #expect(setup.page.presses.isEmpty)
    }

    @Test("a disabled Play means there's nothing to play")
    func disabled() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage()
        setup.page.buttonsByNumber[1]?.isEnabled = false
        #expect(await setup.player.playerState() == .stopped)
    }

    @Test("not running, or without Accessibility, it can't be controlled")
    func access() async {
        let stopped = Setup(recipe: Self.learned, running: false)
        #expect(await stopped.player.playerState() == .notRunning)
        await #expect(throws: MusicPlayerError.playerNotRunning) { try await stopped.player.verifyControlAccess() }

        let untrusted = Setup(recipe: Self.learned)
        untrusted.showPage()
        untrusted.page.trusted = false
        #expect(await untrusted.player.playerState() == .unknown)
        await #expect(throws: MusicPlayerError.accessibilityPermissionDenied) {
            try await untrusted.player.verifyControlAccess()
        }
        untrusted.page.trusted = true
        try? await untrusted.player.verifyControlAccess() // not learned is fine: it learns while running
    }
}

/// A pid the tests change, as when the web app is opened again.
final class PIDBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: pid_t
    init(_ value: pid_t) { _value = value }
    var value: pid_t {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
