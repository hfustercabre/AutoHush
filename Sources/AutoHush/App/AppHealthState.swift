import Foundation

/// Whether the app could start monitoring, and if not, why.
enum AppHealthState: Equatable, Sendable {
    case starting
    case ready
    case degraded(String)
    case needsPermission(String)
    case failed(String)
}

extension AppHealthState {
    /// The health shown when the startup check against Spotify fails.
    init(startupError error: any Error) {
        switch error as? AutoHushError {
        case .automationPermissionDenied:
            self = .needsPermission("Grant Automation access to control Spotify")
        case .spotifyUnavailable:
            self = .degraded("Spotify is not running")
        case .spotifyNotResponding:
            self = .degraded("Spotify is not responding")
        case .spotifyCommandFailed(let message):
            self = .degraded("Spotify control error: \(message)")
        case nil:
            self = .failed(error.localizedDescription)
        }
    }
}
