import Foundation
import Observation
import AutoHushKit

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
    /// Reopens the player as it needs to be opened (`AppStatus.playerNeedsReopen`).
    case reopenPlayer
    /// Lifts the mute of a player that's muted instead of paused, until the
    /// other apps stop (`AppStatus.offersUnmute`).
    case unmutePlayer
    /// Shows or folds away More Settings, below Ignored Apps.
    case toggleMoreSettings
    /// The settings changed what More Settings shows: its rows follow.
    case updateMoreSettings
    /// Learns the chosen web app's controls in a new learning window.
    case learnControls
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
    /// The apps listed under "Recently Played", fixed the same way.
    var listedRecentSources: [AudioSource] = []
    /// Whether the music players are unfolded under the card.
    var isChoosingPlayer = false
    /// Whether More Settings shows: folded at first, then as the user left
    /// it, while AutoHush runs.
    var showsMoreSettings = false
    /// More Settings' rows whose content shows: all but those arriving or
    /// going while its rows are revealed (they fade and drift).
    var moreSettingsArrived = Set(MoreSettingsRow.allCases)
    /// What was typed in the search over the unfolded players.
    var playerSearch = ""
    /// An update check asked from the menu runs: its Updates button says so.
    var isCheckingForUpdates = false
    /// Retry was clicked: VoiceOver hears the card's line once the start is
    /// over, as it shows how it went.
    @ObservationIgnored var announcesRetryOutcome = false
    @ObservationIgnored var perform: @MainActor (StatusMenuCommand) -> Void = { _ in }

    init(status: AppStatus) {
        self.status = status
    }
}
