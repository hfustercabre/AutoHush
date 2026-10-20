import Foundation
import AutoHushKit

/// Whether the app could start monitoring, and if not, why.
enum AppHealthState: Equatable, Sendable {
    case starting
    case ready
    /// No media player is chosen yet: AutoHush waits for the user.
    case needsPlayer(String)
    /// The player isn't installed: AutoHush starts on once it's back.
    case degraded(String)
    /// The player is closed: AutoHush listens anyway, has nothing to pause,
    /// and starts on once it opens, so nothing needs the user (the user,
    /// 2026-10-20: said calmly).
    case playerClosed(String)
    /// The player didn't answer, or answered with an error, and nothing
    /// announces when it's fixed: AutoHush tries again by itself, and the
    /// menu offers Try Again.
    case retrying(String)
    /// AutoHush may not control the player: the user has to grant it.
    case needsPermission(Permission)
    case failed(String)
}

extension AppHealthState {
    /// Waiting for the user to choose a player. Every Mac has some installed:
    /// macOS itself comes with supported ones.
    static var waitingForPlayer: AppHealthState {
        .needsPlayer(String(localized: "Choose a media player", comment: "Status line: no media player chosen yet"))
    }

    /// The chosen media player is no longer installed.
    static func playerNotInstalled(_ playerName: String) -> AppHealthState {
        .degraded(String(localized: "\(playerName) isn’t installed",
                         comment: "Status line; %@ is the media player, e.g. Spotify"))
    }

    /// The health shown when the startup check against the media player fails.
    init(startupError error: any Error, playerName: String) {
        switch error as? MusicPlayerError {
        case .automationPermissionDenied:
            self = .needsPermission(.automation(player: playerName))
        case .accessibilityPermissionDenied:
            self = .needsPermission(.accessibility(player: playerName))
        case .playerNotRunning:
            self = .playerClosed(String(localized: "\(playerName) isn’t running",
                                    comment: "Status line; %@ is the media player, e.g. Spotify"))
        case .playerNotResponding:
            self = .retrying(String(localized: "\(playerName) isn’t responding",
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
        String(localized: "Can’t control \(playerName) right now",
               comment: "Status line when the media player couldn't be controlled; an info symbol after it opens an alert that says why; %@ is the media player, e.g. TIDAL")
    }
}
