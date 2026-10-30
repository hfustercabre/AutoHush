import Foundation

// PlaybackArbiter: new settings, Auto-Pause, and resumes held.
extension PlaybackArbiter {
    /// Applies new settings.
    func setConfiguration(_ configuration: AppConfiguration) async {
        self.configuration = configuration
        if !configuration.levelsMusic {
            volumeLeveler?.restoreNow() // whoever lowered it: the setting is off for all
            levelLowered = nil
            resumeLowered = false
        }
        await fader.setDurations(fadeOut: configuration.fadeOutDuration, fadeIn: configuration.fadeInDuration)
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
}
