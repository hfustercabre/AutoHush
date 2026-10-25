import Foundation

// PlaybackArbiter: the player heard while AutoHush holds its pause, or
// starting while other apps play, and its mute in place of a pause (the
// user, 2026-10-24: "If pauses didn't work, you should mute it").
extension PlaybackArbiter {
    /// Looks, after `delay` and then every `silentRecheckInterval` while
    /// AutoHush holds its pause and other apps play, whether the pause took
    /// and stays (or, muted, whether it can be paused now). The monitor also
    /// tells the moment the player is heard again (`handlePlayerHeard`); this
    /// is for what it can't tell: a sound that never stopped (a pause that
    /// didn't take), and a state that changed.
    func watchRestart(after delay: TimeInterval) {
        if let restartWatch {
            restartWatch.task.cancel()
            let id = UUID()
            calledOffWatches[id] = restartWatch
            Task { [weak self] in
                await restartWatch.task.value
                await self?.watchEnded(id)
            }
        }
        let wait = debounceScheduler.scheduleDebounce(after: delay)
        let task = Task { [weak self] in
            _ = await wait.value
            guard !Task.isCancelled else { return }
            await self?.lookForRestart()
        }
        restartWatch = (task, wait)
    }

    private func watchEnded(_ id: UUID) { calledOffWatches[id] = nil }

    private func lookForRestart() async {
        let look = restartWatch?.task
        lookUnderWay = look
        restartWatch = nil
        await lookAtPause()
        if lookUnderWay == look { lookUnderWay = nil }
    }

    private func lookAtPause() async {
        guard !isShutDown, pausedByUs, !activeSources.isEmpty else { return }
        if mutedForRestart {
            await lookWhileMuted()
        } else if await handleRestart(reported: false) == false {
            letUserHaveIt()
        }
        if pausedByUs, !activeSources.isEmpty, restartWatch == nil { watchRestart(after: Self.silentRecheckInterval) }
    }

    /// The monitor heard the player again while other apps play: looked at
    /// at once, held by AutoHush or not. A mute it makes is awaited here, so
    /// the monitor's next event waits for its tap (a moment): their order is
    /// kept.
    func handlePlayerHeard() async {
        guard !isShutDown, autoPauseEnabled, !isAsleep, !activeSources.isEmpty else { return }
        guard pausedByUs else {
            await playerStartedDuringApps()
            return
        }
        guard !mutedForRestart, await handleRestart(reported: false) == false else { return }
        letUserHaveIt()
    }

    /// AutoHush's pause becomes the user's: they played the player.
    private func letUserHaveIt() {
        guard pausedByUs else { return }
        logger.info("[arbiter] \(self.player.name, privacy: .public) is heard again, played by the user: theirs, it won’t be resumed")
        pausedByUs = false // a mute standing for it is lifted as it's published
        leftToUser = true
        playerState = .playing
        publishPlaybackState()
    }

    /// The player starts, or is heard, while other apps play and AutoHush
    /// holds no pause in it (it wasn't playing when they started, or it was
    /// silent): paused as at an app's start, unless the user started it
    /// (input to the player since the apps started playing), it's theirs
    /// already, its pause failed, or a pause is under way.
    func playerStartedDuringApps() async {
        guard !isShutDown, !pausedByUs, !leftToUser, pauseFailure == nil, pauseTask == nil, !isFadingOut,
              autoPauseEnabled, !isAsleep, !activeSources.isEmpty else { return }
        if !playsSilently, let appsPlayingSince, inputToPlayer(appsPlayingSince) {
            leftToUser = true
            logger.info("[arbiter] \(self.player.name, privacy: .public) was started by the user while other apps play — left playing")
            return
        }
        logger.info("[arbiter] \(self.player.name, privacy: .public) plays while other apps do — pausing")
        cancelPendingPause()
        startPause()
    }

    /// Keeps what the player's sound said during the pause, for the resume:
    /// what was measured stands once nothing is (the other app's output closed).
    private func noteHearingDuringPause(_ hearing: PlayerHearing) {
        switch hearing {
        case .heard, .silent: hearingDuringPause = hearing
        case .measuring, .unknown: break
        }
    }

    /// The player says it plays (`reported`), or may be heard, while
    /// AutoHush holds its pause: its sound since the pause decides (what's
    /// heard up to `pauseTail` after it may be from before it). Not heard,
    /// it's a report that's late or a silent start, and the pause stands
    /// (`true`). Heard again after it was silent, and the user played it
    /// just before (`userPlayedJustNow`), it's theirs (`false`); so is a
    /// reported play with nothing measured (AntiDot mode), while a look that
    /// can't measure it (the other app's output closed) tells nothing.
    /// Otherwise the pause didn't take, or it started again by itself: muted
    /// until the pause is over; one that can't be muted plays on, its pause
    /// failed.
    func handleRestart(reported: Bool) async -> Bool {
        guard pausedByUs, let pausedAt else { return false }
        // Muted in place of the pause, it plays on, silent, as expected.
        guard !mutedForRestart else { return true }
        let hearing = await hearsPlayer(false, pausedAt.addingTimeInterval(Self.pauseTail))
        guard !isShutDown, pausedByUs, !mutedForRestart else { return true }
        // Only a player that was silent can be played again (the user, 2026-10-24).
        let wasSilent = hearingDuringPause == .silent
        noteHearingDuringPause(hearing)
        switch hearing {
        case .silent:
            if playerState == .playing {
                logger.info("[arbiter] \(self.player.name, privacy: .public) says it plays but isn’t heard — still paused")
                playerState = .paused
            }
            return true
        case .measuring(let remaining):
            watchRestart(after: remaining) // looked at again once it's known
            return true
        case .unknown:
            return !reported
        case .heard:
            break
        }
        if wasSilent, userPlayedJustNow(after: pausedAt) { return false }
        return await muteInsteadOfPause("plays on through the pause, or started again by itself",
                                        failure: .playerCommandFailed(.pressIgnored))
    }

    /// Whether the user played the player just now: a key or click in it,
    /// or a media key, after `date` and within `playInputWindow`, so an
    /// input long before the player starts again isn't taken for its play.
    private func userPlayedJustNow(after date: Date) -> Bool {
        inputToPlayer(max(date, clock().addingTimeInterval(-Self.playInputWindow)))
    }

    /// Mutes the player in place of a pause that doesn't take: AutoHush's
    /// pause from then on, ended as any. `true` once it's handled; one that
    /// can't be muted plays on, its pause failed (`failure`).
    func muteInsteadOfPause(_ why: String, failure: MusicPlayerError) async -> Bool {
        // A mute lifted just before is lifted first, so it can't lift this one.
        await muteLift?.value
        // Muted already, kept through the pause: only a relaunched process to mute.
        let keptMute = muteKeptInPause
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
                muteKeptInPause = false
                await playerMute.unmute()
                return true
            }
            // A call among the apps was noted as the music faded out.
            pausedByUs = true
            mutedForRestart = true
            muteKeptInPause = false
            pausePressedWhileMuted = nil
            playerState = .playing
            pausedAt = clock()
            logger.info("[arbiter] \(self.player.name, privacy: .public) \(why, privacy: .public) — muted until the apps stop")
            publishPlaybackState()
            if !autoPauseEnabled || activeSources.isEmpty {
                scheduleResume(after: nil) // its resume unmutes it
            } else {
                watchRestart(after: Self.silentRecheckInterval)
            }
            return true
        }
        if keptMute { muteKeptInPause = false } // a relaunched process heard: no mute stands
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
    /// (`muteKeptInPause`). Still heard, its pause is
    /// pressed again, every `mutedPauseRetry`. The user's input changes
    /// nothing: it plays already, so nothing of theirs started it (the
    /// user, 2026-10-24: "if at any point it can be paused instead of
    /// muted, it should pause it").
    private func lookWhileMuted() async {
        guard let pausedAt else { return }
        let stillMuted = await playerMute?.followRelaunch() ?? false
        guard !isShutDown, pausedByUs, mutedForRestart, !activeSources.isEmpty else { return }
        guard stillMuted else {
            // Relaunched, and its new process couldn't be muted: it plays on, heard.
            logger.info("[arbiter] \(self.player.name, privacy: .public) relaunched and can’t be muted — it plays on")
            pausedByUs = false
            pauseFailure = .playerCommandFailed(.pressIgnored)
            publishPlaybackState()
            return
        }
        let since = (pausePressedWhileMuted ?? pausedAt).addingTimeInterval(Self.pauseTail)
        let hearing = await hearsPlayer(false, since)
        logger.debug("[arbiter] muted \(self.player.name, privacy: .public): \(String(describing: hearing), privacy: .public)")
        switch hearing {
        case .silent:
            guard !isShutDown, pausedByUs, mutedForRestart else { return }
            mutedForRestart = false
            muteKeptInPause = true
            pausePressedWhileMuted = nil
            playerState = .paused
            self.pausedAt = clock()
            hearingDuringPause = .silent
            logger.info("[arbiter] \(self.player.name, privacy: .public) is silent now — paused, muted until it plays again")
            publishPlaybackState()
        case .heard:
            // Things may have changed while it was measured.
            guard !isShutDown, pausedByUs, mutedForRestart, !activeSources.isEmpty else { return }
            let now = clock()
            if let pressed = pausePressedWhileMuted, now.timeIntervalSince(pressed) < Self.mutedPauseRetry { return }
            do { try await player.pause() } catch {
                logger.debug("[arbiter] muted \(self.player.name, privacy: .public): its pause failed: \(error)")
                return
            }
            logger.debug("[arbiter] muted \(self.player.name, privacy: .public): its pause pressed in \(String(format: "%.2f", self.clock().timeIntervalSince(now)), privacy: .public) s")
            guard !isShutDown, pausedByUs, mutedForRestart else { return }
            pausePressedWhileMuted = now
        case .measuring, .unknown:
            return // looked at again at the next look
        }
    }
}
