import Foundation

/// What learning weighs about a button whose words changed, besides its
/// place. A player's bar is in sight, among the player's other controls; a
/// song's own button (a tile, a row) can be scrolled out of sight and has
/// none around it (measured on SoundCloud and YouTube Music).
package struct ButtonStanding: Equatable, Sendable {
    /// Inside its window: not scrolled below or above it.
    let isInWindow: Bool
    /// Something just around it holds a slider or a progress bar, as a
    /// player's bar does (its progress, its volume).
    package let isWithPlayerControls: Bool

    init(isInWindow: Bool = true, isWithPlayerControls: Bool = false) {
        self.isInWindow = isInWindow
        self.isWithPlayerControls = isWithPlayerControls
    }
}
