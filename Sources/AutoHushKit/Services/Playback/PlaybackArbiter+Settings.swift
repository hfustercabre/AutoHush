import Foundation

// PlaybackArbiter: new settings, Auto-Pause, resumes held, and kept mutes shown.
extension PlaybackArbiter {
    /// Applies new settings. A source playing that no longer counts (Pause
    /// for VoiceOver turned off while VoiceOver plays) stops at once, so the
    /// music it paused needn't wait for the monitor's stop.
    func setConfiguration(_ configuration: AppConfiguration) async {
        self.configuration = configuration
        await fader.setDurations(fadeOut: configuration.fadeOutDuration, fadeIn: configuration.fadeInDuration)
        for sourceID in activeSources.sorted() where !configuration.isMediaSource(sourceID) {
            await handleSourceChange(sourceID: sourceID, isPlaying: false)
        }
    }

    /// Turns automatic pausing on or off (the menu's "Auto-Pause" switch).
    ///
    /// Off: a pending resume is cancelled and the player, if we paused it, resumes
    /// right away — the user wants it playing alongside the other audio.
    /// On: if other apps are already playing, the player is paused once they
    /// have been measured again. Sources keep being tracked while off, but
    /// without audio levels (the monitor captures nothing then), so an app
    /// that only has its output open, such as a muted call, counts as
    /// playing; the monitor drops it within its stop grace.
    func setAutoPauseEnabled(_ enabled: Bool) async {
        guard !isShutDown, enabled != autoPauseEnabled else { return }
        autoPauseEnabled = enabled
        logger.info("[arbiter] Auto-Pause \(enabled ? "on" : "off", privacy: .public)")
        if enabled {
            if !activeSources.isEmpty {
                schedulePause(after: configuration.sourceStopGrace + Self.remeasureMargin)
            }
        } else {
            pauseFailure = nil
            cancelPendingPause()
            cancelPendingResume()
            if isFadingOut { await fader.cancel() }
            if pausedByUs { scheduleResume(after: nil) }
        }
        publishPlaybackState()
    }

    /// Holds every resume (`true`), or lets them happen again (`false`).
    /// While Add an App checks an app, playing and pausing it for minutes,
    /// music its sound paused would otherwise come back in each gap, fading
    /// in and out. Pausing goes on as usual, so music that plays still
    /// pauses when an app starts; a player we didn't pause is never touched.
    /// Released, music we paused resumes as it would have: at once when no
    /// other app plays (or Auto-Pause is off), otherwise once they stop.
    func holdResumes(_ held: Bool) {
        guard !isShutDown, held != resumesHeld else { return }
        resumesHeld = held
        logger.debug("[arbiter] resumes \(held ? "held" : "no longer held", privacy: .public)")
        if held {
            cancelPendingResume() // one checking on the player calls itself off
        } else if pausedByUs, !isAsleep, activeSources.isEmpty || !autoPauseEnabled {
            scheduleResume(after: nil)
        }
        publishPlaybackState()
    }

    /// Whether a mute kept in place of a kept pause (`keptMuteStands`) is
    /// shown, with Unmute (`true`, the chosen player's), or not (`false`): a
    /// player held paused after the user chose another has no card to show
    /// it. Its kept mute ends then, unmuted and its pause over, as a pause
    /// cut short by switching plays the player again (D2, the user's pick,
    /// 2026-11-07), once no app plays: while one does, it stays muted, not
    /// heard over it, and ends as they stop (`keepPaused`; F-2, the user:
    /// "Yes, once no app plays").
    func setKeptMuteShown(_ shown: Bool) {
        guard !isShutDown, shown != keptMuteShown else { return }
        keptMuteShown = shown
        if !shown, keptMuteStands { endUnshownKeptMute() }
    }

    /// A mute kept with nothing to show it (`keptMuteShown` false) ends:
    /// heard again, the user's, never resumed.
    func endUnshownKeptMute() {
        logger.info("[arbiter] \(self.player.name, privacy: .public) stays muted with nothing to show it: unmuted, the user’s")
        pausedByUs = false // the mute is lifted as it's published
        leftToUser = true
        publishPlaybackState()
    }
}
