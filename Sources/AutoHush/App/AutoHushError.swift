import Foundation

enum AutoHushError: LocalizedError, Equatable, Sendable {
    case automationPermissionDenied
    case spotifyUnavailable
    /// Spotify rejected or failed an Apple event; the message carries the details.
    case spotifyCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .automationPermissionDenied:
            return "Automation permission for Spotify is not granted."
        case .spotifyUnavailable:
            return "Spotify is not running or is unavailable."
        case .spotifyCommandFailed(let message):
            return "Controlling Spotify failed: \(message)"
        }
    }
}
