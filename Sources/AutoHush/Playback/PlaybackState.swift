import Foundation

/// Describes what Spotify and the monitor are doing right now.
/// Separate from AppHealthState so icons can reflect real-time playback
/// without coupling to error conditions.
enum PlaybackState: Equatable, Sendable {
    /// App just started; Spotify state not yet known.
    case unknown
    /// Spotify is playing and no foreign audio source is active.
    case spotifyPlaying
    /// Monitor paused Spotify because a foreign audio source started.
    case pausedByMonitor
    /// Spotify is stopped/paused and no foreign audio source is active
    /// (user paused manually or Spotify is idle).
    case spotifyIdle
    /// Spotify plays on another Spotify Connect device; it is never paused.
    case spotifyPlayingElsewhere
}
