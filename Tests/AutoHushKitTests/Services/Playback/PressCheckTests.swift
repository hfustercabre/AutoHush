import Foundation
import Testing
import AutoHushTestSupport
@testable import AutoHushKit

@Suite("PressCheck", .waitsTimeLimit)
struct PressCheckTests {
    private func check(_ player: any MusicPlayer) -> PressCheck {
        PressCheck(player: player, sleep: { _ in })
    }

    @Test("a press the player follows is made once")
    func followed() async throws {
        let player = MockMusicPlayer(state: .playing)
        try await check(player).press(to: .paused)
        #expect(await player.commandLog == ["pause"])
        try await check(player).press(to: .playing)
        #expect(await player.commandLog == ["pause", "play"])
    }

    @Test("a press the player missed is made once more, and then it took")
    func missedOnce() async throws {
        let player = MockMusicPlayer(state: .paused)
        await player.setIgnoredPresses(1)
        try await check(player).press(to: .playing)
        #expect(await player.commandLog == ["play", "play"])
        #expect(await player.state == .playing)
    }

    @Test("a press the player ignores twice fails, said so")
    func ignored() async throws {
        let player = MockMusicPlayer(state: .playing)
        await player.setIgnoredPresses(2)
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressIgnored)) {
            try await check(player).press(to: .paused)
        }
        #expect(await player.pauseCallCount == 2)
    }

    @Test("stopped counts as paused")
    func stopped() async throws {
        let player = MockMusicPlayer(state: .stopped)
        try await check(player).press(to: .paused)
        #expect(await player.pauseCallCount == 1)
    }

    @Test("while the player doesn't answer, nothing can be told: no second press, no failure")
    func unanswered() async throws {
        let player = MockMusicPlayer(state: .playing)
        await player.setIgnoredPresses(1)
        await player.setUnansweredStateQueries(1_000)
        try await check(player).press(to: .paused)
        #expect(await player.pauseCallCount == 1)
    }

    @Test("the wait is the clock's: slow reads end it sooner than thirty reads would")
    func clock() async throws {
        let player = MockMusicPlayer(state: .playing)
        await player.setIgnoredPresses(2)
        let clock = ManualClock(start: Date(timeIntervalSince1970: 0))
        // Each read takes a second, as a slow app's answer.
        await player.setBeforeStateAnswer { clock.advance(by: 1) }
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressIgnored)) {
            try await PressCheck(player: player, sleep: { _ in }, now: { clock.now }).press(to: .paused)
        }
        #expect(await player.stateQueryCount <= 10)
    }

    @Test("a press made by a closure is judged by another")
    func closures() async throws {
        let player = MockMusicPlayer(state: .playing)
        let check = PressCheck(name: "Jukebox", press: { target in
            if target == .paused { try await player.pause() } else { try await player.play() }
        }, state: { await player.playerState() }, sleep: { _ in })
        try await check.press(to: .paused)
        #expect(await player.commandLog == ["pause"])
    }

    @Test("a toggle judged by another sign is made once: shown after the usual wait, it took; never shown, it fails")
    func toggle() async throws {
        let player = MockMusicPlayer(state: .paused)
        let clock = ManualClock(start: Date(timeIntervalSince1970: 0))
        // Heard 5 s after its press, as Qobuz buffering.
        let heardAt = Date(timeIntervalSince1970: 5)
        let toggle = { (shows: Bool) in
            PressCheck(name: "Jukebox", isToggle: true, press: { _ in try await player.play() },
                       state: { shows && clock.now >= heardAt ? .playing : .paused }, sleep: { clock.advance(by: $0) },
                       now: { clock.now })
        }
        try await toggle(true).press(to: .playing)
        #expect(await player.playCallCount == 1)
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressIgnored)) { try await toggle(false).press(to: .playing) }
        #expect(await player.playCallCount == 2) // once more, for the second toggle only
    }

    @Test("a player that checks its own presses isn't checked again")
    func checksItself() async throws {
        let player = MockMusicPlayer(state: .playing, checksItsPresses: true)
        await player.setIgnoredPresses(1) // a press checked again would be made twice
        try await check(player).press(to: .paused)
        #expect(await player.pauseCallCount == 1)
        #expect(await player.stateQueryCount == 0)
    }
}
