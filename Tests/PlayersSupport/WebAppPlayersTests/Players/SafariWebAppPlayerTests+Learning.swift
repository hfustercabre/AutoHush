import Foundation
import Testing
import AutoHushKit
@testable import WebAppPlayers
import AutoHushTestSupport
import PlayersTestSupport

extension SafariWebAppPlayerTests {
    @Test("it learns the button from the user saying it plays, then that it's paused; then reads the state from it")
    func learns() async throws {
        let setup = Setup()
        setup.showPage()
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))
        #expect(await setup.player.playerState() == .paused) // its sound is off
        let looks = setup.page.looks
        setup.clock.advance(by: 1)
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
        setup.clock.advance(by: 5)
        #expect(await setup.player.markPaused() == .noted)
        #expect(setup.player.learningStatus == .learned)
        #expect(setup.store.recipe(for: Self.app.bundleID) == Self.learned)
        #expect(setup.page.presses.isEmpty)

        setup.page.set(1, label: "Pause")
        #expect(await setup.player.playerState() == .playing)
    }

    @Test("after It's Playing it pauses itself with the Play/Pause key, learns the button that changed, and plays again with it, else with the key")
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

        // The page not following the learned button's press: the key plays it again.
        let ignoring = Setup()
        ignoring.showPage("Pause")
        ignoring.page.set(2, label: "Pause")
        ignoring.page.sound = true
        #expect(await ignoring.player.markPlaying() == .noted)
        ignoring.key.onPress = { [page = ignoring.page] in
            page.set(1, label: "Play")
            page.set(2, label: "Play")
        }
        ignoring.page.onPress = { _, _ in }
        #expect(await ignoring.player.pauseByItself() == .paused)
        #expect(ignoring.page.presses == [1])
        #expect(ignoring.key.count == 2)
    }

    @Test("SoundCloud: learned is its bar's Play current, among the player's controls, not a song's tile scrolled out of sight")
    func soundCloudsBar() async {
        let setup = Setup()
        let bar = ButtonPlace(path: ["AXGroup:AXLandmarkContentInfo"], distanceFromBottom: 24)
        var buttons: [Int: FakeWebPage.Button] = [
            1: .init(label: "Pause current", place: bar, withControls: true),
            2: .init(label: "Pause", place: ButtonPlace(path: ["AXGroup"], distanceFromBottom: -77), outOfSight: true),
        ]
        for number in 3..<14 { buttons[number] = .init(label: "Item \(number)", place: ButtonPlaces.main) }
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
        #expect(setup.key.count == 1) // not with the key
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
            let started = setup.clock.now
            #expect(await setup.player.pauseByItself() == .keyGoesElsewhere)
            #expect(setup.key.count == 0)
            #expect(setup.nowPlaying.asked == 2) // asked again a moment later
            #expect(setup.clock.now.timeIntervalSince(started) >= WebAppControl.nowPlayingRecheck)
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

    @Test("another app still Now Playing as the web app starts: asked again a moment later, the web app holds it and the key is pressed")
    func nowPlayingTakenLate() async {
        let setup = Setup()
        setup.showPage()
        setup.page.set(1, label: "Pause")
        setup.page.sound = true
        setup.nowPlaying.answers = [.process(pid_t.max - 1), .process(setup.pid.value)]
        #expect(await setup.player.markPlaying() == .noted)
        setup.key.onPress = { [page = setup.page] in page.set(1, label: "Play") }
        #expect(await setup.player.pauseByItself() == .paused)
        #expect(setup.nowPlaying.asked == 2)
        #expect(setup.key.count == 1)
        #expect(setup.player.learningStatus == .learned)
    }

    @Test("with the web app Now Playing, or no answer, Now Playing is asked once")
    func nowPlayingAskedOnce() async {
        for answer in [NowPlayingApp.Answer.process(4242), .unknown] {
            let setup = Setup()
            setup.showPage()
            setup.page.set(1, label: "Pause")
            setup.page.sound = true
            setup.nowPlaying.answer = answer
            #expect(await setup.player.markPlaying() == .noted)
            setup.key.onPress = { [page = setup.page] in page.set(1, label: "Play") }
            #expect(await setup.player.pauseByItself() == .paused)
            #expect(setup.nowPlaying.asked == 1)
        }
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
        setup.page.buttonsByNumber = Dictionary(uniqueKeysWithValues: (1...20).map { ($0, FakeWebPage.Button(label: "", place: ButtonPlaces.main)) })
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
        setup.page.buttonsByNumber = [1: .init(label: "Pause", place: ButtonPlaces.playerBar),
                                      2: .init(label: "Volume", place: ButtonPlaces.playerBar),
                                      3: .init(label: "", place: ButtonPlaces.main)]
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
        setup.clock.advance(by: 1)
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
        setup.clock.advance(by: 1)
        #expect(await setup.player.playerState() == .stopped)
        #expect(setup.page.windowLooks == looks) // waits before looking again
        setup.page.hasWindow = true
        setup.clock.advance(by: WebAppControl.noWindowPause)
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
        setup.clock.advance(by: LearningStatus.pauseWait + 1)
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
}
