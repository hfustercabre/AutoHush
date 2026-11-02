import Foundation

/// What AntiDot mode leaves out, said the same way wherever it shows (E7,
/// the full check, 2026-10-19: one wording per fact). AntiDot mode hears no
/// sound, so it can't work with a player only its sound tells about, nor
/// level the volume, and it doesn't need Audio Recording.
enum AntiDotText {
    /// An app added with Add an App that can only be muted: why it couldn't
    /// be controlled in AntiDot mode (the alert after the menu's card; out of
    /// it, `muteNeedsRecording`), why AntiDot mode is off while it's the
    /// player (Settings → Behavior), and why it can't be chosen in AntiDot
    /// mode (its row's and tile's help and VoiceOver hint).
    static func onlyMuted(_ player: String) -> String {
        String(localized: "AutoHush can only mute \(player), and muting needs Audio Recording, which AntiDot mode doesn’t use.",
               comment: "Why the media player (added with Add an App, muted instead of paused) couldn't be controlled, in the alert after the menu's card while AntiDot mode is on; Settings → Behavior, under the AntiDot mode switch, dimmed while it's the player; and the help tag and VoiceOver hint of its row and tile where media players are offered, dimmed while AntiDot mode is on; %@ is the player")
    }

    /// An app added with Add an App whose Now Playing row doesn't show
    /// whether it plays, so only its sound tells: the same three places, the
    /// alert out of AntiDot mode only (in it, `notHeardInAntiDotMode`).
    static func onlyHeard(_ player: String) -> String {
        String(localized: "AutoHush needs Audio Recording to hear whether \(player) is playing.",
               comment: "Why the media player (added with Add an App, whose Now Playing row doesn't show its state, so only its sound tells) couldn't be paused or played, in the alert after the menu's card while AntiDot mode is off; Settings → Behavior, under the AntiDot mode switch, dimmed while it's the player; and the help tag and VoiceOver hint of its row and tile where media players are offered, dimmed while AntiDot mode is on; %@ is the player")
    }

    /// An app added with Add an App that can only be muted, while AntiDot
    /// mode is off and Audio Recording isn't allowed: why it couldn't be
    /// controlled, in the alert after the menu's card (T5, 2026-11-02:
    /// `onlyMuted` blamed AntiDot mode, which was off).
    static func muteNeedsRecording(_ player: String) -> String {
        String(localized: "AutoHush can only mute \(player), and muting needs Audio Recording.",
               comment: "Why the media player (added with Add an App, muted instead of paused) couldn't be controlled, in the alert after the menu's card, while AntiDot mode is off and Audio Recording isn't allowed; %@ is the player")
    }

    /// An app added with Add an App that only its sound tells about, while
    /// AntiDot mode is on: why it couldn't be controlled, in the alert after
    /// the menu's card (T5, 2026-11-02: `onlyHeard` doesn't say AntiDot
    /// mode is what keeps it from being heard).
    static func notHeardInAntiDotMode(_ player: String) -> String {
        String(localized: "AutoHush needs Audio Recording to hear whether \(player) is playing, which AntiDot mode doesn’t use.",
               comment: "Why the media player (added with Add an App, whose Now Playing row doesn't show its state, so only its sound tells) couldn't be paused or played, in the alert after the menu's card, while AntiDot mode is on; %@ is the player")
    }

    /// Under a switch that needs sound measured (Level the volume), dimmed:
    /// Settings → Behavior and Fine-Tuning.
    static var featureOff: String {
        String(localized: "Off in AntiDot mode",
               comment: "Under the dimmed Level the volume switch while AntiDot mode is on (it measures no sound): Settings → Behavior, and Fine-Tuning's volume limits")
    }

    /// Audio Recording, which it doesn't use: Diagnostics' row, the welcome
    /// window and the Add an App window.
    static var notNeeded: String {
        String(localized: "Not needed in AntiDot mode",
               comment: "Audio Recording while AntiDot mode is on, which doesn't use it: its row in Diagnostics, and the note under “Audio Recording” in the welcome window and the Add an App window")
    }
}
