import Foundation

/// A music player's state. Raw values are used in log messages.
enum PlayerState: String, Sendable {
    case playing
    case paused
    case stopped
    case notRunning = "not running"
    case unknown
}
