import Foundation

/// What AntiDot mode leaves out, said the same way wherever it shows (E7,
/// the full check, 2026-10-19: one wording per fact). AntiDot mode hears no
/// sound, so it can't work with a player only its sound tells about, nor
/// level the volume, and it doesn't need Audio Recording.
enum AntiDotText {
    /// An app added with Add an App that can only be muted: why it couldn't
    /// be controlled (the menu's card), and why AntiDot mode is off while
    /// it's the player (Settings → Detection).
    static func onlyMuted(_ player: String) -> String {
        String(localized: "AutoHush can only mute \(player), and muting needs Audio Recording, which AntiDot mode doesn’t use.",
               comment: "Why the media player (added with Add an App, muted instead of paused) couldn't be controlled, in the menu; and Settings → Detection, under the AntiDot mode switch, dimmed while it's the player; %@ is the player")
    }

    /// An app added with Add an App whose Now Playing row doesn't show
    /// whether it plays, so only its sound tells: the same two places.
    static func onlyHeard(_ player: String) -> String {
        String(localized: "AutoHush needs Audio Recording to hear whether \(player) is playing.",
               comment: "Why the media player (added with Add an App, whose Now Playing row doesn't show its state, so only its sound tells) couldn't be paused or played, in the menu; and Settings → Detection, under the AntiDot mode switch, dimmed while it's the player; %@ is the player")
    }

    /// Under a switch that needs sound measured (Level the volume), dimmed:
    /// the menu and Settings → Behavior.
    static var featureOff: String {
        String(localized: "Off in AntiDot mode",
               comment: "Under the dimmed Level the volume switch while AntiDot mode is on (it measures no sound): the menu and Settings → Behavior")
    }

    /// Audio Recording, which it doesn't use: Diagnostics' row, the welcome
    /// window and the Add an App window.
    static var notNeeded: String {
        String(localized: "Not needed in AntiDot mode",
               comment: "Audio Recording while AntiDot mode is on, which doesn't use it: its row in Diagnostics, and the note under “Audio Recording” in the welcome window and the Add an App window")
    }
}
