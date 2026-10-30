import Foundation
import AutoHushKit

/// Why a player couldn't be controlled, in the user's words, and where
/// Now Playing is shown in the menu bar.
extension ControlFailure {
    /// Where Now Playing is shown in the menu bar or hidden: System
    /// Settings' Menu Bar from macOS 26, its Control Center before.
    static var nowPlayingSettings: String {
        if #available(macOS 26, *) {
            String(localized: "System Settings → Menu Bar",
                   comment: "Where Now Playing is shown in the menu bar or hidden, as macOS names it (macOS 26 and later), inside a sentence")
        } else {
            String(localized: "System Settings → Control Center",
                   comment: "Where Now Playing is shown in the menu bar or hidden, as macOS names it (macOS 14 and 15), inside a sentence")
        }
    }

    /// The button that opens that pane (`SystemSettingsPane.menuBar`), so
    /// Now Playing can be shown.
    static var openMenuBarSettings: String {
        if #available(macOS 26, *) {
            String(localized: "Open Menu Bar Settings…",
                   comment: "Button in the alert about Now Playing being hidden in the menu bar, and in the Add an App window: opens System Settings → Menu Bar (macOS 26 and later), where it can be shown")
        } else {
            String(localized: "Open Control Center Settings…",
                   comment: "Button in the alert about Now Playing being hidden in the menu bar, and in the Add an App window: opens System Settings → Control Center (macOS 14 and 15), where it can be shown")
        }
    }

    /// The failure as the user reads it, about `player`.
    func text(player: String) -> String {
        switch self {
        case .menuItemNotFound:
            String(localized: "AutoHush can’t find Play/Pause in \(player)’s menus.",
                   comment: "Why the media player couldn't be controlled: an update may have changed its menus; %@ is the player")
        case .stateUnknown:
            String(localized: "\(player) doesn’t say whether it’s playing.",
                   comment: "Why the media player couldn't be controlled: its state can't be read; %@ is the player")
        case .nothingToPlay:
            String(localized: "\(player) has nothing to play.",
                   comment: "Why the media player couldn't be controlled: its Play is disabled; %@ is the player")
        case .buttonDisabled:
            String(localized: "\(player)’s Play/Pause button is disabled, as during an ad.",
                   comment: "Why a web app couldn't be paused: the site disabled its button; %@ is the web app")
        case .pressFailed:
            String(localized: "AutoHush couldn’t press \(player)’s Play/Pause.",
                   comment: "Why the media player couldn't be controlled; %@ is the player")
        case .pressIgnored:
            String(localized: "\(player) didn’t respond to its Play/Pause.",
                   comment: "Why the media player couldn't be controlled: a press didn't change it; %@ is the player")
        case .muteUnavailable:
            AntiDotText.onlyMuted(player)
        case .hearingUnavailable:
            AntiDotText.onlyHeard(player)
        case .nowPlayingHidden:
            String(localized: "AutoHush controls \(player) with Now Playing in the menu bar, which is hidden: show it in \(Self.nowPlayingSettings).",
                   comment: "Why the media player (added with Add an App, paused and played through the menu bar's Now Playing panel) couldn't be paused or resumed; the first %@ is the player, the second where the setting is, e.g. “System Settings → Menu Bar”")
        case .appleEventError(let number):
            String(localized: "\(player) answered with an error (\(String(number))).",
                   comment: "Why the media player couldn't be controlled; the first %@ is the player, the second the error's number, e.g. -1708")
        }
    }
}
