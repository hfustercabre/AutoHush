import Foundation

/// Why the music player could not be controlled.
package enum MusicPlayerError: LocalizedError, Equatable, Sendable {
    case automationPermissionDenied
    /// For a player controlled through its own menu.
    case accessibilityPermissionDenied
    case playerNotRunning
    /// The player did not answer in time, e.g. while still starting up.
    case playerNotResponding
    /// The player rejected or failed a command, for this reason.
    case playerCommandFailed(ControlFailure)
    /// The player can't be controlled until AutoHush has learned how
    /// (`LearningMusicPlayer`): an expected wait, not a failure.
    case stillLearning

    /// In English, for the log and Diagnostics' report; the app words the
    /// failure for the user (the engine has no text for people).
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
        case .playerCommandFailed(let failure):
            return "Controlling the music player failed: \(failure)."
        case .stillLearning:
            return "AutoHush is still learning how to control the music player."
        }
    }
}

/// What went wrong when a player was told to play or pause, or checked: the
/// app says it in the user's language. Its `description`, in English, is for
/// the log and Diagnostics' report.
package enum ControlFailure: Equatable, Sendable, CustomStringConvertible {
    /// Its Play/Pause item wasn't found in its menus (an update changed them).
    case menuItemNotFound
    /// It doesn't say whether it plays: its state can't be read.
    case stateUnknown
    /// It has nothing to play: its Play is disabled.
    case nothingToPlay
    /// Its Play/Pause button is disabled (a web app during an ad).
    case buttonDisabled
    /// Its Play/Pause couldn't be pressed.
    case pressFailed
    /// It didn't follow a press of its Play/Pause.
    case pressIgnored
    /// It answered an Apple event with an error: its number, and the
    /// message it gave, if any (in the player's language).
    case appleEventError(Int, message: String?)

    package var description: String {
        switch self {
        case .menuItemNotFound: "its Play/Pause menu item wasn't found"
        case .stateUnknown: "its state is unknown"
        case .nothingToPlay: "it has nothing to play"
        case .buttonDisabled: "its Play/Pause button is disabled"
        case .pressFailed: "its Play/Pause couldn't be pressed"
        case .pressIgnored: "it didn't respond to its Play/Pause"
        case .appleEventError(let number, let message?) where !message.isEmpty: "\(message) (OSStatus \(number))"
        case .appleEventError(let number, _): "OSStatus \(number)"
        }
    }
}
