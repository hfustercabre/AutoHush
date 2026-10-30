import Foundation

// PlaybackArbiter: the player heard while AutoHush holds its pause, or
// starting while other apps play.
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
        if mutedInstead {
            await lookWhileMuted()
        } else if await handleRestart(reported: false) == false {
            letUserHaveIt()
        }
        // Watched while its sound is measured: not once AntiDot mode is on.
        if pausedByUs, !activeSources.isEmpty, restartWatch == nil, tapsAllowed() { watchRestart(after: Self.silentRecheckInterval) }
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
        guard !mutedInstead, await handleRestart(reported: false) == false else { return }
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
    /// (input to the player just before, `userPlayedJustNow`: the user,
    /// 2026-10-25), it's theirs already, its pause failed, or a pause is
    /// under way.
    func playerStartedDuringApps() async {
        guard !isShutDown, !pausedByUs, !leftToUser, pauseFailure == nil, pauseTask == nil, !isFadingOut,
              autoPauseEnabled, !isAsleep, !activeSources.isEmpty else { return }
        if !playsSilently, let appsPlayingSince, userPlayedJustNow(after: appsPlayingSince) {
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
    /// reported play with nothing measured (AntiDot mode) after their input,
    /// while without it it's paused again; a look that can't measure it (the
    /// other app's output closed) tells nothing.
    /// Otherwise the pause didn't take, or it started again by itself: muted
    /// until the pause is over; one that can't be muted plays on, its pause
    /// failed.
    func handleRestart(reported: Bool) async -> Bool {
        guard pausedByUs, let pausedAt else { return false }
        // Muted in place of the pause, it plays on, silent, as expected.
        guard !mutedInstead else { return true }
        // Its pause is a mute of its own: heard through it, as any muted
        // player, and left to it (the user, 2026-10-25). One that only mutes,
        // said to play, was unmuted (the menu's Unmute): the user's.
        if await pauseIsItsOwnMute() { return !(reported && player.pausesByMuting) }
        let hearing = await hearsPlayer(pausedAt.addingTimeInterval(Self.pauseTail))
        guard !isShutDown, pausedByUs, !mutedInstead else { return true }
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
            // Nothing measured (AntiDot mode, no Audio Recording): a play it
            // reports is the user's only after their key or click in it just
            // before (the user, 2026-10-25); otherwise it's paused again.
            guard reported else { return true }
            if userPlayedJustNow(after: pausedAt) { return false }
            return await pauseAgain()
        case .heard:
            break
        }
        if wasSilent, userPlayedJustNow(after: pausedAt) { return false }
        return await muteInsteadOfPause("plays on through the pause, or started again by itself",
                                        failure: .playerCommandFailed(.pressIgnored))
    }

    /// Said to play again during AutoHush's pause with nothing measured, and
    /// not by the user: paused again (nothing to mute it by without its
    /// sound); refused, it's muted where it can be, else its pause failed.
    private func pauseAgain() async -> Bool {
        logger.info("[arbiter] \(self.player.name, privacy: .public) says it plays again during the pause, not by the user — paused again")
        do {
            try await player.pause()
        } catch {
            return await muteInsteadOfPause("refused to pause again",
                                            failure: error as? MusicPlayerError ?? .playerCommandFailed(.pressFailed))
        }
        return true // its report of the pause says it's paused
    }

    /// Whether the user played the player just now: a key or click in it
    /// after `date` and within `playInputWindow`, so an input long before
    /// the player starts again isn't taken for its play.
    func userPlayedJustNow(after date: Date) -> Bool {
        inputToPlayer(max(date, clock().addingTimeInterval(-Self.playInputWindow)))
    }
}
