import Foundation

/// A pause handed over by an AutoHush that quit while holding the music
/// paused, for the next one to take over.
package struct PauseHandover: Equatable, Sendable {
    package let at: Date
    /// The paused music player's bundle ID; AutoHush 0.8.2 and earlier
    /// didn't say.
    package let player: String?

    package init(at: Date, player: String?) {
        self.at = at
        self.player = player
    }
}
