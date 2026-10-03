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
    /// The health shown when the startup check against the music player fails.
    init(startupError error: any Error, playerName: String) {
        switch error as? AutoHushError {
        case .automationPermissionDenied:
            self = .needsPermission("Grant Automation access to control \(playerName)")
        case .playerNotRunning:
            self = .degraded("\(playerName) is not running")
        case .playerNotResponding:
            self = .degraded("\(playerName) is not responding")
        case .playerCommandFailed(let message):
            self = .degraded("\(playerName) control error: \(message)")
        case nil:
            self = .failed(error.localizedDescription)
        }
    }
}
