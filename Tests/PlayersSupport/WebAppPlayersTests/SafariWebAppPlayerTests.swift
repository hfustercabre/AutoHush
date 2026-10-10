import Foundation
import Testing
import AutoHushKit
@testable import WebAppPlayers
import AutoHushTestSupport

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
        let key = PlayPauseKeyBox()
        let nowPlaying = NowPlayingBox()
        let player: SafariWebAppPlayer

        init(recipe: PlayPauseRecipe? = nil, running: Bool = true) {
            store = MemoryRecipeStore(recipe.map { [SafariWebAppPlayerTests.app.bundleID: $0] } ?? [:])
            player = SafariWebAppPlayer(
                app: SafariWebAppPlayerTests.app, page: page, store: store, muter: muter, levelProbe: probe,
                processIdentifier: { [pid] in running ? pid.value : nil },
                clock: { [clock] in clock.now },
                sleep: { [clock] in clock.advance($0) },
                pressKey: { [key] in key.press() },
                nowPlaying: { [nowPlaying] in nowPlaying.answer }
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

        /// Two windows of the web app, each with the page: the first one's
        /// buttons are 1 to 13, the second one's 21 to 33.
        func showTwoWindows(_ first: String, _ second: String) {
            showPage(first)
            var buttons = page.buttonsByNumber
            buttons[21] = .init(label: second, place: Places.playerBar)
            buttons[22] = .init(label: "Play", place: Places.main)
            for number in 23..<34 { buttons[number] = .init(label: "Item \(number)", place: Places.main) }
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

    @Test("it learns the button from the user saying it plays, then that it's paused; then reads the state from it")
    func learns() async throws {
        let setup = Setup()
        setup.showPage()
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))
        #expect(await setup.player.playerState() == .paused) // its sound is off
        let looks = setup.page.looks
        setup.clock.advance(1)
        _ = await setup.player.playerState()
        #expect(setup.page.looks == looks) // the page is looked at only when the user says so

        // The user plays: the bar's button and the playlist's change, the sound comes on; It's Playing.
        setup.page.set(1, label: "Pause")
        setup.page.set(2, label: "Pause")
        setup.page.sound = true
        #expect(await setup.player.playerState() == .playing)
        #expect(await setup.player.markPlaying() == .noted)
        #expect(setup.player.learningStatus == .learning(hasPlayed: true))

        // The user pauses; It's Paused: the bar's button is the one, at the bottom.
        setup.page.set(1, label: "Play")
        setup.page.set(2, label: "Play")
        setup.clock.advance(5)
        #expect(await setup.player.markPaused() == .noted)
        #expect(setup.player.learningStatus == .learned)
        #expect(setup.store.recipe(for: Self.app.bundleID) == Self.learned)
        #expect(setup.page.presses.isEmpty)

        setup.page.set(1, label: "Pause")
        #expect(await setup.player.playerState() == .playing)
    }

    @Test("after It's Playing it pauses itself with the Play/Pause key, learns the button that changed, and plays again with it")
    func pausesByItself() async {
        let setup = Setup()
        setup.showPage()
        #expect(await setup.player.pauseByItself() == .didntTake) // It's Playing comes first
        #expect(setup.key.count == 0)

        setup.page.set(1, label: "Pause")
        setup.page.set(2, label: "Pause")
        setup.page.sound = true
        #expect(await setup.player.markPlaying() == .noted)
        // The key reaches the web app: the bar's button and the playlist's change.
        setup.key.onPress = { [page = setup.page] in
            page.set(1, label: "Play")
            page.set(2, label: "Play")
        }
        #expect(await setup.player.pauseByItself() == .paused)
        #expect(setup.key.count == 1)
        #expect(setup.player.learningStatus == .learned)
        #expect(setup.store.recipe(for: Self.app.bundleID) == Self.learned)
        #expect(setup.page.presses == [1]) // played again with the learned button
        #expect(setup.page.buttonsByNumber[1]?.label == "Pause")
    }

    @Test("SoundCloud: learned is its bar's Play current, among the player's controls, not a song's tile scrolled out of sight")
    func soundCloudsBar() async {
        let setup = Setup()
        let bar = ButtonPlace(path: ["AXGroup:AXLandmarkContentInfo"], distanceFromBottom: 24)
        var buttons: [Int: FakeWebPage.Button] = [
            1: .init(label: "Pause current", place: bar, withControls: true),
            2: .init(label: "Pause", place: ButtonPlace(path: ["AXGroup"], distanceFromBottom: -77), outOfSight: true),
        ]
        for number in 3..<14 { buttons[number] = .init(label: "Item \(number)", place: Places.main) }
        setup.page.buttonsByNumber = buttons
        setup.page.sound = true
        #expect(await setup.player.markPlaying() == .noted)
        setup.key.onPress = { [page = setup.page] in
            page.set(1, label: "Play current")
            page.set(2, label: "Play")
        }
        #expect(await setup.player.pauseByItself() == .paused)
        #expect(setup.store.recipe(for: Self.app.bundleID)
            == PlayPauseRecipe(playLabel: "Play current", pauseLabel: "Pause current", places: [bar]))
        #expect(setup.page.presses == [1]) // played again with the bar's button
    }

    @Test("when the Play/Pause key changes nothing on the page, it's pressed again to undo it, and the user pauses it")
    func keyDoesNothing() async {
        let setup = Setup()
        setup.showPage()
        setup.page.set(1, label: "Pause")
        setup.page.sound = true
        #expect(await setup.player.markPlaying() == .noted)
        let started = setup.clock.now
        #expect(await setup.player.pauseByItself() == .didntTake)
        #expect(setup.key.count == 2) // the second undoes the first, wherever it went
        #expect(setup.clock.now.timeIntervalSince(started) >= 3)
        #expect(setup.player.learningStatus == .learning(hasPlayed: true))
        #expect(setup.page.presses.isEmpty)

        setup.page.set(1, label: "Play")
        #expect(await setup.player.markPaused() == .noted)
        #expect(setup.player.learningStatus == .learned)
    }

    @Test("when another app is Now Playing, or none is, the Play/Pause key isn't pressed: the user pauses it")
    func keyWouldGoElsewhere() async {
        // A pid that can't be the web app's, nor one of its helpers.
        for answer in [NowPlayingApp.Answer.process(pid_t.max - 1), .none] {
            let setup = Setup()
            setup.showPage()
            setup.page.set(1, label: "Pause")
            setup.page.sound = true
            setup.nowPlaying.answer = answer
            #expect(await setup.player.markPlaying() == .noted)
            #expect(await setup.player.pauseByItself() == .keyGoesElsewhere)
            #expect(setup.key.count == 0)
            #expect(setup.page.presses.isEmpty)
            #expect(setup.player.learningStatus == .learning(hasPlayed: true))

            setup.page.set(1, label: "Play") // the user paused it
            #expect(await setup.player.markPaused() == .noted)
            #expect(setup.player.learningStatus == .learned)
        }
    }

    @Test("when the web app itself is Now Playing, the Play/Pause key is pressed")
    func keyReachesTheWebApp() async {
        let setup = Setup()
        setup.showPage()
        setup.page.set(1, label: "Pause")
        setup.page.sound = true
        setup.nowPlaying.answer = .process(setup.pid.value)
        #expect(await setup.player.markPlaying() == .noted)
        setup.key.onPress = { [page = setup.page] in page.set(1, label: "Play") }
        #expect(await setup.player.pauseByItself() == .paused)
        #expect(setup.key.count == 1)
        #expect(setup.player.learningStatus == .learned)
    }

    @Test("waiting for the page to change after the Play/Pause key, a page without words isn't looked at twice: the wait stays the key's")
    func keyWaitLooksOnce() async {
        let setup = Setup()
        setup.showPage()
        setup.page.set(1, label: "Pause")
        setup.page.sound = true
        #expect(await setup.player.markPlaying() == .noted)
        setup.page.blankLooks = 100 // its words gone meanwhile (a window restored at login)
        let started = setup.clock.now
        let looksBefore = setup.page.looks
        #expect(await setup.player.pauseByItself() == .didntTake)
        let checks = Int(WebAppControl.keyWait / WebAppControl.keyCheckInterval)
        #expect(setup.page.looks - looksBefore == checks) // one look a check
        #expect(setup.clock.now.timeIntervalSince(started) < WebAppControl.keyWait + WebAppControl.firstLookWait)
    }

    @Test("learning is reported as it goes, starting with where it stands")
    func updates() async {
        let setup = Setup()
        setup.showPage()
        var updates = setup.player.learningUpdates().makeAsyncIterator()
        #expect(await updates.next() == .learning(hasPlayed: false))
        setup.page.set(1, label: "Pause")
        setup.page.sound = true
        _ = await setup.player.markPlaying()
        #expect(await updates.next() == .learning(hasPlayed: true))
        setup.page.set(1, label: "Play")
        _ = await setup.player.markPaused()
        #expect(await updates.next() == .learned)
    }

    @Test("It's Playing while it can't be heard (its page then unread), or It's Paused with nothing changed, doesn't move it on")
    func refusedClicks() async {
        let setup = Setup()
        setup.showPage()
        #expect(await setup.player.markPaused() == .notLearning) // It's Playing comes first
        let looks = setup.page.looks
        #expect(await setup.player.markPlaying() == .notHeard)
        #expect(setup.page.looks == looks) // silent: its page isn't read
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))

        setup.page.set(1, label: "Pause")
        setup.page.sound = true
        #expect(await setup.player.markPlaying() == .noted)
        #expect(await setup.player.markPaused() == .nothingChanged) // not paused yet
        #expect(setup.player.learningStatus == .learning(hasPlayed: true))
        setup.page.set(1, label: "Play")
        #expect(await setup.player.markPaused() == .noted)
        #expect(await setup.player.markPlaying() == .notLearning) // learned: nothing to tell
    }

    @Test("a page AutoHush can't read (not running, no window, buttons without words) is said so, and It's Paused then starts over")
    func cantSeePage() async {
        let notRunning = Setup(running: false)
        #expect(await notRunning.player.markPlaying() == .cantSeePage)

        let setup = Setup()
        setup.page.sound = true
        setup.page.hasWindow = false
        #expect(await setup.player.markPlaying() == .cantSeePage)

        // A window macOS restored at login: buttons, but without their words.
        setup.page.hasWindow = true
        setup.page.buttonsByNumber = Dictionary(uniqueKeysWithValues: (1...20).map { ($0, FakeWebPage.Button(label: "", place: Places.main)) })
        #expect(await setup.player.markPlaying() == .cantSeePage)
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))

        setup.showPage("Pause")
        #expect(await setup.player.markPlaying() == .noted)
        setup.page.hasWindow = false // the window was closed before It's Paused
        #expect(await setup.player.markPaused() == .cantSeePage)
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))
    }

    @Test("a page never read before answers its first look with nothing: It's Playing looks again, and takes it")
    func firstLookAtAPage() async {
        let setup = Setup()
        setup.page.sound = true
        setup.showPage("Pause")
        setup.page.blankLooks = 1 // the web app just opened: WebKit builds the page for Accessibility at the first look
        #expect(await setup.player.markPlaying() == .noted)
        #expect(setup.player.learningStatus == .learning(hasPlayed: true))
    }

    @Test("a small page, with only a few buttons that have words, can be learned")
    func smallPage() async {
        let setup = Setup()
        setup.page.sound = true
        setup.page.buttonsByNumber = [1: .init(label: "Pause", place: Places.playerBar),
                                      2: .init(label: "Volume", place: Places.playerBar),
                                      3: .init(label: "", place: Places.main)]
        #expect(await setup.player.markPlaying() == .noted)
        setup.page.set(1, label: "Play")
        #expect(await setup.player.markPaused() == .noted)
        #expect(setup.player.learningStatus == .learned)
    }

    @Test("while it learns, the observer's silent reads are reused, and a web app that's heard plays without a look for windows")
    func polledWhileLearning() async {
        let setup = Setup()
        #expect(await setup.player.polledPlayerState() == .paused)
        let looks = setup.page.windowLooks
        setup.clock.advance(1)
        #expect(await setup.player.polledPlayerState() == .paused)
        #expect(setup.page.windowLooks == looks) // silent: the last state
        setup.page.sound = true
        #expect(await setup.player.polledPlayerState() == .playing)
        #expect(setup.page.windowLooks == looks) // heard: it plays
        #expect(setup.page.looks == 0)
    }

    @Test("while it learns, a web app without a window is stopped, and windows aren't looked for again for a while")
    func learningWithoutWindow() async {
        let setup = Setup()
        setup.page.hasWindow = false
        #expect(await setup.player.playerState() == .stopped)
        let looks = setup.page.windowLooks
        setup.clock.advance(1)
        #expect(await setup.player.playerState() == .stopped)
        #expect(setup.page.windowLooks == looks) // waits before looking again
        setup.page.hasWindow = true
        setup.clock.advance(WebAppControl.noWindowPause)
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.page.looks == 0) // the page itself is never read while learning
    }

    @Test("It's Paused more than a minute after It's Playing is too late: it starts over; so does restarting")
    func pauseTooLate() async {
        let setup = Setup()
        setup.showPage("Pause")
        setup.page.sound = true
        _ = await setup.player.markPlaying()
        setup.page.set(1, label: "Play")
        setup.clock.advance(LearningStatus.pauseWait + 1)
        #expect(await setup.player.markPaused() == .tooLate)
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))
        #expect(setup.store.recipe(for: Self.app.bundleID) == nil)

        setup.page.set(1, label: "Pause")
        _ = await setup.player.markPlaying()
        #expect(setup.player.learningStatus == .learning(hasPlayed: true))
        #expect(await setup.player.restartLearning())
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))
        #expect(await setup.player.restartLearning() == false) // nothing to start over
        setup.page.set(1, label: "Play")
        #expect(await setup.player.markPaused() == .notLearning)
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

    @Test("learning again keeps the button until It's Playing is taken: then it's forgotten, a mute lifted, and it's learned afresh from the user's clicks")
    func learnAgain() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Pause")
        setup.page.buttonsByNumber[1]?.isEnabled = false
        try await setup.player.pause() // an ad: muted in place of a pause
        #expect(setup.muter.muted == [4242])

        await setup.player.learnAgain()
        #expect(setup.player.learningStatus == .relearning)
        #expect(setup.player.learningStatus.isLearned)
        #expect(setup.store.recipe(for: Self.app.bundleID) == Self.learned)
        #expect(setup.muter.muted == [4242]) // still standing in for the pause

        // It's Playing while it can't be heard isn't taken: nothing is forgotten.
        #expect(await setup.player.markPlaying() == .notHeard)
        #expect(setup.player.learningStatus == .relearning)
        #expect(setup.store.recipe(for: Self.app.bundleID) == Self.learned)

        // Taken: what it learned goes. Learned again, its words the other way round.
        setup.page.buttonsByNumber[1]?.isEnabled = true
        setup.page.set(1, label: "Pausar")
        setup.page.sound = true
        #expect(await setup.player.markPlaying() == .noted)
        #expect(setup.player.learningStatus == .learning(hasPlayed: true))
        #expect(setup.store.recipe(for: Self.app.bundleID) == nil)
        #expect(setup.muter.muted.isEmpty)
        setup.page.set(1, label: "Reproducir")
        #expect(await setup.player.markPaused() == .noted)
        #expect(setup.player.learningStatus == .learned)
        #expect(setup.store.recipe(for: Self.app.bundleID)?.playLabel == "Reproducir")
        #expect(setup.store.recipe(for: Self.app.bundleID)?.pauseLabel == "Pausar")
    }

    @Test("asked to learn again, it's still controlled with what it learned; kept, it's learned as before")
    func keepLearned() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Pause")
        await setup.player.learnAgain()
        try await setup.player.pause() // the learned button, still
        #expect(setup.page.presses == [1])

        await setup.player.keepLearned() // the learning window closed before It's Playing
        #expect(setup.player.learningStatus == .learned)
        #expect(setup.store.recipe(for: Self.app.bundleID) == Self.learned)
        #expect(await setup.player.markPlaying() == .notLearning)

        // Never learned: learning again just starts over.
        let fresh = Setup()
        await fresh.player.learnAgain()
        #expect(fresh.player.learningStatus == .learning(hasPlayed: false))
        await fresh.player.keepLearned()
        #expect(fresh.player.learningStatus == .learning(hasPlayed: false))
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

    @Test("after a sleep, an ad's mute ends in a real pause once the song plays, and nothing plays it again")
    func forgottenMuteEndsInPause() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Play")
        setup.page.sound = true
        setup.probe.audible = true
        #expect(await setup.player.muteIfPlayingAnyway())

        await setup.player.forgetPause()
        #expect(!(await setup.player.muteIfPlayingAnyway())) // no longer a pause AutoHush holds
        #expect(await setup.player.playerState() == .paused) // the ad still plays
        #expect(setup.muter.muted == [4242])

        setup.page.set(1, label: "Pause") // the song starts after the ad
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.page.presses == [1])
        #expect(setup.muter.muted.isEmpty)
    }

    @Test("after a sleep, a mute is lifted once the page is silent, and when its pause doesn't take")
    func forgottenMuteLifted() async throws {
        let silent = Setup(recipe: Self.learned)
        silent.showPage("Play")
        silent.page.sound = true
        silent.probe.audible = true
        #expect(await silent.player.muteIfPlayingAnyway())
        await silent.player.forgetPause()
        silent.page.sound = false
        _ = await silent.player.playerState()
        #expect(silent.muter.muted.isEmpty)
        #expect(silent.page.presses.isEmpty)

        let ignored = Setup(recipe: Self.learned)
        ignored.showPage("Pause")
        ignored.page.onPress = { _, _ in }
        try await ignored.player.pause() // muted instead
        #expect(ignored.muter.muted == [4242])
        await ignored.player.forgetPause()
        _ = await ignored.player.playerState() // pressed again, and still not followed
        #expect(ignored.page.presses == [1, 1])
        #expect(ignored.muter.muted.isEmpty)
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
        await TestWait.until { setup.muter.muted.isEmpty }
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

    @Test("with two windows, the one whose button says the music plays is pressed")
    func twoWindowsPlayingFirst() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showTwoWindows("Play", "Pause")
        #expect(await setup.player.playerState() == .playing)
        try await setup.player.pause()
        #expect(setup.page.presses == [21])
        try await setup.player.play()
        #expect(setup.page.presses == [21, 21])
    }

    @Test("music moving to a second window is followed there: paused, played, and never muted")
    func twoWindowsMusicMoves() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.probe.audible = true
        setup.showTwoWindows("Play", "Play")
        #expect(await setup.player.playerState() == .paused) // the first window's button

        // The user plays the second window.
        setup.page.set(21, label: "Pause")
        setup.page.sound = true
        #expect(await setup.player.playerState() == .playing)
        #expect(!(await setup.player.muteIfPlayingAnyway()))
        try await setup.player.pause()
        #expect(setup.page.presses == [21])
        #expect(setup.muter.log.isEmpty)
        #expect(setup.probe.listens == 0)
        try await setup.player.play()
        #expect(setup.page.presses == [21, 21])
    }

    @Test("other windows are looked at only while the web app is heard, and every 2 s at most")
    func twoWindowsLookedAtSparingly() async {
        let setup = Setup(recipe: Self.learned)
        setup.showTwoWindows("Play", "Play")
        #expect(await setup.player.playerState() == .paused)
        let looks = setup.page.looks
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.page.looks == looks) // silent: nothing else plays

        setup.page.sound = true // a pause's silent tail, or an ad
        setup.clock.advance(WebAppControl.otherWindowsInterval)
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.page.looks == looks + 1)
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.page.looks == looks + 1)
        setup.clock.advance(WebAppControl.otherWindowsInterval)
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.page.looks == looks + 2)
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

    @Test("with no window, each look waits twice as long, up to a minute; a web app with its sound on is looked at at once")
    func noWindowBacksOff() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage()
        setup.page.hasWindow = false
        #expect(await setup.player.playerState() == .stopped)
        setup.clock.advance(WebAppControl.noWindowPause)
        _ = await setup.player.playerState() // the second look
        let looks = setup.page.looks
        setup.clock.advance(WebAppControl.noWindowPause)
        _ = await setup.player.playerState()
        #expect(setup.page.looks == looks) // it waits 10 s now
        setup.clock.advance(WebAppControl.noWindowPause)
        _ = await setup.player.playerState()
        #expect(setup.page.looks == looks + 1)

        for _ in 0..<8 { // it never waits more than a minute
            setup.clock.advance(WebAppControl.noWindowPauseLimit)
            _ = await setup.player.playerState()
        }
        #expect(setup.page.looks == looks + 9)

        setup.page.sound = true
        setup.page.hasWindow = true
        #expect(await setup.player.playerState() == .paused)
    }

    @Test("the observer's reads ask the page less while the web app is silent; its sound, or AutoHush deciding, reads it at once")
    func polledReadsWhileSilent() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Play")
        #expect(await setup.player.polledPlayerState() == .paused)
        let reads = setup.page.buttonReads
        setup.clock.advance(1)
        #expect(await setup.player.polledPlayerState() == .paused)
        #expect(setup.page.buttonReads == reads) // silent and paused: the last state

        setup.page.set(1, label: "Pause") // played without sound yet (loading)
        #expect(await setup.player.playerState() == .playing) // a decision reads afresh
        setup.page.set(1, label: "Play")
        _ = await setup.player.playerState()

        setup.clock.advance(WebAppControl.quietReadInterval)
        let before = setup.page.buttonReads
        _ = await setup.player.polledPlayerState()
        #expect(setup.page.buttonReads > before) // read again after a while

        setup.page.set(1, label: "Pause")
        setup.page.sound = true
        #expect(await setup.player.polledPlayerState() == .playing) // the sound came on
    }

    @Test("a button missing for a minute while the web app is heard is learned again, keeping the old place")
    func relearns() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage()
        // The site shows another layout, its Play/Pause elsewhere, and plays.
        setup.page.buttonsByNumber[1] = .init(label: "Pause", place: Places.fullScreen)
        setup.page.sound = true
        #expect(await setup.player.playerState() == .unknown)
        setup.clock.advance(WebAppControl.missingBeforeLearning)
        _ = await setup.player.playerState()
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))

        // It's Playing, the user pauses it, It's Paused.
        #expect(await setup.player.markPlaying() == .noted)
        setup.page.set(1, label: "Play")
        #expect(await setup.player.markPaused() == .noted)
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.player.learningStatus == .learned)
        #expect(setup.store.recipe(for: Self.app.bundleID)?.places == [Places.fullScreen, Places.playerBar])
    }

    @Test("a missing button that turns up again ends the learning")
    func buttonBack() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage()
        setup.page.buttonsByNumber[1] = .init(label: "Pause", place: Places.fullScreen)
        setup.page.sound = true
        _ = await setup.player.playerState()
        setup.clock.advance(WebAppControl.missingBeforeLearning)
        _ = await setup.player.playerState()
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))
        setup.page.buttonsByNumber[1] = .init(label: "Pause", place: Places.playerBar)
        #expect(await setup.player.playerState() == .playing)
        #expect(setup.player.learningStatus == .learned)
    }

    @Test("learning again while the button is missing, then kept (the window closed): once it's back, it's learned, not learning again")
    func keptWhileMissing() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage()
        await setup.player.learnAgain()
        #expect(setup.player.learningStatus == .relearning)
        setup.page.buttonsByNumber[1] = .init(label: "Pause", place: Places.fullScreen)
        setup.page.sound = true
        _ = await setup.player.playerState()
        setup.clock.advance(WebAppControl.missingBeforeLearning)
        _ = await setup.player.playerState()
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))

        await setup.player.keepLearned()
        setup.page.buttonsByNumber[1] = .init(label: "Pause", place: Places.playerBar)
        #expect(await setup.player.playerState() == .playing)
        #expect(setup.player.learningStatus == .learned)
        #expect(await setup.player.markPlaying() == .notLearning) // nothing asked any more
    }

    @Test("the button counts as missing only while the web app is heard: a fresh page without its player bar stays learned, and a silence starts the minute again")
    func missingOnlyWhileHeard() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage()
        setup.page.buttonsByNumber[1] = nil // a fresh YouTube Music window: no player bar until something plays
        #expect(await setup.player.playerState() == .unknown)
        setup.clock.advance(WebAppControl.missingBeforeLearning * 2)
        _ = await setup.player.playerState()
        #expect(setup.player.learningStatus == .learned)

        // Heard, but its button is nowhere: half a minute, a silence, half a minute.
        setup.page.sound = true
        _ = await setup.player.playerState()
        setup.clock.advance(WebAppControl.missingBeforeLearning / 2)
        _ = await setup.player.playerState()
        setup.page.sound = false
        setup.clock.advance(1)
        _ = await setup.player.playerState()
        setup.page.sound = true
        _ = await setup.player.playerState()
        setup.clock.advance(WebAppControl.missingBeforeLearning / 2)
        _ = await setup.player.playerState()
        #expect(setup.player.learningStatus == .learned)
        setup.clock.advance(WebAppControl.missingBeforeLearning / 2)
        _ = await setup.player.playerState()
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))
    }

    @Test("a silent page without its button is looked at only every 5 s by the observer; its sound coming on, at once")
    func polledLooksWithoutButton() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage()
        setup.page.buttonsByNumber[1] = nil
        #expect(await setup.player.polledPlayerState() == .unknown)
        let looks = setup.page.looks
        setup.clock.advance(1)
        #expect(await setup.player.polledPlayerState() == .unknown)
        #expect(setup.page.looks == looks)
        setup.clock.advance(WebAppControl.quietReadInterval)
        _ = await setup.player.polledPlayerState()
        #expect(setup.page.looks > looks)

        setup.page.buttonsByNumber[1] = .init(label: "Pause", place: Places.playerBar)
        setup.page.sound = true
        #expect(await setup.player.polledPlayerState() == .playing)
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

/// The Now Playing app in tests: unknown (the key is pressed, as ever)
/// unless a test sets it.
final class NowPlayingBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _answer = NowPlayingApp.Answer.unknown
    var answer: NowPlayingApp.Answer {
        get { lock.withLock { _answer } }
        set { lock.withLock { _answer = newValue } }
    }
}

/// The keyboard's Play/Pause key in tests: counts its presses, and does
/// what a test says (by default, nothing: it reached another app).
final class PlayPauseKeyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var presses = 0
    private var action: (@Sendable () -> Void)?

    var count: Int { lock.withLock { presses } }
    var onPress: (@Sendable () -> Void)? {
        get { lock.withLock { action } }
        set { lock.withLock { action = newValue } }
    }

    func press() {
        let action = lock.withLock {
            presses += 1
            return self.action
        }
        action?()
    }
}
