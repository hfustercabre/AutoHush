import Foundation

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
    /// (`lookWhileMuted`) keep about it.
    struct MuteState: Sendable {
        var kind = PauseMute.off
        /// While muted in place of the pause: when its pause was pressed,
        /// once its own state said it plays again, to be unmuted once it's
        /// silent since (`lookWhileMuted`).
        var pausePressed: Date?
        /// While muted in place of the pause: how many presses of its pause
        /// failed in a row, and when the last did (`mutedPauseWait`).
        var pauseFailures: (count: Int, last: Date)?
        /// Muted while it said it doesn't play (`mutesHeardWhileQuiet`): its
        /// mute is only lifted, never followed by a play, since nothing of
        /// it was playing to resume. Kept until AutoHush's pause is over.
        var whileQuiet = false

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

        /// Not muted by AutoHush any more, saying whether it was.
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
}
