import Foundation

// PlaybackArbiter: taking over the pause of the AutoHush before this one.
extension PlaybackArbiter {
    /// Takes over the pause of the AutoHush that ran before this one, which
    /// quit to install an update while holding the music paused, or of the
    /// monitoring before this one, whose pause is taken back (the player
    /// chosen again, checked again, or its permission back): if the player
    /// is still paused, it counts as paused by this arbiter, so the music
    /// comes back once no other app plays. Paused by a mute of its own (a
    /// page's, an app only ever muted), that mute is this arbiter's to lift
    /// (`heldByMute`), and the player heard through it is left to it, as in
    /// the pause it was made for (`handleRestart`). Found playing (or, for
    /// a tap, not answering, or saying anything when that tap was made as
    /// it said it doesn't play; for a page, heard though it says it's
    /// paused) while the one before held its pause by a mute
    /// (`mutedBefore`), it's muted again at once, the same way
    /// (`takeOverMute`). Apps still
    /// playing are found again first; when none is, the music resumes after
    /// the longest start the monitor applies (3 s for sound without video
    /// in AntiDot mode) plus `takeOverMargin`. `false` when there was no
    /// pause to take over: the player isn't paused, nor muted again.
    @discardableResult
    func takeOverPause(mutedBefore: TakenBackMute? = nil) async -> Bool {
        // Handed over while the Mac sleeps: forgotten, as any pause then.
        guard !isShutDown, !isAsleep else { return false }
        let state = await livePlayerState()
        guard !isShutDown else { return false }
        if let mutedBefore, let taken = await takeOverMute(mutedBefore, found: state) { return taken }
        guard state == .paused else { return false }
        return await adoptPause(.found)
    }

    /// How the pause taken over came to be.
    private enum TakenOver {
        /// The player found paused, as the one before left it.
        case found
        /// Paused by this arbiter's press just now (`takeOverMute`).
        case pressed
        /// Muted by its own mute just now, heard as it says it's paused
        /// (`muteIfPlayingAnyway`): that mute is the pause.
        case muted
    }

    /// The player paused: its pause is this arbiter's, a mute of its own
    /// included. Pressed just now (`.pressed`), it's played again if the
    /// monitoring stopped meanwhile, as nobody would resume it
    /// (`pauseMusicIfNeeded`), or the Mac went to sleep, since no pause is
    /// held then; a pause found is forgotten then, as any (`setAsleep`).
    private func adoptPause(_ how: TakenOver) async -> Bool {
        var ownMute = how == .muted
        if !ownMute { ownMute = await (player as? any MutingMusicPlayer)?.isMutedForPause() ?? false }
        // Never so for `.muted`: nothing is awaited since `takeOverMute`
        // checked the same, so its mute is never left with nothing to lift it.
        guard !isShutDown, !isAsleep else {
            if how == .pressed { try? await player.play() }
            return false
        }
        pausedByUs = true
        heldByMute = ownMute
        // Pressed just now, it's this arbiter's pause, timed as any it
        // pressed (N2 of 11-27); one found, or its own mute, has no time
        // (`forgetEarlierPause`): heard through its own mute, it's left to
        // it all the same (`handleRestart`).
        if how == .pressed { pausedAt = clock() }
        logger.info("[arbiter] took over the pause of the previous AutoHush")
        startTakenOverPause()
        return true
    }

    /// Found as `state` as the monitoring before held its pause by a mute,
    /// which still stands (`TakenBackMute`): muted again at once, the same
    /// way, before that one lets go of its own, so the music isn't heard
    /// until the apps are counted again. By this arbiter's tap, playing or
    /// not answering (a tap mutes whatever it says), or anything but not
    /// running when that mute was made as it was heard while it said it
    /// doesn't play (its resume then only unmutes it, as before: N1 of
    /// 11-27), muted in place of the pause from then on; by the player's
    /// own pause (another player object
    /// of the app, checked again, whose pause is a mute), paused by it; said
    /// paused or stopped while heard (a page's ad, its button saying Play),
    /// by its own mute (`muteIfPlayingAnyway`), which is the pause then.
    /// `false` when it can't be (AntiDot mode, no Audio Recording, a
    /// refused pause): the one before lifts its mute, and the apps, once
    /// counted, pause it as any. `nil` with nothing to mute again (paused
    /// under that mute, silent, or its own mute not possible): taken over
    /// as any pause, if it's paused.
    private func takeOverMute(_ mutedBefore: TakenBackMute, found state: PlayerState) async -> Bool? {
        switch (mutedBefore, state) {
        // Not every paused one: one that paused for real under its tap is
        // silent, a real pause (that mute turns into one at its next look,
        // `keptInPause`), whose resume plays it.
        case (.byTap(let whileQuiet), _) where state == .playing || state == .unknown || whileQuiet && state != .notRunning:
            guard let playerMute, await playerMute.mute() else { return false }
            // Stopped, or the Mac asleep, while its tap was made: a mute is
            // never left with nothing to lift it.
            guard !isShutDown, !isAsleep else {
                await playerMute.unmute()
                return false
            }
            pausedByUs = true
            if whileQuiet { mute.noteMutedWhileQuiet() } // told with the mute, at once
            mute.begin()
            pausedAt = clock()
            logger.info("[arbiter] \(self.player.name, privacy: .public) is \(state.rawValue, privacy: .public), muted in place of the pause taken back: muted again")
            startTakenOverPause()
            return true
        case (.byPlayer, .playing):
            do { try await player.pauseQuietly() } catch {
                logger.info("[arbiter] \(self.player.name, privacy: .public) couldn’t be muted again for the pause taken back: \(error)")
                return false
            }
            let pressed = await livePlayerState()
            guard !isAsleep else {
                // No pause held while asleep, nor its mute.
                if pressed == .paused { try? await player.play() } else { await liftMuteLeftByPress() }
                return false
            }
            guard pressed == .paused else {
                await liftMuteLeftByPress()
                return false
            }
            return await adoptPause(.pressed)
        case (.byPlayer, .paused), (.byPlayer, .stopped):
            guard let muting = player as? any MutingMusicPlayer, !(await muting.isMutedForPause()),
                  await muting.muteIfPlayingAnyway() else { return nil }
            // Stopped, or the Mac asleep, while it was measured: a mute is
            // never left with nothing to lift it.
            guard !isShutDown, !isAsleep else {
                await muting.releaseMute()
                return false
            }
            logger.info("[arbiter] \(self.player.name, privacy: .public) is \(state.rawValue, privacy: .public) but can be heard, as the pause taken back was a mute: muted again")
            return await adoptPause(.muted)
        default:
            return nil
        }
    }

    /// Its quiet pause muted it (a page that refused it), yet no pause is
    /// held (it reads as playing, or doesn't answer, or the Mac slept): that
    /// mute is lifted, nothing played, so it isn't left silent with no
    /// pause to end it.
    private func liftMuteLeftByPress() async {
        guard let muting = player as? any MutingMusicPlayer, await muting.isMutedForPause() else { return }
        logger.info("[arbiter] \(self.player.name, privacy: .public)’s pause muted it, but no pause is held: unmuted")
        await muting.releaseMute()
    }

    /// A pause taken over: shown, and resumed once the monitor, starting
    /// afresh, has had time to find an app still playing.
    private func startTakenOverPause() {
        publishPlaybackState()
        if activeSources.isEmpty {
            if autoPauseEnabled { scheduleTakenOverResume(from: clock()) } else { scheduleResume(after: nil) }
        }
    }

    /// The monitor says how long an app must play, at most, before it
    /// counts. A pause taken over before it said (it starts after the
    /// takeover) waits that long for apps still playing.
    func handleStartConfirmationChange(_ longest: TimeInterval) {
        guard !isShutDown else { return }
        let known = startConfirmation
        longestStartConfirmation = longest
        if longest != known, let takenOver, takenOver.resume == pendingResumeID {
            scheduleTakenOverResume(from: takenOver.at)
        }
    }

    /// How long an app must play, at most, before the monitor counts it, as
    /// far as known: until it says, the user's start confirmation.
    var startConfirmation: TimeInterval {
        longestStartConfirmation ?? configuration.sourceStartConfirmation
    }

    /// Resumes a pause taken over at `takenOverAt` once the monitor, starting
    /// afresh, has had `startConfirmation` plus `takeOverMargin` to find an
    /// app still playing.
    private func scheduleTakenOverResume(from takenOverAt: Date) {
        let wait = startConfirmation + Self.takeOverMargin - clock().timeIntervalSince(takenOverAt)
        scheduleResume(after: max(wait, 0))
        takenOver = pendingResumeID.map { (takenOverAt, $0) }
    }
}
