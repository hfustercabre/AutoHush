import Foundation
import Testing
@testable import CheckedPlayers
import AutoHushKit
import AutoHushTestSupport

/// A keep-awake assertion as a player holds one while it plays.
private let playing: Set<PowerAssertion> = [PowerAssertion(.system, "Playing")]

@Suite("MutedApp")
struct MutedAppTests {
    private let muted = PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox",
                                    appURL: URL(fileURLWithPath: "/Applications/Jukebox.app"), ways: [.mute])

    @Test("muted instead of paused: a pause mutes it and it reads paused; a play unmutes it; once its assertion was seen, it tells; stopped 3 s by the user and played again, it's unmuted; after a sleep, unmuted once it stops, not while it plays; AntiDot mode lifts a mute")
    func muting() async throws {
        let muter = FakeMuter()
        let held = Locked(false)
        let clock = ManualClock()
        let player = MutedApp(setup: muted, processIdentifier: { 4242 }, muter: muter,
                              assertionsHeld: { _ in held.value ? playing : [] }, clock: { clock.now })
        #expect(player.pausesByMuting && player.needsAudioLevels && player.controlPermission == .systemAudioRecording && !player.canFade)
        held.value = true
        #expect(await player.playerState() == .playing)
        try await player.pause()
        #expect(muter.isMuted)
        #expect(await player.playerState() == .paused) // still plays, muted: our pause
        try await player.play()
        #expect(!muter.isMuted)
        held.value = false
        #expect(await player.playerState() == .paused) // its assertion seen: without it, it's paused

        // Muted, the user pauses it for 3 s, then plays it: theirs to hear.
        held.value = true
        try await player.pause()
        held.value = false
        #expect(await player.playerState() == .paused)
        clock.advance(by: MuteState.stopTime)
        #expect(await player.playerState() == .paused)
        #expect(muter.isMuted)
        held.value = true
        #expect(await player.playerState() == .playing)
        #expect(!muter.isMuted)

        try await player.pause()
        await player.forgetPause() // the Mac slept: AutoHush no longer holds the pause
        #expect(muter.isMuted) // it plays on
        held.value = false
        #expect(await player.playerState() == .paused)
        clock.advance(by: MuteState.stopTime)
        #expect(await player.playerState() == .paused)
        #expect(!muter.isMuted) // stopped for 3 s: lifted

        held.value = true
        try await player.pause()
        player.allowTaps(false) // AntiDot mode: no taps, no mute
        await TestWait.until { !muter.isMuted }
        #expect(!muter.isMuted)
        await #expect(throws: MusicPlayerError.playerCommandFailed(.muteUnavailable)) { try await player.pause() }
    }

    @Test("muted, then quit: what the mute stood for goes with it, also when it's opened again before a read sees it quit")
    func mutedThenQuit() async throws {
        let muter = FakeMuter()
        let running = Locked<pid_t?>(4242)
        let player = MutedApp(setup: muted, processIdentifier: { running.value }, muter: muter, assertionsHeld: { _ in playing })
        try await player.pause()
        #expect(muter.isMuted)
        running.value = nil
        #expect(await player.playerState() == .notRunning)
        #expect(!muter.isMuted)
        running.value = 4343 // opened again, playing: it's heard, not taken for paused
        #expect(await player.playerState() == .playing)
        try await player.pause()
        running.value = 4444 // quit and opened again within a read
        #expect(await player.playerState() == .playing)
        #expect(!muter.isMuted)
        try await player.pause()
        #expect(muter.isMuted)
    }

    @Test("released, a mute is lifted, whenever it's asked; it needs only to run")
    func releaseAndAccess() async throws {
        let muter = FakeMuter()
        let running = Locked<pid_t?>(4242)
        let player = MutedApp(setup: muted, processIdentifier: { running.value }, muter: muter, assertionsHeld: { _ in playing })
        try await player.verifyControlAccess()
        try await player.pause()
        #expect(player.releasesOnQuit)
        await player.release()
        #expect(!muter.isMuted)
        #expect(await player.playerState() == .playing)
        running.value = nil
        await #expect(throws: MusicPlayerError.playerNotRunning) { try await player.verifyControlAccess() }
    }
}
