import Foundation

// PlaybackArbiter: the output going away, and the Mac going to sleep.
extension PlaybackArbiter {
    /// The output the sound played through went away (headphones unplugged
    /// or out of range, AirPods moved to another device): with Pause on
    /// disconnect (Settings → Behavior) and Auto-Pause on, the music pauses at once, without a fade, rather than moving to the next
    /// output, and stays paused: a pause of ours, or one fading out, is the
    /// user's from then on, as after a sleep (the user, 2026-10-21).
    func handleOutputDisconnected() async {
        guard !isShutDown, configuration.pausesOnOutputDisconnect, autoPauseEnabled, !isAsleep else { return }
        // A resume still pending is called off: it would unmute a player
        // whose real pause is refused, and play it on the next output (K1-3).
        if pausedByUs {
            cancelPendingResume()
            callDuringPause = false
            logger.info("[arbiter] the output went away: \(self.player.name, privacy: .public) stays paused")
            await keepPaused()
            return
        }
        // A fade-out under way pauses where it got to, rather than fading
        // on through the next output (the user, 2026-10-21), and isn't held.
        // Called off, the music coming back up, it's paused at once below,
        // as when it plays.
        if isFadingOut {
            outputGoneDuringPause = true
            if await fader.cutFadeOutShort() { return }
            outputGoneDuringPause = false
        }
        guard playsLocally else { return }
        let state = await livePlayerState()
        guard !isShutDown, autoPauseEnabled, state == .playing else { return }
        do {
            try await fader.pauseNow()
        } catch {
            logger.error("[arbiter] pausing \(self.player.name, privacy: .public) as the output went away failed: \(error)")
            return
        }
        // Paused: the Mac's volume lowered for the music is put back.
        if let levelLowered { volumeLeveler?.restoreNow(lowered: levelLowered) }
        levelLowered = nil
        playerState = .paused
        latestStart = nil // no app's doing, to be taken over and resumed
        logger.info("[arbiter] the output went away: \(self.player.name, privacy: .public) paused at once, and stays paused")
        publishPlaybackState()
    }

    /// The Mac goes to sleep (`true`) or is awake again (`false`).
    ///
    /// The other apps' sound stops as the Mac falls asleep, which isn't them
    /// ending: a pause AutoHush holds is forgotten, so the music stays paused
    /// after waking, as media players keep it after a sleep. While asleep
    /// nothing is paused or resumed (a web page can't be pressed then); once
    /// awake, apps playing pause the music as usual.
    ///
    /// `change` numbers the changes as they happened, when they can arrive
    /// by more than one way: one older than the latest applied comes late,
    /// and is ignored.
    func setAsleep(_ asleep: Bool, change: Int? = nil) async {
        if let change {
            guard acceptsSleepChange(change) else { return }
        }
        guard !isShutDown, asleep != isAsleep else { return }
        isAsleep = asleep
        if asleep {
            // A pause under way may end only after the Mac wakes (frozen
            // mid-fade): it's forgotten all the same.
            if pauseTask != nil { sleptDuringPause = true }
            pauseFailure = nil
            cancelPendingPause()
            cancelPendingResume()
            if pausedByUs {
                // Muted in place of the pause: paused for real first, so it
                // wakes paused, as any pause held then (the user, 2026-10-25);
                // refused, it plays on, its pause failed.
                let refused = mutedInstead ? await pauseForReal(uncovered: true) : nil
                pausedByUs = false
                if let refused {
                    if !activeSources.isEmpty { pauseFailure = refused }
                } else {
                    forgotPauseInSleep = true
                    logger.info("[arbiter] the Mac sleeps: \(self.player.name, privacy: .public) stays paused")
                }
            }
        } else {
            logger.info("[arbiter] the Mac is awake")
            await tellForgottenPause()
            if autoPauseEnabled, !activeSources.isEmpty { startPause() }
        }
        publishPlaybackState()
    }

    /// A pause forgotten in a sleep is told to the player, once the Mac is
    /// awake: it can act then.
    func tellForgottenPause() async {
        if forgotPauseInSleep, let muting = player as? any MutingMusicPlayer { await muting.forgetPause() }
        forgotPauseInSleep = false
    }
}
