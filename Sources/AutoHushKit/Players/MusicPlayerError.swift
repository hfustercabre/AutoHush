import Foundation

/// Why the media player could not be controlled.
package enum MusicPlayerError: LocalizedError, LoggableError, Equatable, Sendable {
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

    /// In English, for the log, Diagnostics' report and the control-error
    /// alert's last paragraph (never translated: it's what a bug report
    /// quotes); the app words the failure for the user in their language.
    package var errorDescription: String? {
        switch self {
        case .automationPermissionDenied:
            return "AutoHush isn’t allowed Automation access to control the media player."
        case .accessibilityPermissionDenied:
            return "AutoHush isn’t allowed Accessibility access to control the media player."
        case .playerNotRunning:
            return "The media player isn’t running or isn’t available."
        case .playerNotResponding:
            return "The media player isn’t responding."
        case .playerCommandFailed(let failure):
            return "Controlling the media player failed: \(failure)."
        case .stillLearning:
            return "AutoHush is still learning how to control the media player."
        }
    }

    package var logDescription: String { errorDescription ?? "\(self)" }
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
    /// It can only be muted, and muting isn't possible now: no Audio
    /// Recording, or AntiDot mode, which taps no sound.
    case muteUnavailable
    /// Only its sound tells whether it plays (its Now Playing row doesn't
    /// follow it), and it can't be heard now: no Audio Recording, or AntiDot
    /// mode, which taps no sound.
    case hearingUnavailable
    /// Its way is the menu bar's Now Playing panel, and Now Playing isn't
    /// shown in the menu bar (the user hid it in System Settings).
    case nowPlayingHidden
    /// It answered an Apple event with an error: its number. Never the
    /// message it gave, which can name what it was playing (a document).
    case appleEventError(Int)

    package var description: String {
        switch self {
        case .menuItemNotFound: "its Play/Pause menu item wasn’t found"
        case .stateUnknown: "its state is unknown"
        case .nothingToPlay: "it has nothing to play"
        case .buttonDisabled: "its Play/Pause button is disabled"
        case .pressFailed: "its Play/Pause couldn’t be pressed"
        case .pressIgnored: "it didn’t respond to its Play/Pause"
        case .muteUnavailable: "it can only be muted, and muting needs Audio Recording (not in AntiDot mode)"
        case .hearingUnavailable: "only its sound tells whether it’s playing, and hearing it needs Audio Recording (not in AntiDot mode)"
        case .nowPlayingHidden: "Now Playing isn’t shown in the menu bar, so its panel can’t be opened"
        case .appleEventError(let number): "OSStatus \(number)"
        }
    }
}
