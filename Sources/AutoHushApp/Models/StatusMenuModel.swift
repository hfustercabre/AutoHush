import Foundation
import Observation
import AutoHushKit

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
    /// Whether the players' side window is open, beside the card's Change
    /// Player row.
    var isChoosingPlayer = false
    /// What was typed in the search over the players.
    var playerSearch = ""
    /// Counts the times the players' search takes the keyboard: its field
    /// takes the focus each time (`StatusMenuController.searchTakesKeyboard`).
    var searchFocus = 0
    /// The highlight the arrow keys and the pointer move through the menu's
    /// controls, as in macOS's menus; the side window's, through its rows.
    @ObservationIgnored let keyboard = KeyHighlight()
    @ObservationIgnored let sideKeyboard = KeyHighlight()
    /// The settings the menu reads (AntiDot mode, the card's checks), as
    /// Settings changes them.
    @ObservationIgnored weak var settings: SettingsModel?
    /// Whether AntiDot mode is on: an app that can only be muted can't be
    /// chosen then. Read live from the settings, so the players follow a
    /// switch in Settings at once; without them, as the menu opened.
    var isAntiDotMode: Bool {
        get { settings?.isAntiDotMode ?? antiDotModeAtOpening }
        set { antiDotModeAtOpening = newValue }
    }
    private var antiDotModeAtOpening = false
    /// Option is held: an added app's row removes it instead.
    var isOptionHeld = false
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
    /// The menu is as tall as the screen lets it be, its content taller:
    /// only then does it show that more is below. Never while it grows to
    /// fit what unfolded, whose rows dimmed and flashed for a moment (the
    /// user, 2026-10-18).
    var isCappedByScreen = false
    /// The same for the side window.
    var isSideCappedByScreen = false
    /// An update check asked from the menu runs: its Updates button says so.
    var isCheckingForUpdates = false
    /// Try Again was clicked: VoiceOver hears the card's line once the start is
    /// over, as it shows how it went.
    @ObservationIgnored var announcesRetryOutcome = false
    /// Try Again on "Couldn't resume" was clicked: VoiceOver hears the card's
    /// line once the resume is over (played, or given up again), not the
    /// line shown while it tries.
    @ObservationIgnored var announcesResumeOutcome = false
    @ObservationIgnored var perform: @MainActor (StatusMenuCommand) -> Void = { _ in }

    init(status: AppStatus) {
        self.status = status
    }

    /// The players, as the search narrows them.
    var players: MenuPlayerList {
        MenuPlayerList(options: status.playerOptions, chosenID: status.chosenPlayerID,
                       antiDotMode: isAntiDotMode, search: playerSearch)
    }

    /// The menu's parts, in order: the card (with the media player's row,
    /// H4, the user's pick, 2026-10-25), a warning and its fix (not the
    /// player's own missing permission, which the card asks for), Turn off
    /// for, the apps playing and played, Ignored Apps, the update found, and
    /// the buttons. The settings are Settings' only (A1, the user's pick,
    /// 2026-10-25).
    var sections: [MenuSection] {
        var sections: [MenuSection] = [.card]
        if let warning = status.warning {
            if status.missingPermission == nil {
                sections.append(status.offersReopen ? .reopenAutoHush : .warning(warning))
            }
            // Not for a player that can only be muted: AntiDot mode can't mute it.
            if warning == .systemAudioRecording, !status.playerNeedsLevels { sections.append(.useAntiDot) }
        }
        sections.append(.snooze)
        if !listedSources.isEmpty { sections.append(.playingNow) }
        if !listedRecentSources.isEmpty { sections.append(.recentlyPlayed) }
        // Always, so the first app to ignore can be added from the menu (the user, 2026-10-18).
        sections.append(.ignoredApps)
        if status.updateOffer != nil { sections.append(.update) }
        sections.append(.toolbar)
        return sections
    }
}
