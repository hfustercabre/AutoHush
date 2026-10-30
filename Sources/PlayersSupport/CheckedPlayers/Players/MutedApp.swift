import AppKit
import Foundation
import os
import AutoHushKit

/// An app added with Add an App that's muted instead of paused (Mute It
/// Instead, `PlayerSetup.Way.mute`): its own sound is muted, which needs
/// Audio Recording, so not in AntiDot mode. Whether it plays is its
/// keep-awake assertion once it has shown one (Qobuz holds one only while
/// it plays), else its sound output. A mute stands for a pause until the
/// user plays it again or stops it (`MutedAppState`), and always takes.
actor MutedApp: AddedAppPlayer, FadelessMusicPlayer, PolledMusicPlayer {
    nonisolated let setup: PlayerSetup
    nonisolated var controlPermission: Permission { .systemAudioRecording }
    nonisolated var releasesOnQuit: Bool { true }
    nonisolated var pausesByMuting: Bool { true }
    /// Only its sound tells how it is.
    nonisolated var needsAudioLevels: Bool { true }

    /// Its running process, if it runs: AutoHush never launches it.
    private let processIdentifier: @Sendable () -> pid_t?
    /// Whether its sound output is on (a process of its own plays).
    private let soundOn: @Sendable (pid_t) -> Bool
    private let muter: any AudioMuting
    /// The mute, and what it stands for.
    private var hush = MutedAppState()
    private var mutedPID: pid_t?
    private let assertions: PlaybackAssertions
    /// What a stop is timed by (`MutedAppState.stopTime`).
    private let clock: @Sendable () -> Date
    private nonisolated let tapsAllowed = OSAllocatedUnfairLock(initialState: true)
    /// Whether Audio Recording lets a tap mute it (`AudioCapturePermission.allowsTaps`).
    private let audioRecordingAllowed: @Sendable () -> Bool
    private let logger = AutoHushLogger(category: "MutedApp")
    /// Its taps, process lists and keep-awake assertions are read and made
    /// here, never on Swift's shared threads (DEVELOPMENT.md).
    private let queue = DispatchQueue(label: "AutoHush.MutedApp", qos: .userInitiated)

    init(setup: PlayerSetup,
         processIdentifier: (@Sendable () -> pid_t?)? = nil,
         muter: any AudioMuting = ProcessTapMuter(),
         soundOn: (@Sendable (pid_t) -> Bool)? = nil,
         assertionsHeld: @escaping @Sendable (pid_t) -> Set<PowerAssertion> = PlaybackAssertions.read,
         clock: @escaping @Sendable () -> Date = { Date() },
         audioRecordingAllowed: @escaping @Sendable () -> Bool = { AudioCapturePermission.allowsTaps }) {
        self.setup = setup
        self.audioRecordingAllowed = audioRecordingAllowed
        self.processIdentifier = processIdentifier ?? { [bundleID = setup.bundleID] in
            NSRunningApplication.running(bundleID)?.processIdentifier
        }
        self.muter = muter
        let sound = OwnedAudioProcesses()
        self.soundOn = soundOn ?? { sound.isPlayingSound(appPID: $0) }
        self.assertions = PlaybackAssertions(read: assertionsHeld)
        self.clock = clock
    }

    func verifyControlAccess() async throws {
        guard processIdentifier() != nil else { throw MusicPlayerError.playerNotRunning }
    }

    /// Its state is its sound output's or its keep-awake assertion's, never
    /// its own (`MusicPlayer.statesItself`).
    func statesItself() async -> Bool { false }

    func playerState() async -> PlayerState {
        guard let pid = processIdentifier() else {
            // Quit while muted: what the mute stood for goes with it.
            await endMute()
            return .notRunning
        }
        // Opened again since it was muted: that mute was the old process's.
        if let mutedPID, mutedPID != pid { await endMute() }
        let playing = await playsNow(pid)
        let (state, unmute) = hush.read(playing: playing, at: clock())
        if unmute {
            await liftMute()
            logger.notice("\(self.name, privacy: .public): unmuted, as it was played again (or stopped after a sleep)")
        }
        return state
    }

    func pause() async throws {
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        // Without Audio Recording a tap mutes nothing: the mute fails, as
        // in AntiDot mode, rather than reading as taken (the user, 2026-10-20).
        guard tapsAllowed.withLock({ $0 }) else { throw MusicPlayerError.playerCommandFailed(.muteUnavailable) }
        // Noted before the mute is made: a release meanwhile lifts it, after
        // it, as the queue keeps their order, and the pause is off.
        mutedPID = pid
        let muter = muter, allowed = audioRecordingAllowed
        let muted = await queue.run { allowed() && muter.mute(appPID: pid) }
        guard muted, mutedPID == pid else {
            if mutedPID == pid { mutedPID = nil }
            throw MusicPlayerError.playerCommandFailed(.muteUnavailable)
        }
        hush.mute()
    }

    func play() async throws {
        await endMute()
    }

    /// Whether it plays now: its keep-awake assertion once it has held one,
    /// else its sound output (open while it plays, and for some apps paused too).
    private func playsNow(_ pid: pid_t) async -> Bool {
        let soundOn = soundOn, assertions = assertions
        return await queue.run { () -> Bool in
            switch assertions.state(of: pid, soundOn: { soundOn(pid) }) {
            case .playing: true
            case .paused: false
            default: soundOn(pid)
            }
        }
    }

    private func liftMute() async {
        guard let pid = mutedPID else { return }
        mutedPID = nil
        let muter = muter
        await queue.run { muter.unmute(appPID: pid) }
    }

    /// Unmuted, and nothing left of what the mute stood for.
    private func endMute() async {
        await liftMute()
        hush.unmute()
    }

    /// Lifts its mute without playing anything: as AutoHush quits, or once
    /// another player is chosen and AutoHush holds no pause in it.
    func release() async {
        await endMute()
    }

    /// Its mute stands for a pause (`pause()`), never for `muteIfPlayingAnyway`,
    /// which mutes nothing more: nothing to lift here.
    func releaseMute() async {}

    /// Not in AntiDot mode, which taps no sound: then it can't be muted,
    /// and a mute under way is lifted.
    nonisolated func allowTaps(_ allowed: Bool) {
        tapsAllowed.withLock { $0 = allowed }
        guard !allowed else { return }
        Task { await self.endMute() }
    }

    /// It reads as paused while muted: nothing more to mute.
    func muteIfPlayingAnyway() async -> Bool { false }

    /// The Mac slept: AutoHush no longer holds the pause the mute stands
    /// for. It's lifted once the app has been stopped for
    /// `MutedAppState.stopTime`, never while it plays.
    func forgetPause() async {
        guard hush.isMuted else { return }
        hush.forget()
        _ = await playerState()
    }
}
