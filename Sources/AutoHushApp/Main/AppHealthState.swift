import Foundation
import AutoHushKit

/// Whether the app could start monitoring, and if not, why.
enum AppHealthState: Equatable, Sendable {
    case starting
    case ready
    case degraded(String)
    case needsPermission(String)
    case failed(String)
}

extension AppHealthState {
    /// The health shown when the startup check against the music player fails.
    init(startupError error: any Error, playerName: String) {
        switch error as? MusicPlayerError {
        case .automationPermissionDenied:
            self = .needsPermission(String(localized: "Grant Automation access to control \(playerName)",
                                           comment: "Status line; %@ is the music player, e.g. Spotify"))
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
