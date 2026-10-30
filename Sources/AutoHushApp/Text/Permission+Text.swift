import Foundation
import AutoHushKit

/// The permissions as the menu, the card's line and the learning window
/// ask for them.
extension Permission {
    /// The menu item that leads the user to grant it.
    var grantTitle: String {
        switch self {
        case .automation(let player):
            return String(localized: "Allow \(player) Automation Access…",
                          comment: "Menu item; %@ is the media player")
        case .accessibility:
            return String(localized: "Allow Accessibility Access…",
                          comment: "Menu item: lets AutoHush control a media player through its menu")
        case .systemAudioRecording:
            return String(localized: "Allow Audio Recording Access…", comment: "Menu item")
        }
    }

    /// The status line while the player needs it, said once: the menu's
    /// card has Allow… under it, instead of a row asking again (I2, P3, the
    /// user's pick, 2026-10-19).
    var missingLine: String {
        switch self {
        case .automation:
            String(localized: "Needs Automation access",
                   comment: "Status line, under the media player's name (the menu's card, Settings → General), while AutoHush may not control it through Automation; in the menu, Allow… under it asks for it")
        case .accessibility:
            String(localized: "Needs Accessibility access",
                   comment: "Status line, under the media player's name (the menu's card, Settings → General), while AutoHush may not control it through Accessibility (its menu, its page, the Now Playing panel); in the menu, Allow… under it asks for it")
        case .systemAudioRecording:
            String(localized: "Needs Audio Recording access",
                   comment: "Status line, under the media player's name (the menu's card, Settings → General), while AutoHush can't hear it (an app added with Add an App that only its sound tells about); in the menu, Allow… under it asks for it")
        }
    }

    /// The step that asks for it in the learning window. Only a web app
    /// learns, and it's controlled through Accessibility: the others never
    /// come there, so they say the same.
    var statusLine: String {
        let player = switch self {
        case .automation(let player), .accessibility(let player): player
        case .systemAudioRecording: "" // controls no player
        }
        return String(localized: "Allow Accessibility access to control \(player)",
                      comment: "The learning window: the step that asks for Accessibility before the web app's controls can be learned; %@ is the web app")
    }
}
