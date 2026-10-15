import Foundation

/// A music player's state. Raw values are used in log messages.
package enum PlayerState: String, Sendable {
    case playing
    case paused
    case stopped
    case notRunning = "not running"
    case unknown
}

extension PlayerState {
    /// For a player whose one Play/Pause control toggles: whether pressing it
    /// now leaves `state`, the player being in it. In the other state
    /// already, `false`: nothing to press, which would undo it. Otherwise it
    /// throws why it can't tell or can't: not running, its state unknown,
    /// or stopped, with nothing to play.
    package func needsToggle(from state: PlayerState) throws -> Bool {
        if self == state { return true }
        switch self {
        case .notRunning: throw MusicPlayerError.playerNotRunning
        case .unknown: throw MusicPlayerError.playerCommandFailed(.stateUnknown)
        case .stopped: throw MusicPlayerError.playerCommandFailed(.nothingToPlay)
        case .playing, .paused: return false
        }
    }
}
