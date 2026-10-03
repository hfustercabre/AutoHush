import Foundation

enum AutoHushError: LocalizedError, Equatable, Sendable {
    case automationPermissionDenied
    case spotifyUnavailable
    /// Spotify did not answer an Apple event in time, e.g. while still starting up.
    case spotifyNotResponding
    /// Spotify rejected or failed an Apple event; the message carries the details.
    case spotifyCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .automationPermissionDenied:
            return "Automation permission for Spotify is not granted."
        case .spotifyUnavailable:
            return "Spotify is not running or is unavailable."
        case .spotifyNotResponding:
            return "Spotify is not responding."
        case .spotifyCommandFailed(let message):
            return "Controlling Spotify failed: \(message)"
        }
    }
}
