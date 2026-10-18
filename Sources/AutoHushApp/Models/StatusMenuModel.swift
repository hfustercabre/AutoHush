import Foundation
import Observation
import AutoHushKit

/// What the menu's own controls do.
enum StatusMenuCommand: Equatable, Sendable {
    case toggleAutoPause
    case snooze(AutoPauseSnooze)
    /// Whether the app stops pausing the music (`true`) or pauses it again.
    case setIgnored(AudioSource, Bool)
    /// Opens or closes the players' side window, beside Media Player's row.
    case togglePlayerList
    /// Shows only the unfolded players whose names match.
    case searchPlayers(String)
    /// Moves the side window's highlight through its rows (-1, 1).
    case moveHighlight(Int)
    /// Presses the highlighted row in the players' side window, or chooses
    /// the first player the search left (Return).
    case chooseHighlighted
    /// Chooses the player with this bundle ID (or a suggested web app's ID).
    case choosePlayer(String)
    /// Removes the app added with Add an App with this bundle ID, after asking.
    case removeAddedApp(String)
    case addApp
    case addWebApp
    /// Picks apps to ignore (the ignored apps' side window).
    case ignoreAnotherApp
    /// Shows or folds away a settings part's other settings (Detection's
    /// ways and timings, the fades' lengths), under its switch.
    case toggleSettings(MenuSettingsPart)
    /// Opens or closes the ignored apps' side window, beside their row.
    case toggleIgnoredApps
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
    /// The media player's row, under the card: the players unfold there.
    case mediaPlayer
    case snooze
    case playingNow
    case recentlyPlayed
    case ignoredApps
    /// Detection's, Fades' and Advanced's switches, each part's other
    /// settings folded (`MenuSettingsPart`).
    case settings
    /// The update found, or being installed.
    case update
    case toolbar
}

/// A settings part of the menu that has more than its switches, folded
/// away under it (F3, the user's pick, 2026-10-18): Detection's ways and
/// timings, Fades' lengths. Advanced has nothing more.
enum MenuSettingsPart: Hashable, Sendable {
    case detection, fades
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
    /// Whether the players' side window is open, beside Media Player's row.
    var isChoosingPlayer = false
    /// What was typed in the search over the unfolded players.
    var playerSearch = ""
    /// The highlight the arrow keys and the pointer move through the menu's
    /// controls, as in macOS's menus; the side window's, through its rows.
    @ObservationIgnored let keyboard = KeyHighlight()
    @ObservationIgnored let sideKeyboard = KeyHighlight()
    /// Detection's, Fades' and Advanced's settings, as Settings changes them.
    @ObservationIgnored weak var settings: SettingsModel?
    /// Whether AntiDot mode is on: an app that can only be muted can't be
    /// chosen then. Read live from the settings, so the players follow a
    /// switch in the menu's own settings at once; without them, as the menu
    /// opened.
    var isAntiDotMode: Bool {
        get { settings?.isAntiDotMode ?? antiDotModeAtOpening }
        set { antiDotModeAtOpening = newValue }
    }
    private var antiDotModeAtOpening = false
    /// Option is held: an added app's row removes it instead.
    var isOptionHeld = false
    /// The settings parts whose other settings show: folded at first, then
    /// each as the user left it, while AutoHush runs.
    var unfoldedSettings: Set<MenuSettingsPart> = []
    /// Whether the ignored apps' side window is open, beside their row.
    var showsIgnoredApps = false
    /// The apps listed in the ignored apps' side window, fixed while it's
    /// open, so one switched back on keeps its row (and can be switched off again).
    var listedIgnoredApps: [AudioSource] = []
    /// Where the rows that open a side window have their tops, in the
    /// menu's content: each side window opens level with its row.
    @ObservationIgnored var sideRowTops: [MenuSidePart: CGFloat] = [:]

    /// The side window that's open, if one is.
    var openSide: MenuSidePart? {
        isChoosingPlayer ? .players : showsIgnoredApps ? .ignoredApps : nil
    }
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

    /// The menu's parts, in order: the card, the media player, a warning
    /// and its fix, Turn off for, the apps playing and played, Ignored Apps
    /// (while one is), the settings, the update found, and the buttons.
    var sections: [MenuSection] {
        var sections: [MenuSection] = [.card, .mediaPlayer]
        if let warning = status.warning {
            sections.append(status.offersReopen ? .reopenAutoHush : .warning(warning))
            // Not for a player that can only be muted: AntiDot mode can't mute it.
            if warning == .systemAudioRecording, !status.playerNeedsLevels { sections.append(.useAntiDot) }
        }
        sections.append(.snooze)
        if !listedSources.isEmpty { sections.append(.playingNow) }
        if !listedRecentSources.isEmpty { sections.append(.recentlyPlayed) }
        // While its side window is open, even once every app is switched back on.
        if !status.ignoredApps.isEmpty || showsIgnoredApps { sections.append(.ignoredApps) }
        if hasSettings { sections.append(.settings) }
        if status.updateOffer != nil { sections.append(.update) }
        sections.append(.toolbar)
        return sections
    }
}

/// The menu's parts that open a side window beside it.
enum MenuSidePart: Hashable {
    case players, ignoredApps

    /// The menu's part its row is in.
    var section: MenuSection {
        switch self {
        case .players: .mediaPlayer
        case .ignoredApps: .ignoredApps
        }
    }
}
