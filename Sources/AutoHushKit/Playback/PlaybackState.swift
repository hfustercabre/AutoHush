import Foundation

/// Describes what the music player and the monitor are doing right now.
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
    /// The music plays on another device (e.g. Spotify Connect); it is never paused.
    case playingElsewhere
    /// Another app plays, but the music player refused to pause or failed
    /// to (the arbiter says why); it plays on.
    case pauseFailed
}
