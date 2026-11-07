import AutoHushKit

/// Which control paused and played the player last, since AutoHush started.
package struct LastControls: Sendable, Equatable {
    package var paused: WayOrder.Kind?
    package var played: WayOrder.Kind?

    package init(paused: WayOrder.Kind? = nil, played: WayOrder.Kind? = nil) {
        self.paused = paused
        self.played = played
    }

    mutating func note(_ kind: WayOrder.Kind, for target: PlayerState) {
        if target == .playing { played = kind } else { paused = kind }
    }
}
