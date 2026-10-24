import Foundation

/// Describes what the media player and the monitor are doing right now.
/// Separate from AppHealthState so icons can reflect real-time playback
/// without coupling to error conditions.
package enum PlaybackState: Equatable, Sendable {
    /// App just started; the player's state is not yet known.
    case unknown
    /// The music is playing on this Mac (other apps may be playing too, e.g.
    /// with auto-pause off or after the user resumed it).
    case musicPlaying
    /// Monitor paused the music because a foreign audio source started.
    case pausedByMonitor
    /// The player is paused, stopped or not running, and not held paused
    /// for another app (the user paused it, or nothing plays).
    case musicIdle
    /// The music plays on another device (the player's own remote playback); it is never paused.
    case playingElsewhere
    /// The player says it plays on this Mac, but nothing of it is heard (a
    /// muted trailer, a silent preview): it isn't paused, since nothing needs it.
    case playingSilently
    /// Another app plays, but the media player refused to pause or failed
    /// to (the arbiter says why); it plays on.
    case pauseFailed
}
