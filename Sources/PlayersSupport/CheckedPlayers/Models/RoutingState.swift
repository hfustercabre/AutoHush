import Foundation
import AutoHushKit

/// What pressing a player by its ways keeps between presses
/// (`BackupRouting`), held by each player it routes (`CheckedPlayer`,
/// `BackedUpPlayer`).
struct RoutingState: Sendable {
    /// Its own way's permission is missing (Automation, Accessibility) while
    /// a backup can be pressed: why, and its own way passed over at each
    /// press until macOS allows it again (the user, 2026-11-05); `nil`
    /// otherwise (`passesOverOwnWay`).
    var ownWayDenied: MusicPlayerError?
    /// The ways tried in this muted pause, by their place in `wayOrder`
    /// (`pauseWhileMuted`): the Play/Pause key and the panel once only (the
    /// user, 2026-11-04); a pause or a play starts again.
    var mutedTried: Set<Int> = []
    /// Each pause or play begun counts one: one going down its ways stops
    /// once another has begun.
    var pressCalls = 0
    /// When a play by the panel last failed (`panelPlayRest`).
    var panelPlayFailedAt: Date?
}
