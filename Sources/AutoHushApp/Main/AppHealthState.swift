import Foundation
import AutoHushKit

/// Whether the app could start monitoring, and if not, why.
enum AppHealthState: Equatable, Sendable {
    case starting
    case ready
    /// No music player is chosen yet: AutoHush waits for the user.
    case needsPlayer(String)
    case degraded(String)
    /// AutoHush may not control the player: the user has to grant it.
    case needsPermission(Permission)
    case failed(String)
}

extension AppHealthState {
    /// Waiting for the user to choose one of `options`, or for one of them to
    /// be installed.
    static func waitingForPlayer(among options: [PlayerOption]) -> AppHealthState {
        guard !options.noneInstalled else {
            return .needsPlayer(String(localized: "No supported music player is installed",
                                       comment: "Status line: none of the music players AutoHush works with is installed"))
        }
        return .needsPlayer(String(localized: "Choose a music player", comment: "Status line: no music player chosen yet"))
    }

    /// The chosen music player is no longer installed.
    static func playerNotInstalled(_ playerName: String) -> AppHealthState {
        .degraded(String(localized: "\(playerName) is not installed",
                         comment: "Status line; %@ is the music player, e.g. Spotify"))
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
                                    comment: "Status line; %@ is the music player, e.g. Spotify"))
        case .playerNotResponding:
            self = .degraded(String(localized: "\(playerName) is not responding",
                                    comment: "Status line; %@ is the music player, e.g. Spotify"))
        case .playerCommandFailed(let message):
            self = .degraded(String(localized: "\(playerName) control error: \(message)",
                                    comment: "Status line; the music player, then the error it reported"))
        case nil:
            self = .failed(error.localizedDescription)
        }
    }
}
