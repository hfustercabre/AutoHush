import Foundation
import Testing
import AutoHushKit
@testable import WebAppPlayers
import AutoHushTestSupport
import PlayersTestSupport

extension SafariWebAppPlayerTests {
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
        setup.clock.advance(by: WebAppControl.otherWindowsInterval)
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.page.looks == looks + 1)
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.page.looks == looks + 1)
        setup.clock.advance(by: WebAppControl.otherWindowsInterval)
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
        setup.clock.advance(by: 1)
        #expect(await setup.player.playerState() == .stopped)
        #expect(setup.page.looks == looks)
        setup.page.hasWindow = true
        setup.clock.advance(by: WebAppControl.noWindowPause)
        #expect(await setup.player.playerState() == .paused)
    }

    @Test("with no window, each look waits twice as long, up to a minute; a web app with its sound on is looked at at once")
    func noWindowBacksOff() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage()
        setup.page.hasWindow = false
        #expect(await setup.player.playerState() == .stopped)
        setup.clock.advance(by: WebAppControl.noWindowPause)
        _ = await setup.player.playerState() // the second look
        let looks = setup.page.looks
        setup.clock.advance(by: WebAppControl.noWindowPause)
        _ = await setup.player.playerState()
        #expect(setup.page.looks == looks) // it waits 10 s now
        setup.clock.advance(by: WebAppControl.noWindowPause)
        _ = await setup.player.playerState()
        #expect(setup.page.looks == looks + 1)

        for _ in 0..<8 { // it never waits more than a minute
            setup.clock.advance(by: WebAppControl.noWindowPauseLimit)
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
        setup.clock.advance(by: 1)
        #expect(await setup.player.polledPlayerState() == .paused)
        #expect(setup.page.buttonReads == reads) // silent and paused: the last state

        setup.page.set(1, label: "Pause") // played without sound yet (loading)
        #expect(await setup.player.playerState() == .playing) // a decision reads afresh
        setup.page.set(1, label: "Play")
        _ = await setup.player.playerState()

        setup.clock.advance(by: WebAppControl.quietReadInterval)
        let before = setup.page.buttonReads
        _ = await setup.player.polledPlayerState()
        #expect(setup.page.buttonReads > before) // read again after a while

        setup.page.set(1, label: "Pause")
        setup.page.sound = true
        #expect(await setup.player.polledPlayerState() == .playing) // the sound came on
    }

    @Test("a button missing for a minute while the web app is heard is learned again, keeping the old place; Learn Again meanwhile starts over")
    func relearns() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage()
        // The site shows another layout, its Play/Pause elsewhere, and plays.
        setup.page.buttonsByNumber[1] = .init(label: "Pause", place: Places.fullScreen)
        setup.page.sound = true
        #expect(await setup.player.playerState() == .unknown)
        setup.clock.advance(by: WebAppControl.missingBeforeLearning)
        _ = await setup.player.playerState()
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))

        // It's Playing, the user pauses it, It's Paused.
        #expect(await setup.player.markPlaying() == .noted)
        setup.page.set(1, label: "Play")
        #expect(await setup.player.markPaused() == .noted)
        #expect(await setup.player.playerState() == .paused)
        #expect(setup.player.learningStatus == .learned)
        #expect(setup.store.recipe(for: Self.app.bundleID)?.places == [Places.fullScreen, Places.playerBar])

        // Missing again, and It's Playing taken: Learn Again starts that learning over.
        setup.page.buttonsByNumber[1] = nil
        _ = await setup.player.playerState()
        setup.clock.advance(by: WebAppControl.missingBeforeLearning)
        _ = await setup.player.playerState()
        #expect(await setup.player.markPlaying() == .noted)
        #expect(setup.player.learningStatus == .learning(hasPlayed: true))
        await setup.player.learnAgain()
        #expect(setup.player.learningStatus == .learning(hasPlayed: false))
    }

    @Test("a missing button that turns up again ends the learning")
    func buttonBack() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage()
        setup.page.buttonsByNumber[1] = .init(label: "Pause", place: Places.fullScreen)
        setup.page.sound = true
        _ = await setup.player.playerState()
        setup.clock.advance(by: WebAppControl.missingBeforeLearning)
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
        setup.clock.advance(by: WebAppControl.missingBeforeLearning)
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
        setup.clock.advance(by: WebAppControl.missingBeforeLearning * 2)
        _ = await setup.player.playerState()
        #expect(setup.player.learningStatus == .learned)

        // Heard, but its button is nowhere: half a minute, a silence, half a minute.
        setup.page.sound = true
        _ = await setup.player.playerState()
        setup.clock.advance(by: WebAppControl.missingBeforeLearning / 2)
        _ = await setup.player.playerState()
        setup.page.sound = false
        setup.clock.advance(by: 1)
        _ = await setup.player.playerState()
        setup.page.sound = true
        _ = await setup.player.playerState()
        setup.clock.advance(by: WebAppControl.missingBeforeLearning / 2)
        _ = await setup.player.playerState()
        #expect(setup.player.learningStatus == .learned)
        setup.clock.advance(by: WebAppControl.missingBeforeLearning / 2)
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
        setup.clock.advance(by: 1)
        #expect(await setup.player.polledPlayerState() == .unknown)
        #expect(setup.page.looks == looks)
        setup.clock.advance(by: WebAppControl.quietReadInterval)
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
        setup.clock.advance(by: WebAppControl.missingBeforeLearning * 2)
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
        await #expect(throws: MusicPlayerError.playerCommandFailed(.buttonDisabled)) { try await setup.player.pause() }
        #expect(setup.page.presses.isEmpty)
    }

    @Test("a disabled Play means there's nothing to play")
    func disabled() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage()
        setup.page.buttonsByNumber[1]?.isEnabled = false
        #expect(await setup.player.playerState() == .stopped)
    }

    @Test("not running, or without Accessibility, it can't be controlled; not learned yet, it can")
    func access() async throws {
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
        try await Setup().player.verifyControlAccess() // not learned is fine: it learns while running
    }
}
