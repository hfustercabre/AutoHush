import Foundation

/// Why the music player could not be controlled.
package enum MusicPlayerError: LocalizedError, Equatable, Sendable {
    case automationPermissionDenied
    /// For a player controlled through its own menu.
    case accessibilityPermissionDenied
    case playerNotRunning
    /// The player did not answer in time, e.g. while still starting up.
    case playerNotResponding
    /// The player rejected or failed a command; the message carries the details.
    case playerCommandFailed(String)
    /// The player can't be controlled until AutoHush has learned how
    /// (`LearningMusicPlayer`): an expected wait, not a failure.
    case stillLearning

    package var errorDescription: String? {
        switch self {
        case .automationPermissionDenied:
            return "Automation permission to control the music player is not granted."
        case .accessibilityPermissionDenied:
            return "Accessibility permission to control the music player is not granted."
        case .playerNotRunning:
            return "The music player is not running or is unavailable."
        case .playerNotResponding:
            return "The music player is not responding."
        case .playerCommandFailed(let message):
            return "Controlling the music player failed: \(message)"
        case .stillLearning:
            return "AutoHush is still learning how to control the music player."
        }
    }
}
