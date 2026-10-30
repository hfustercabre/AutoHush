import Foundation
import Testing
import AutoHushKit
@testable import WebAppPlayers
import AutoHushTestSupport
import PlayersTestSupport

extension SafariWebAppPlayerTests {
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

    @Test("a press after which the site puts a new button in place (YouTube Music's Pause): the new one tells")
    func replacedButton() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Play")
        setup.page.onPress = { page, number in
            var buttons = page.buttonsByNumber
            guard var button = buttons.removeValue(forKey: number) else { return }
            button.label = "Pause"
            buttons[number + 10] = button
            page.buttonsByNumber = buttons
        }
        try await setup.player.play()
        #expect(setup.page.presses == [1])
        #expect(await setup.player.playerState() == .playing)
    }

    @Test("a press the page doesn't follow is an error when the web app can't be muted either")
    func ignoredPress() async throws {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Pause")
        setup.page.onPress = { _, _ in }
        setup.muter.canMute = false
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressIgnored)) { try await setup.player.pause() }
        #expect(setup.page.presses == [1])
    }

    @Test("a press that can't be made mutes it instead; playing unmutes it, pressing nothing")
    func failedPressMutes() async throws {
        let failing = Setup(recipe: Self.learned)
        failing.showPage("Pause")
        failing.page.pressFails = true
        try await failing.player.pause()
        #expect(failing.muter.muted == [4242])
        #expect(await failing.player.playerState() == .paused)
        try await failing.player.play()
        #expect(failing.muter.log == ["mute 4242", "unmute 4242"])
    }

    @Test("a press that can't be made is an error when the web app can't be muted either")
    func failedPressUnmutable() async {
        let failing = Setup(recipe: Self.learned)
        failing.showPage("Pause")
        failing.page.pressFails = true
        failing.muter.canMute = false
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressFailed)) { try await failing.player.pause() }
        #expect(failing.muter.log.isEmpty)
    }

    @Test("another app's page (Electron's, CEF's): it's an app, controlled the same way")
    func otherAppsPage() async throws {
        let setup = Setup(recipe: Self.learned, kind: .app)
        #expect(setup.player.kind == .app)
        setup.showPage("Pause")
        try await setup.player.pause()
        #expect(setup.page.presses == [1])
    }

    @Test("a Chromium or Flutter page out of sight keeps an old word: its sound tells instead")
    func staleWords() async {
        let setup = Setup(recipe: Self.learned)
        setup.showPage("Pause")
        setup.page.wordsCurrent = false
        setup.page.sound = false
        #expect(await setup.player.playerState() == .paused)
        setup.page.sound = true
        #expect(await setup.player.playerState() == .playing)
        setup.page.wordsCurrent = true
        setup.page.set(1, label: "Play")
        #expect(await setup.player.playerState() == .paused)
    }

    @Test("an app that plays through its browser (a Chromium web app) isn't muted: a refused pause is an error")
    func noMutingThroughTheBrowser() async {
        let setup = Setup(recipe: Self.learned, canMute: false)
        setup.showPage("Pause")
        setup.page.onPress = { _, _ in }
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressIgnored)) { try await setup.player.pause() }
        #expect(setup.muter.muted.isEmpty)
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
}
