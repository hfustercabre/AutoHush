import Foundation
import Observation
import AutoHushKit

/// The width of the menu's custom views; rows the menu draws itself follow.
let menuContentWidth: CGFloat = 345

/// What the menu's own controls do.
enum StatusMenuCommand: Equatable, Sendable {
    case toggleAutoPause
    case snooze(AutoPauseSnooze)
    /// Whether the app stops pausing the music (`true`) or pauses it again.
    case setIgnored(AudioSource, Bool)
    /// Unfolds or folds the music players under the card.
    case togglePlayerList
    /// Shows only the unfolded players whose names match.
    case searchPlayers(String)
    /// Tries starting again after a failed start.
    case retry
    /// While AutoHush learns the player: it plays, or it's paused.
    case learningStep(StepButton)
    case openSettings
    case showDiagnostics
    /// Checks for updates, or shows the update found.
    case updates
    case showAbout
    /// Shows why the music player couldn't be controlled (the info button
    /// after the card's line).
    case showControlError
    case quit
}

/// What the menu's custom views show. Unlike the menu's rows, it follows the
/// status while the menu is open.
@MainActor
@Observable
final class StatusMenuModel {
    var status: AppStatus
    /// The apps listed under "Playing Now", fixed while the menu is open so
    /// that no row moves under the pointer.
    var listedSources: [AudioSource] = []
    /// Whether the music players are unfolded under the card.
    var isChoosingPlayer = false
    /// What was typed in the search over the unfolded players.
    var playerSearch = ""
    @ObservationIgnored var perform: @MainActor (StatusMenuCommand) -> Void = { _ in }

    init(status: AppStatus) {
        self.status = status
    }
}
