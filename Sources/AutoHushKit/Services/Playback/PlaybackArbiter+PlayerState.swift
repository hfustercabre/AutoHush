import Foundation

// PlaybackArbiter: what the player says it does, and where it plays.
extension PlaybackArbiter {
    /// Called whenever the player reports a new state. While other apps play,
    /// a report that it plays again during our pause is judged by its sound
    /// (`handleRestart`: the user's only after their input, else muted); one
    /// that it stopped or quit ends our pause. Once no other app plays,
    /// nothing is judged the user's: the resume decides. A mute kept in
    /// place of a pause kept, though, is ended by the user's own pause or
    /// play (`reportWhileKeptMuted`).
    ///
    /// A report can be stale, though: some players post the state they had
    /// just before the new one (one, right after our pause: "Playing", then
    /// "Paused"). So a report that would end our pause is checked with the
    /// player first, and ignored while it's still paused.
    ///
    /// `.unknown` carries no information and is ignored.
    func handlePlayerStateChange(_ state: PlayerState) async {
        guard !isShutDown, state != .unknown else { return }
        notePlayerReport()
        resumeFailure = nil // it answers: the user may have played or paused it
        if state != .playing { playsSilently = false }
        noteStoppedPlaying(state)
        if state != .playing { pauseFailure = nil } // the user paused or stopped it
        if keptMuteStands {
            await reportWhileKeptMuted(state)
            return
        }
        guard pausedByUs, state != .paused else {
            let was = playerState
            playerState = state
            publishPlaybackState()
            if state == .playing, was != .playing, !pausedByUs { await playerStartedDuringApps() }
            return
        }
        let live = await livePlayerState()
        guard !isShutDown else { return }
        if live == .paused {
            logger.debug("[arbiter] \(self.player.name, privacy: .public) reported \(state.rawValue, privacy: .public) but is paused — keeping pausedByUs")
        } else {
            if live == .unknown { playerState = state } // no answer: the report stands
            // With no other app playing, nothing is judged the user's (the
            // user, 2026-10-24): the resume to come decides.
            if activeSources.isEmpty, !resumesHeld {
                publishPlaybackState()
                return
            }
            if playerState == .playing, await handleRestart(reported: true) {
                publishPlaybackState()
                return
            }
            if pausedByUs {
                logger.info("[arbiter] \(self.player.name, privacy: .public) is \(self.playerState.rawValue, privacy: .public): the user took it over, it won’t be resumed")
                pausedByUs = false
                leftToUser = true
            }
        }
        publishPlaybackState()
    }

    /// A report while a mute kept in place of a kept pause stands
    /// (`keptMuteStands`), checked with the player, as a report can be
    /// stale. Found paused, stopped or quit, or playing again after that,
    /// it's the user's doing (or the player's own): unmuted, theirs, not
    /// resumed (K1-2, the user, 2026-11-07). Still playing (a stale report,
    /// or the next track), or no answer, it stays muted.
    private func reportWhileKeptMuted(_ state: PlayerState) async {
        let was = playerState
        let live = await livePlayerState()
        guard !isShutDown else { return }
        // No answer: the report can't be checked, and may be stale (a
        // "Paused" around its refused pause), so the mute stays (C-3).
        guard live != .unknown else { return }
        // Still standing (no app started meanwhile), and not a report that
        // it plays on: the user's.
        if keptMuteStands, playerState != .playing || was != .playing {
            logger.info("[arbiter] \(self.player.name, privacy: .public) is \(self.playerState.rawValue, privacy: .public) while muted, with no app playing: the user’s, unmuted, it won’t be resumed")
            pausedByUs = false // the mute is lifted as it's published
            leftToUser = true
        }
        publishPlaybackState()
    }

    func handleLocalPlaybackChange(_ isLocal: Bool) async {
        guard !isShutDown, isLocal != playsLocally else { return }
        playsLocally = isLocal
        playsSilently = false // a new output, or none: what was heard no longer stands
        if !isLocal { pauseFailure = nil } // it isn't heard here any more
        publishPlaybackState()
        if isLocal, playerState == .playing { await playerStartedDuringApps() } // its sound on this Mac now
    }

    /// Queries the player's live state, caches it and publishes the resulting
    /// playback state. Used once as monitoring starts, to seed the cache. A
    /// report from its observer that came during the query is newer, and
    /// stands (`playerReports`).
    @discardableResult
    func refreshPlaybackState() async -> PlayerState {
        let reports = playerReports
        let state = await player.playerState()
        if playerReports == reports, state != .unknown {
            noteStoppedPlaying(state)
            playerState = state
        }
        publishPlaybackState()
        return state
    }

    func livePlayerState() async -> PlayerState {
        let state = await player.playerState()
        if state != .unknown {
            noteStoppedPlaying(state)
            playerState = state
        }
        return state
    }

    /// Notes when the player stops playing here (`stoppedPlayingAt`), from a
    /// state just learned and the one known until then. A pause on another
    /// device (the player's own remote playback) isn't noted: it's no concern here.
    private func noteStoppedPlaying(_ state: PlayerState) {
        switch state {
        case .paused:
            if playerState == .playing { stoppedPlayingAt = playsLocally ? clock() : nil }
        case .playing, .stopped, .notRunning:
            stoppedPlayingAt = nil
        case .unknown:
            break
        }
    }
}
