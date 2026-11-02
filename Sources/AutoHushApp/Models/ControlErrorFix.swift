import Foundation
import AutoHushKit

/// The one button that can help in the alert behind the info button after
/// the card's orange line (U2a, the user's pick, 2026-11-02): first, the
/// default (Return), with OK after it (Escape). Picked by what failed and the
/// kind of player, since a press fails the same way for every kind; none
/// where nothing can help (a web app's button disabled during an ad, a
/// state that can't be read, nothing to play).
enum ControlErrorFix: Equatable {
    /// Now Playing hidden in the menu bar: the pane where it's shown.
    case openMenuBarSettings
    /// A resume given up: the resume once more (the user, 2026-10-25).
    case retryResume
    /// A supported app's pause that failed: the pause once more.
    case retryPause
    /// A supported app AutoHush can't control: starting over, as the card's
    /// Try Again does.
    case retryStart
    /// A supported app's Play/Pause gone from its menus: an update of
    /// AutoHush may know its new menus.
    case checkForUpdates
    /// A web app that didn't follow its learned button: learning it again.
    case learnAgain
    /// An app added with Add an App whose way stopped working: Add an App on
    /// it, to check it again.
    case checkAgain
    /// An app added with Add an App that only its sound tells about, in
    /// AntiDot mode, which hears none.
    case turnOffAntiDot
    /// The same out of AntiDot mode, Audio Recording not allowed.
    case allowAudioRecording
    /// The same, Audio Recording allowed in System Settings: macOS applies it
    /// once AutoHush reopens.
    case reopenAutoHush

    /// What the alert is about.
    enum Situation: Equatable {
        /// The card says "Couldn't resume".
        case resumeGivenUp
        /// The card says "Couldn't pause" while an app plays.
        case pauseFailed
        /// The card says AutoHush can't control the player; it keeps trying.
        case cantControl
    }

    /// The fix for `failure` (`nil`: an error with no failure of the
    /// player's own) of a player of `kind`. `antiDot`: AntiDot mode is on;
    /// `audio`: where Audio Recording stands.
    static func fix(for failure: ControlFailure?, kind: MusicPlayerKind, situation: Situation,
                    antiDot: Bool, audio: PermissionAccess) -> ControlErrorFix? {
        if failure == .nowPlayingHidden { return .openMenuBarSettings }
        if situation == .resumeGivenUp { return .retryResume }
        guard let failure else { return nil }
        switch (kind, failure) {
        case (.safariWebApp, .pressIgnored), (.safariWebApp, .pressFailed):
            return .learnAgain
        case (.checkedApp, .pressIgnored), (.checkedApp, .pressFailed), (.checkedApp, .menuItemNotFound),
             (.checkedApp, .appleEventError):
            return .checkAgain
        case (.checkedApp, .muteUnavailable), (.checkedApp, .hearingUnavailable):
            if antiDot { return .turnOffAntiDot }
            return switch audio {
            case .needsReopen: .reopenAutoHush
            case .notAsked, .denied: .allowAudioRecording
            default: nil // allowed: nothing a button can change
            }
        case (.app, .pressIgnored), (.app, .pressFailed), (.app, .appleEventError):
            return situation == .pauseFailed ? .retryPause : .retryStart
        case (.app, .menuItemNotFound):
            return .checkForUpdates
        default:
            return nil
        }
    }

    /// The button's title.
    var title: String {
        switch self {
        case .openMenuBarSettings: ControlFailure.openMenuBarSettings
        case .retryResume, .retryPause, .retryStart: TryAgainText.title
        case .checkForUpdates:
            String(localized: "Check for Updates",
                   comment: "Button in the alert that says why AutoHush can't control a supported media player (its Play/Pause wasn't found in its menus): checks for a newer AutoHush, which may know the player's new menus")
        case .learnAgain: LearnText.learnAgainButton
        case .checkAgain:
            String(localized: "Check Again…",
                   comment: "Button in the alert that says why AutoHush couldn't pause or control an app added with Add an App: opens the Add an App window on that app, to check it again")
        case .turnOffAntiDot: AddAppText.turnOffAntiDot
        case .allowAudioRecording: Permission.systemAudioRecording.grantTitle
        case .reopenAutoHush: PermissionText.reopen
        }
    }
}
