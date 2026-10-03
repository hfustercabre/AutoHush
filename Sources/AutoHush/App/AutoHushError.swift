import Foundation

/// Why the music player could not be controlled.
enum AutoHushError: LocalizedError, Equatable, Sendable {
    case automationPermissionDenied
    case playerNotRunning
    /// The player did not answer in time, e.g. while still starting up.
    case playerNotResponding
    /// The player rejected or failed a command; the message carries the details.
    case playerCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .automationPermissionDenied:
            return "Automation permission to control the music player is not granted."
        case .playerNotRunning:
            return "The music player is not running or is unavailable."
        case .playerNotResponding:
            return "The music player is not responding."
        case .playerCommandFailed(let message):
            return "Controlling the music player failed: \(message)"
        }
    }
}
