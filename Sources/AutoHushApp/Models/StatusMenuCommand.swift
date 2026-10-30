import Foundation
import AutoHushKit

/// What the menu's own controls do.
enum StatusMenuCommand: Equatable, Sendable {
    case toggleAutoPause
    case snooze(AutoPauseSnooze)
    /// Whether the app stops pausing the music (`true`) or pauses it again.
    case setIgnored(AudioSource, Bool)
    /// Shows only the players whose names match.
    case searchPlayers(String)
    /// The players' search takes the keyboard itself (a click in it).
    case typeInSearch
    /// Moves the side window's highlight through its rows (-1, 1).
    case moveHighlight(Int)
    /// Presses the highlighted row in the players' side window, or chooses
    /// the first player the search left while something is typed (Return).
    case chooseHighlighted
    /// Chooses the player with this bundle ID (or a suggested web app's ID).
    case choosePlayer(String)
    /// Removes the app added with Add an App with this bundle ID, after asking.
    case removeAddedApp(String)
    case addApp
    case addWebApp
    /// Picks apps to ignore (the ignored apps' side window).
    case ignoreAnotherApp
    /// Opens a part's side window (its row clicked), closing the other.
    case openSide(MenuSidePart)
    /// The pointer came onto (`true`) or left a row that opens a side
    /// window: resting on it a moment opens it, as a submenu.
    case hoverSideRow(MenuSidePart, Bool)
    /// The pointer came onto a part of the menu: another part than the open
    /// side window's closes it, after a moment (the user, 2026-10-18).
    case pointerEntered(MenuSection)
    /// Tries starting again after a failed start.
    case retry
    /// Tries the resume that was given up again (`AppStatus.showsResumeFailure`).
    case retryResume
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
    /// Shows why the media player couldn't be controlled (the info button
    /// after the card's line).
    case showControlError
    case quit
}

extension StatusMenuCommand {
    /// What opens a window or an alert closes the menu first, as a menu's
    /// rows do, and acts once it has closed (`StatusMenuController.run`);
    /// the rest act at once, the menu staying open. Updates keeps it open
    /// while it checks (`StatusMenuController.perform`).
    var closesMenuFirst: Bool {
        switch self {
        case .snooze, .removeAddedApp, .addApp, .addWebApp, .ignoreAnotherApp, .resolveWarning, .reopenAutoHush, .useAntiDotMode,
             .showUpdate, .openSettings, .showDiagnostics, .updates, .showAbout, .showControlError, .learnControls,
             .reopenPlayer, .unmutePlayer, .quit:
            true
        case .toggleAutoPause, .setIgnored, .choosePlayer, .searchPlayers, .typeInSearch, .moveHighlight, .chooseHighlighted,
             .openSide, .hoverSideRow, .pointerEntered, .retry, .retryResume:
            false
        }
    }
}
