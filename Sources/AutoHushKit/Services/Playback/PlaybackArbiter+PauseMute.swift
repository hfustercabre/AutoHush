import Foundation

// PlaybackArbiter: its mute of the player in place of a pause (the user,
// 2026-10-24: "If pauses didn't work, you should mute it"), and where it stands.
extension PlaybackArbiter {
    /// AutoHush's mute of the player, standing for its pause (the user,
    /// 2026-10-24: "If pauses didn't work, you should mute it").
    enum PauseMute: Sendable {
        /// Not muted by AutoHush.
        case off
        /// Muted in place of the pause: the player plays on through it, or
        /// started again by itself, so the mute stands for the pause until
        /// it's over.
        case insteadOfPause
        /// Muted in place of the pause, then paused once it went silent: the
        /// mute is kept until it plays again, the resume or the user's play
        /// (the user, 2026-10-24: "unmute it for the playback"), so a restart
        /// by itself is never heard.
        case keptInPause
    }

    /// Where AutoHush's mute of the player stands, and what its looks
    /// (`lookWhileMuted`) keep about it: changed only through its methods,
    /// so each step resets what it must.
    struct MuteState: Sendable {
        private(set) var kind = PauseMute.off
        /// While muted in place of the pause: when its pause was pressed,
        /// once its own state said it plays again, to be unmuted once it's
        /// silent since (`lookWhileMuted`).
        private(set) var pausePressed: Date?
        /// While muted in place of the pause: how many presses of its pause
        /// failed in a row, and when the last did (`mutedPauseWait`).
        private(set) var pauseFailures: (count: Int, last: Date)?
        /// Muted while it said it doesn't play (`mutesHeardWhileQuiet`): its
        /// mute is only lifted, never followed by a play, since nothing of
        /// it was playing to resume. Kept until AutoHush's pause is over.
        private(set) var whileQuiet = false

        var isInsteadOfPause: Bool { kind == .insteadOfPause }

        /// Muted in place of the pause, its looks starting afresh.
        mutating func begin() {
            kind = .insteadOfPause
            pausePressed = nil
            pauseFailures = nil
        }

        /// Paused once it went silent: still muted until it plays again.
        mutating func keepInPause() {
            kind = .keptInPause
            pausePressed = nil
        }

        /// Another press of its pause failed at `date`: how many in a row.
        mutating func notePauseFailed(at date: Date) -> Int {
            let failures = (pauseFailures?.count ?? 0) + 1
            pauseFailures = (failures, date)
            return failures
        }

        /// A press of its pause went through: no failures in a row.
        mutating func notePauseWorked() {
            pauseFailures = nil
        }

        /// Its pause was pressed at `date`.
        mutating func notePausePressed(at date: Date) {
            pausePressed = date
        }

        /// Muted while it said it doesn't play, or not (its pause over).
        mutating func noteWhileQuiet(_ quiet: Bool) {
            whileQuiet = quiet
        }

        /// Not muted by AutoHush any more, saying whether it was.
        @discardableResult
        mutating func end() -> Bool {
            guard kind != .off else { return false }
            kind = .off
            pausePressed = nil
            pauseFailures = nil
            return true
        }
    }

    /// The mute in place of the pause still stands after a wait: the
    /// monitoring goes on, AutoHush holds its pause, and it's still that
    /// mute (`lookWhileMuted` checks it after each await).
    var muteStillStands: Bool { !isShutDown && pausedByUs && mutedInstead }

    /// Mutes the player in place of a pause that doesn't take: AutoHush's
    /// pause from then on, ended as any. `true` once it's handled; one that
    /// can't be muted plays on, its pause failed (`failure`).
    func muteInsteadOfPause(_ why: String, failure: MusicPlayerError) async -> Bool {
        // A mute lifted just before is lifted first, so it can't lift this one.
        await muteLift?.value
        // Muted already, kept through the pause: only a relaunched process to mute.
        let keptMute = mute.kind == .keptInPause
        let muted: Bool = if keptMute { await playerMute?.followRelaunch() ?? false } else { await playerMute?.mute() ?? false }
        if muted, let playerMute {
            // Things may have changed while its tap was made (the Mac asleep,
            // the apps gone, Auto-Pause off): a mute is never left with
            // nothing to lift it.
            guard !isShutDown else {
                await playerMute.unmute()
                return true
            }
            if isAsleep || outputGoneDuringPause {
                // Asleep, or the output gone: no pause held, so no mute either
                // (what's shown changed with them).
                outputGoneDuringPause = false
                mute.end()
                await playerMute.unmute()
                return true
            }
            // A call among the apps was noted as the music faded out.
            pausedByUs = true
            mute.begin()
            playerState = .playing
            pausedAt = clock()
            logger.info("[arbiter] \(self.player.name, privacy: .public) \(why, privacy: .public) — muted until the apps stop")
            publishPlaybackState()
            // AntiDot mode turned on while its tap was made: no tap may stay,
            // so paused for real and unmuted, as at its turning on.
            if !tapsAllowed() {
                await setTapsAllowed(false)
                guard !isShutDown else { return true }
            }
            if !autoPauseEnabled || activeSources.isEmpty {
                scheduleResume(after: nil) // its resume unmutes it
            } else if tapsAllowed() {
                watchRestart(after: Self.silentRecheckInterval)
            }
            return true
        }
        if keptMute { mute.end() } // a relaunched process heard: no mute stands
        logger.info("[arbiter] \(self.player.name, privacy: .public) \(why, privacy: .public) and can’t be muted — it plays on")
        pausedByUs = false
        if !activeSources.isEmpty { pauseFailure = failure }
        publishPlaybackState()
        return true
    }

    /// Muted in place of the pause: each look mutes a relaunched player
    /// again and listens to it (its sound is measured before the mute).
    /// Silent since the mute or since its pause was pressed (it paused
    /// itself: a trailer in a hidden window), it's paused,
    /// AutoHush's pause from then on, still muted until it plays again
    /// (`PauseMute.keptInPause`). Still heard, its pause is
    /// pressed again, every `mutedPauseRetry` (less often while it fails:
    /// `mutedPauseWait`); the user's input changes
    /// nothing then: it plays already, so nothing of theirs started it (the
    /// user, 2026-10-24: "if at any point it can be paused instead of
    /// muted, it should pause it"). Silent just after their key or click in
    /// it, it's their pause: unmuted, not resumed (the user, 2026-10-25).
    func lookWhileMuted() async {
        guard let pausedAt else { return }
        let stillMuted = await playerMute?.followRelaunch() ?? false
        guard muteStillStands, !activeSources.isEmpty else { return }
        guard stillMuted else {
            // Relaunched, and its new process couldn't be muted: it plays on, heard.
            logger.info("[arbiter] \(self.player.name, privacy: .public) relaunched and can’t be muted — it plays on")
            pausedByUs = false
            pauseFailure = .playerCommandFailed(.pressIgnored)
            publishPlaybackState()
            return
        }
        let since = (mute.pausePressed ?? pausedAt).addingTimeInterval(Self.pauseTail)
        let hearing = await hearsPlayer(since)
        logger.debug("[arbiter] muted \(self.player.name, privacy: .public): \(String(describing: hearing), privacy: .public)")
        switch hearing {
        case .silent:
            guard muteStillStands else { return }
            // Muted while it said it doesn't play: silent now, it's only
            // unmuted, as it says (no pause of AutoHush's to resume).
            if mute.whileQuiet {
                logger.info("[arbiter] \(self.player.name, privacy: .public) is silent now — unmuted, as it says it doesn’t play")
                playerState = .paused
                pausedByUs = false // the mute is lifted as it's published
                publishPlaybackState()
                return
            }
            // Paused by the user just now (their key or click in it): theirs,
            // unmuted, not resumed (the user, 2026-10-25).
            if userPlayedJustNow(after: pausedAt) {
                await liftPauseMute()
                playerState = .paused
                pausedByUs = false
                leftToUser = true
                logger.info("[arbiter] \(self.player.name, privacy: .public) was paused by the user while muted: theirs, it won’t be resumed")
                publishPlaybackState()
                return
            }
            mute.keepInPause()
            playerState = .paused
            self.pausedAt = clock()
            hearingDuringPause = .silent
            logger.info("[arbiter] \(self.player.name, privacy: .public) is silent now — paused, muted until it plays again")
            publishPlaybackState()
        case .heard:
            // Things may have changed while it was measured.
            guard muteStillStands, !activeSources.isEmpty else { return }
            let now = clock()
            if let pressed = mute.pausePressed, now.timeIntervalSince(pressed) < Self.mutedPauseRetry { return }
            if let failed = mute.pauseFailures, now.timeIntervalSince(failed.last) < Self.mutedPauseWait(afterFailures: failed.count) { return }
            do { try await player.pauseQuietly() } catch {
                let failures = mute.notePauseFailed(at: now)
                logger.debug("[arbiter] muted \(self.player.name, privacy: .public): its pause failed (\(failures, privacy: .public) in a row): \(error)")
                return
            }
            mute.notePauseWorked()
            logger.debug("[arbiter] muted \(self.player.name, privacy: .public): its pause pressed in \(String(format: "%.2f", self.clock().timeIntervalSince(now)), privacy: .public) s")
            guard muteStillStands else { return }
            mute.notePausePressed(at: now)
        case .measuring, .unknown:
            return // looked at again at the next look
        }
    }

    /// Muted in place of the pause, paused for real before its mute is
    /// lifted (the Mac asleep, AntiDot mode on, the pause kept): `nil` once
    /// paused, the error when it refused.
    func pauseForReal() async -> MusicPlayerError? {
        do {
            try await player.pause()
            return nil
        } catch {
            logger.info("[arbiter] \(self.player.name, privacy: .public) refused its pause before its mute is lifted: \(error)")
            return error as? MusicPlayerError ?? .playerCommandFailed(.pressFailed)
        }
    }

    /// The menu's Unmute on a player muted in place of the pause (the user,
    /// 2026-10-25): heard again, the user's until another app starts or none
    /// plays, as an app that can only be muted is after its Unmute.
    func unmuteInstead() {
        guard !isShutDown, pausedByUs, mutedInstead else { return }
        logger.info("[arbiter] \(self.player.name, privacy: .public) unmuted from the menu: the user’s until the other apps stop")
        pausedByUs = false // the mute is lifted as it's published
        leftToUser = true
        publishPlaybackState()
    }

    /// AntiDot mode turned on (`allowed` false), which promises no audio taps:
    /// a mute standing for the pause is lifted at once, the player paused
    /// for real first, still AutoHush's pause (the user, 2026-10-25).
    func setTapsAllowed(_ allowed: Bool) async {
        guard !allowed, !isShutDown, mute.kind != .off else { return }
        let refused = mutedInstead ? await pauseForReal() : nil
        guard !isShutDown else { return }
        if let refused {
            // Refused: it plays on, heard once unmuted, its pause failed (the
            // user, 2026-10-25: "Say Couldn't pause").
            pausedByUs = false // the mute is lifted as it's published
            if !activeSources.isEmpty { pauseFailure = refused }
            publishPlaybackState()
            return
        }
        await liftPauseMute()
        playerState = .paused
        hearingDuringPause = .silent
        // Still paused by AutoHush, as shown; the Muted note goes with the mute.
        logger.info("[arbiter] AntiDot mode: \(self.player.name, privacy: .public) paused, and no longer muted")
    }

    /// Whether the player's pause is a mute of its own: an app added as
    /// Mute It Instead, or a web page muted during an ad. AutoHush's restart
    /// watch and its mute leave such a player to it.
    func pauseIsItsOwnMute() async -> Bool {
        if player.pausesByMuting || heldByMute { return true }
        return await (player as? any MutingMusicPlayer)?.isMutedForPause() ?? false
    }

    /// Ends AutoHush's mute of the player (`MuteState.end`), saying whether
    /// there was one: the caller unmutes it, at once (`liftPauseMute`) or,
    /// as the pause's end is published, without waiting.
    func endPauseMute() -> Bool { mute.end() }

    /// Lifts AutoHush's mute of the player, if any, at once.
    func liftPauseMute() async {
        if endPauseMute() { await playerMute?.unmute() }
    }
}
