import AppKit
import Foundation
import os
import AutoHushKit

/// An app added with Add an App that's muted instead of paused (Mute It
/// Instead, `PlayerSetup.Way.mute`): its own sound is muted, which needs
/// Audio Recording, so not in AntiDot mode. Whether it plays is its
/// keep-awake assertion once it has shown one (Qobuz holds one only while
/// it plays), else its sound output. A mute stands for a pause until the
/// user plays it again or stops it (`MuteState`), and always takes.
package actor MutedApp: AddedAppPlayer, FadelessMusicPlayer, PolledMusicPlayer {
    package nonisolated let setup: PlayerSetup
    package nonisolated var controlPermission: Permission { .systemAudioRecording }
    package nonisolated var releasesOnQuit: Bool { true }
    package nonisolated var pausesByMuting: Bool { true }
    /// Only its sound tells how it is.
    package nonisolated var needsAudioLevels: Bool { true }

    /// Its running process, if it runs: AutoHush never launches it.
    private let processIdentifier: @Sendable () -> pid_t?
    /// Whether its sound output is on (a process of its own plays).
    private let soundOn: @Sendable (pid_t) -> Bool
    private let muter: any AudioMuting
    /// The mute, and what it stands for.
    private var hush = MuteState()
    private var mutedPID: pid_t?
    private var assertions: PlaybackAssertions
    /// What a stop is timed by (`MuteState.stopTime`).
    private let clock: @Sendable () -> Date
    private nonisolated let tapsAllowed = OSAllocatedUnfairLock(initialState: true)
    private let logger = AutoHushLogger(category: "MutedApp")

    package init(setup: PlayerSetup,
                 processIdentifier: (@Sendable () -> pid_t?)? = nil,
                 muter: any AudioMuting = ProcessTapMuter(),
                 soundOn: (@Sendable (pid_t) -> Bool)? = nil,
                 assertionsHeld: @escaping @Sendable (pid_t) -> Set<PowerAssertion> = PlaybackAssertions.read,
                 clock: @escaping @Sendable () -> Date = { Date() }) {
        self.setup = setup
        self.processIdentifier = processIdentifier ?? { [bundleID = setup.bundleID] in
            NSRunningApplication.running(bundleID)?.processIdentifier
        }
        self.muter = muter
        let sound = OwnedAudioProcesses()
        self.soundOn = soundOn ?? { sound.isPlayingSound(appPID: $0) }
        self.assertions = PlaybackAssertions(read: assertionsHeld)
        self.clock = clock
    }

    package func verifyControlAccess() async throws {
        guard processIdentifier() != nil else { throw MusicPlayerError.playerNotRunning }
    }

    package func playerState() async -> PlayerState {
        guard let pid = processIdentifier() else {
            // Quit while muted: what the mute stood for goes with it.
            endMute()
            return .notRunning
        }
        // Opened again since it was muted: that mute was the old process's.
        if let mutedPID, mutedPID != pid { endMute() }
        let (state, unmute) = hush.read(playing: playsNow(pid), at: clock())
        if unmute {
            liftMute()
            logger.notice("\(self.name, privacy: .public): unmuted, as it was played again (or stopped after a sleep)")
        }
        return state
    }

    package func pause() async throws {
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        guard tapsAllowed.withLock({ $0 }), muter.mute(appPID: pid) else {
            throw MusicPlayerError.playerCommandFailed(.muteUnavailable)
        }
        mutedPID = pid
        hush.mute()
    }

    package func play() async throws {
        endMute()
    }

    /// Whether it plays now: its keep-awake assertion once it has held one,
    /// else its sound output (open while it plays, and for some apps paused too).
    private func playsNow(_ pid: pid_t) -> Bool {
        let soundOn = soundOn
        switch assertions.state(of: pid, soundOn: { soundOn(pid) }) {
        case .playing: return true
        case .paused: return false
        default: return soundOn(pid)
        }
    }

    private func liftMute() {
        if let mutedPID { muter.unmute(appPID: mutedPID) }
        mutedPID = nil
    }

    /// Unmuted, and nothing left of what the mute stood for.
    private func endMute() {
        liftMute()
        hush.unmute()
    }

    /// Lifts its mute without playing anything: as AutoHush quits, or once
    /// another player is chosen and AutoHush holds no pause in it.
    package func release() async {
        endMute()
    }

    /// Not in AntiDot mode, which taps no sound: then it can't be muted,
    /// and a mute under way is lifted.
    package nonisolated func allowTaps(_ allowed: Bool) {
        tapsAllowed.withLock { $0 = allowed }
        guard !allowed else { return }
        Task { await self.endMute() }
    }

    /// It reads as paused while muted: nothing more to mute.
    package func muteIfPlayingAnyway() async -> Bool { false }

    /// The Mac slept: AutoHush no longer holds the pause the mute stands
    /// for. It's lifted once the app has been stopped for
    /// `MuteState.stopTime`, never while it plays.
    package func forgetPause() async {
        guard hush.isMuted else { return }
        hush.forget()
        _ = await playerState()
    }
}
