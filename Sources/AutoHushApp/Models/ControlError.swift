import Foundation
import AutoHushKit

/// Why a player couldn't be controlled, the last time it couldn't: in the
/// user's language for the menu and Diagnostics, and in English (as the log
/// has it) for a bug report.
struct ControlError: Equatable {
    /// E.g. "AutoHush can't find Play/Pause in Jukebox's menus."
    let text: String
    /// E.g. "Controlling the media player failed: its Play/Pause menu item wasn’t found."
    let detail: String
    /// What failed, when the player said (`MusicPlayerError.playerCommandFailed`):
    /// it picks the alert's button (`ControlErrorFix`).
    private(set) var failure: ControlFailure?

    /// `detail`, unless it says what `text` does (an error AutoHush has no
    /// words of its own for): then it's said once.
    var ownDetail: String? { detail == text ? nil : detail }

    /// `antiDot`: AntiDot mode is on, which a player only its sound tells
    /// about can't work with (said only then).
    init(_ error: any Error, player: String, antiDot: Bool = false) {
        detail = error.localizedDescription
        switch error as? MusicPlayerError {
        case .playerCommandFailed(let failure)?:
            text = failure.text(player: player, antiDot: antiDot)
            self.failure = failure
        case .automationPermissionDenied?, .accessibilityPermissionDenied?:
            text = String(localized: "AutoHush may no longer control \(player).",
                          comment: "Why the media player couldn't be controlled: its permission was taken away; %@ is the player")
        case .playerNotRunning?:
            text = String(localized: "\(player) isn’t running.",
                          comment: "Why the media player couldn't be controlled: it quit; %@ is the player")
        case .playerNotResponding?:
            text = String(localized: "\(player) isn’t responding.",
                          comment: "Why the media player couldn't be controlled; %@ is the player")
        case .stillLearning?, nil:
            text = error.localizedDescription
        }
    }
}
