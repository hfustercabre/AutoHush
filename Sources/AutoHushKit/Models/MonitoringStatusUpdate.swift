import Foundation

/// What the engine reports for the menu and Settings.
package enum MonitoringStatusUpdate: Sendable {
    case playback(PlaybackState)
    case activeSources([AudioSource])
    case detection(DetectionMode)
    /// AntiDot mode learned how an app tells macOS it plays.
    case learnedAssertions(String, AnnouncedAssertions)
    /// Why the music couldn't be paused, then `nil` once that's over.
    case pauseFailure(MusicPlayerError?)
    /// The player is muted in place of AutoHush's pause (one that didn't
    /// take, a start by itself, or a refused one), then `false` once the
    /// mute is lifted.
    case mutedInstead(Bool)
    /// The last resume was given up (no answer, or its play failed),
    /// then `nil` once that's over.
    case resumeFailure(MusicPlayerError?)
}
