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
}
