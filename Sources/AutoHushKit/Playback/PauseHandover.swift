import Foundation

/// A pause handed over by an AutoHush that quit while holding the music
/// paused, for the next one to take over.
package struct PauseHandover: Equatable, Sendable {
    package let at: Date
    /// The paused music player's bundle ID; AutoHush 0.8.2 and earlier
    /// didn't say.
    package let player: String?
    /// The chosen player's pause is handed over; `false` when only `held`
    /// ones are.
    package let holdsChosen: Bool
    /// Players held paused when the user had chosen another (their
    /// monitoring ran on to end those pauses): the next AutoHush ends them.
    package let held: [String]

    package init(at: Date, player: String?, holdsChosen: Bool = true, held: [String] = []) {
        self.at = at
        self.player = player
        self.holdsChosen = holdsChosen
        self.held = held
    }
}
