import Foundation

/// Describes what the music player and the monitor are doing right now.
/// Separate from AppHealthState so icons can reflect real-time playback
/// without coupling to error conditions.
package enum PlaybackState: Equatable, Sendable {
    /// App just started; the player's state is not yet known.
    case unknown
    /// The music is playing and no foreign audio source is active.
    case musicPlaying
    /// Monitor paused the music because a foreign audio source started.
    case pausedByMonitor
    /// The player is stopped/paused and no foreign audio source is active
    /// (user paused manually or the player is idle).
    case musicIdle
    /// The music plays on another device (e.g. Spotify Connect); it is never paused.
    case playingElsewhere
}
