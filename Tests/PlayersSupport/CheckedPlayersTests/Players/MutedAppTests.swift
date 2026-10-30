import Foundation
import Testing
@testable import CheckedPlayers
import AutoHushKit
import AutoHushTestSupport

/// A keep-awake assertion as a player holds one while it plays.
private let playing: Set<PowerAssertion> = [PowerAssertion(.system, "Playing")]

@Suite("MutedApp", .waitsTimeLimit)
struct MutedAppTests {
    private let muted = PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox",
                                    appURL: URL(fileURLWithPath: "/Applications/Jukebox.app"), ways: [.mute])

    /// A muted app on stand-ins: its mute, whether it holds its keep-awake
    /// assertion (not yet), and the clock its stops are timed by.
    private func mutedApp() -> (player: MutedApp, muter: FakeMuter, held: Locked<Bool>, clock: ManualClock) {
        let muter = FakeMuter()
        let held = Locked(false)
        let clock = ManualClock()
        let player = MutedApp(setup: muted, processIdentifier: { 4242 }, muter: muter,
                              assertionsHeld: { _ in held.value ? playing : [] }, clock: { clock.now }, audioRecordingAllowed: { true })
        return (player, muter, held, clock)
    }

    @Test("muted instead of paused: a pause mutes it and it reads paused; a play unmutes it")
    func muting() async throws {
        let (player, muter, held, _) = mutedApp()
        #expect(player.pausesByMuting && player.needsAudioLevels && player.controlPermission == .systemAudioRecording && !player.canFade)
        held.value = true
        #expect(await player.playerState() == .playing)
        try await player.pause()
        #expect(muter.isMuted)
        #expect(await player.playerState() == .paused) // still plays, muted: our pause
        try await player.play()
        #expect(!muter.isMuted)
    }

    @Test("a muted app's keep-awake assertion, once seen, tells: without it, it's paused")
    func assertionTells() async {
        let (player, _, held, _) = mutedApp()
        held.value = true
        _ = await player.playerState() // its assertion seen
        held.value = false
        #expect(await player.playerState() == .paused)
    }

    @Test("muted, then stopped 3 s by the user and played again, a muted app is theirs to hear: unmuted")
    func unmutedOncePlayedAgain() async throws {
        let (player, muter, held, clock) = mutedApp()
        held.value = true
        _ = await player.playerState() // its assertion seen
        try await player.pause()
        held.value = false
        #expect(await player.playerState() == .paused)
        clock.advance(by: MutedAppState.stopTime)
        #expect(await player.playerState() == .paused)
        #expect(muter.isMuted)
        held.value = true
        #expect(await player.playerState() == .playing)
        #expect(!muter.isMuted)
    }

    @Test("after a sleep, a muted app is unmuted once it stops, not while it plays")
    func unmutedAfterSleepOnceStopped() async throws {
        let (player, muter, held, clock) = mutedApp()
        held.value = true
        _ = await player.playerState() // its assertion seen
        try await player.pause()
        await player.forgetPause() // the Mac slept: AutoHush no longer holds the pause
        #expect(muter.isMuted) // it plays on
        held.value = false
        #expect(await player.playerState() == .paused)
        clock.advance(by: MutedAppState.stopTime)
        #expect(await player.playerState() == .paused)
        #expect(!muter.isMuted) // stopped for 3 s: lifted
    }

    @Test("AntiDot mode lifts a muted app's mute, and it can't be muted then")
    func antiDotLiftsMute() async throws {
        let (player, muter, held, _) = mutedApp()
        held.value = true
        try await player.pause()
        player.allowTaps(false) // AntiDot mode: no taps, no mute
        await TestWait.until { !muter.isMuted }
        await #expect(throws: MusicPlayerError.playerCommandFailed(.muteUnavailable)) { try await player.pause() }
    }

    @Test("muted, then quit: what the mute stood for goes with it, also when it's opened again before a read sees it quit")
    func mutedThenQuit() async throws {
        let muter = FakeMuter()
        let running = Locked<pid_t?>(4242)
        let player = MutedApp(setup: muted, processIdentifier: { running.value }, muter: muter, assertionsHeld: { _ in playing }, audioRecordingAllowed: { true })
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
        let player = MutedApp(setup: muted, processIdentifier: { running.value }, muter: muter, assertionsHeld: { _ in playing }, audioRecordingAllowed: { true })
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
