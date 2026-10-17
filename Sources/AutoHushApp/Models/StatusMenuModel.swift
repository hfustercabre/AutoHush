import Foundation
import Observation
import AutoHushKit

/// What the menu's own controls do.
enum StatusMenuCommand: Equatable, Sendable {
    case toggleAutoPause
    case snooze(AutoPauseSnooze)
    /// Whether the app stops pausing the music (`true`) or pauses it again.
    case setIgnored(AudioSource, Bool)
    /// Unfolds or folds the music players inside the card.
    case togglePlayerList
    /// Shows only the unfolded players whose names match.
    case searchPlayers(String)
    /// Moves the keyboard's highlight among the unfolded players (-1, 1).
    case moveHighlight(Int)
    /// Chooses the highlighted player (Return).
    case chooseHighlighted
    /// Chooses the player with this bundle ID (or a suggested web app's ID).
    case choosePlayer(String)
    /// Removes the app added with Add an App with this bundle ID, after asking.
    case removeAddedApp(String)
    case addApp
    case addWebApp
    /// Shows or folds away the settings' timings, under their switches.
    case toggleMoreSettings
    /// Shows or folds away the ignored apps, under Ignored Apps.
    case toggleIgnoredApps
    /// Tries starting again after a failed start.
    case retry
    /// Reopens the player as it needs to be opened (`AppStatus.playerNeedsReopen`).
    case reopenPlayer
    /// Lifts the mute of a player that's muted instead of paused, until the
    /// other apps stop (`AppStatus.offersUnmute`).
    case unmutePlayer
    /// Learns the chosen web app's controls in a new learning window.
    case learnControls
    /// Asks for the permission the warning under the card is about.
    case resolveWarning(Permission)
    /// Reopens AutoHush, once the user went to allow Audio Recording.
    case reopenAutoHush
    case useAntiDotMode
    /// Shows the update found (the row above the buttons).
    case showUpdate
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

/// A part of the menu, in the order it shows (`StatusMenuModel.sections`).
enum MenuSection: Equatable {
    case card
    /// What the chosen player lacks, with the way to fix it.
    case warning(Permission)
    /// Once the user went to allow Audio Recording: Reopen AutoHush.
    case reopenAutoHush
    /// Under Audio Recording's warning: AntiDot mode instead.
    case useAntiDot
    case snooze
    case playingNow
    case recentlyPlayed
    case ignoredApps
    /// Detection's, Fades' and Advanced's switches, their timings folded.
    case settings
    /// The update found, or being installed.
    case update
    case toolbar
}

/// What the menu shows. Unlike the status, the apps listed are fixed while
/// it's open, so no row moves under the pointer.
@MainActor
@Observable
final class StatusMenuModel {
    var status: AppStatus
    /// The apps listed under "Playing Now", fixed while the menu is open.
    var listedSources: [AudioSource] = []
    /// The apps listed under "Recently Played", fixed the same way.
    var listedRecentSources: [AudioSource] = []
    /// Whether the music players are unfolded inside the card.
    var isChoosingPlayer = false
    /// What was typed in the search over the unfolded players.
    var playerSearch = ""
    /// The player the arrow keys moved to, chosen with Return.
    var highlightedPlayerID: String?
    /// Whether AntiDot mode is on: an app that can only be muted can't be
    /// chosen then.
    var isAntiDotMode = false
    /// Option is held: an added app's row removes it instead.
    var isOptionHeld = false
    /// Whether the settings' timings show: folded at first, then as the
    /// user left them, while AutoHush runs.
    var showsMoreSettings = false
    /// Whether the ignored apps show under Ignored Apps.
    var showsIgnoredApps = false
    /// The menu shows Detection's, Fades' and Advanced's settings.
    var hasSettings = false
    /// An update check asked from the menu runs: its Updates button says so.
    var isCheckingForUpdates = false
    /// Retry was clicked: VoiceOver hears the card's line once the start is
    /// over, as it shows how it went.
    @ObservationIgnored var announcesRetryOutcome = false
    @ObservationIgnored var perform: @MainActor (StatusMenuCommand) -> Void = { _ in }

    init(status: AppStatus) {
        self.status = status
    }

    /// The unfolded players, as the search narrows them.
    var players: MenuPlayerList {
        MenuPlayerList(options: status.playerOptions, chosenID: status.chosenPlayerID,
                       antiDotMode: isAntiDotMode, search: playerSearch)
    }

    /// The menu's parts, in order: the card, a warning and its fix, Turn
    /// off for, the apps playing and played, Ignored Apps (while one is),
    /// the settings, the update found, and the buttons.
    var sections: [MenuSection] {
        var sections: [MenuSection] = [.card]
        if let warning = status.warning {
            sections.append(status.offersReopen ? .reopenAutoHush : .warning(warning))
            // Not for a player that can only be muted: AntiDot mode can't mute it.
            if warning == .systemAudioRecording, !status.playerNeedsLevels { sections.append(.useAntiDot) }
        }
        sections.append(.snooze)
        if !listedSources.isEmpty { sections.append(.playingNow) }
        if !listedRecentSources.isEmpty { sections.append(.recentlyPlayed) }
        if !status.ignoredApps.isEmpty { sections.append(.ignoredApps) }
        if hasSettings { sections.append(.settings) }
        if status.updateOffer != nil { sections.append(.update) }
        sections.append(.toolbar)
        return sections
    }
}
