import Foundation
import AutoHushKit

/// Whether the app could start monitoring, and if not, why.
enum AppHealthState: Equatable, Sendable {
    case starting
    case ready
    /// No music player is chosen yet: AutoHush waits for the user.
    case needsPlayer(String)
    /// The player isn't running or isn't installed: AutoHush starts on when
    /// it opens or is back.
    case degraded(String)
    /// The player didn't answer, or answered with an error, and nothing
    /// announces when it's fixed: AutoHush tries again by itself, and the
    /// menu offers Retry.
    case retrying(String)
    /// AutoHush may not control the player: the user has to grant it.
    case needsPermission(Permission)
    case failed(String)
}

extension AppHealthState {
    /// Waiting for the user to choose one of `options`, or for one of them to
    /// be installed.
    static func waitingForPlayer(among options: [PlayerOption]) -> AppHealthState {
        guard !options.noneInstalled else {
            return .needsPlayer(String(localized: "No supported media player is installed",
                                       comment: "Status line: none of the media players AutoHush works with is installed"))
        }
        return .needsPlayer(String(localized: "Choose a media player", comment: "Status line: no media player chosen yet"))
    }

    /// The chosen music player is no longer installed.
    static func playerNotInstalled(_ playerName: String) -> AppHealthState {
        .degraded(String(localized: "\(playerName) is not installed",
                         comment: "Status line; %@ is the media player, e.g. Spotify"))
    }

    /// The health shown when the startup check against the music player fails.
    init(startupError error: any Error, playerName: String) {
        switch error as? MusicPlayerError {
        case .automationPermissionDenied:
            self = .needsPermission(.automation(player: playerName))
        case .accessibilityPermissionDenied:
            self = .needsPermission(.accessibility(player: playerName))
        case .playerNotRunning:
            self = .degraded(String(localized: "\(playerName) is not running",
                                    comment: "Status line; %@ is the media player, e.g. Spotify"))
        case .playerNotResponding:
            self = .retrying(String(localized: "\(playerName) is not responding",
                                    comment: "Status line; %@ is the media player, e.g. Spotify"))
        case .playerCommandFailed, .stillLearning: // stillLearning: never at startup, learning happens while it runs
            self = .retrying(Self.cantControl(playerName))
        case nil:
            self = .failed(Self.cantControl(playerName))
        }
    }

    /// The status line when the player answered with an error: the menu
    /// shows why under it (`AppStatus.controlError`).
    static func cantControl(_ playerName: String) -> String {
        String(localized: "Can't control \(playerName) right now",
               comment: "Status line when the media player couldn't be controlled; an info symbol after it opens an alert that says why; %@ is the media player, e.g. TIDAL")
    }
}
