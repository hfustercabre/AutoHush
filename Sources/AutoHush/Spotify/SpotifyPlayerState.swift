import Foundation

/// Spotify's player state. Raw values are used in log messages.
enum SpotifyPlayerState: String, Sendable {
    case playing
    case paused
    case stopped
    case notRunning = "not running"
    case unknown
}
