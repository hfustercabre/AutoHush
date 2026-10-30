import Foundation
import Testing
import AutoHushKit
@testable import WebAppPlayers
import AutoHushTestSupport

extension SafariWebAppPlayerTests {
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

    @Test("after a sleep, a mute is lifted once the page is silent, and when its pause doesn't take or can't be made")
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

        let failing = Setup(recipe: Self.learned)
        failing.showPage("Play")
        failing.page.sound = true
        failing.probe.audible = true
        #expect(await failing.player.muteIfPlayingAnyway())
        await failing.player.forgetPause()
        failing.page.set(1, label: "Pause") // the song starts after the ad
        failing.page.pressFails = true
        _ = await failing.player.playerState()
        #expect(failing.muter.muted.isEmpty)
        #expect(failing.page.presses.isEmpty)
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
        await #expect(throws: MusicPlayerError.playerCommandFailed(.buttonDisabled)) { try await setup.player.pause() }
        #expect(setup.muter.muted.isEmpty)
        #expect(setup.page.presses.isEmpty)

        setup.player.allowTaps(true)
        try? await setup.player.pause()
        #expect(setup.muter.muted == [4242])
    }
}
