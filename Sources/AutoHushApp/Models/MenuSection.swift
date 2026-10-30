import Foundation
import AutoHushKit

/// A part of the menu, in the order it shows (`StatusMenuModel.sections`).
enum MenuSection: Equatable {
    /// What tells it apart in the menu, as SwiftUI identifies it: a part
    /// that comes while the menu is open leaves the others as they were
    /// (the full check, 2026-10-18).
    var id: String { String(describing: self) }

    case card
    /// What the chosen player lacks, with the way to fix it.
    case warning(Permission)
    /// Once the user went to allow Audio Recording: Reopen AutoHush.
    case reopenAutoHush
    /// Under Audio Recording's warning: AntiDot mode instead.
    case useAntiDot
    /// The card's Change Player row: not a part of its own, only where the
    /// pointer is, so the players' side window closes once the pointer
    /// rests on the rest of the card, as on any other part (the user,
    /// 2026-10-25).
    case playerRow
    case snooze
    case playingNow
    case recentlyPlayed
    case ignoredApps
    /// The update found, or being installed.
    case update
    case toolbar
}
