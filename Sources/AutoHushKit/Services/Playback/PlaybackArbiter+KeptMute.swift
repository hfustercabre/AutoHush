import Foundation

// PlaybackArbiter: a mute kept in place of a kept pause, looked at with no
// app playing.
extension PlaybackArbiter {
    /// A mute kept in place of a kept pause (`keptMuteStands`), its sound not
    /// measured: with no app playing, nothing measures the player (it's
    /// tapped only beside another app, so the recording indicator isn't on
    /// for the music alone). Its pause is still pressed by a way that shows
    /// nothing, as while muted (every `mutedPauseRetry`, less often while it
    /// fails), and it's judged by its own state, read as each press is due:
    /// paused, stopped or quit, it's unmuted and left so, the user's, never
    /// resumed (F-1, the user's pick, 2026-11-07: "Press, judge by its state").
    func lookWhileKeptMuted() async {
        guard clock() >= nextMutedPress else { return }
        let state = await livePlayerState()
        // Things may have changed while it answered.
        guard keptMuteStands else { return }
        switch state {
        case .paused, .stopped, .notRunning:
            logger.info("[arbiter] \(self.player.name, privacy: .public) is \(state.rawValue, privacy: .public) now — its pause kept: unmuted, left paused")
            pausedByUs = false // the mute is lifted as it's published
            publishPlaybackState()
        case .playing, .unknown:
            await pressPauseWhileMuted()
        }
    }

    /// How long until the next look at a mute while AutoHush holds its
    /// pause: every `silentRecheckInterval` while other apps play; a mute
    /// kept with none (`keptMuteStands`) only once its pause may be pressed
    /// again (`nextMutedPress`): nothing measures it then, so there's
    /// nothing else to look at (F-5).
    var nextLookDelay: TimeInterval {
        guard keptMuteStands else { return Self.silentRecheckInterval }
        return max(Self.silentRecheckInterval, nextMutedPress.timeIntervalSince(clock()))
    }
}
