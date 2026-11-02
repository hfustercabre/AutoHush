import Foundation

/// What's said under an app that plays, in the menu's Playing Now and
/// Settings → Sound Sources: what it does to your player, or that it's
/// ignored.
enum SourceText {
    /// Under an app: ignored (`IgnoredText.label`), or what it does to the
    /// player while it plays (`interruptsLabel(mutes:)`).
    static func subtitle(isIgnored: Bool, mutes: Bool) -> String {
        isIgnored ? IgnoredText.label : interruptsLabel(mutes: mutes)
    }

    /// Under an app that pauses the player while it plays (the menu's Playing
    /// Now, Settings → Sound Sources), or mutes it, while the player is muted
    /// rather than paused (`AppStatus.mutesNow`).
    static func interruptsLabel(mutes: Bool) -> String {
        mutes ? String(localized: "Mutes your player", comment: "The menu's Playing Now and Settings → Sound Sources: under an app that mutes your player while it plays (a player added with Add an App that can only be muted, or one muted in place of a pause that didn't take)")
            : String(localized: "Pauses your player", comment: "The menu's Playing Now and Settings → Sound Sources: under an app that pauses your player while it plays")
    }

    /// Under an app in the menu's Playing Now that counts as playing only
    /// because its sound is open (`AudioSource.isOpenOutputOnly`), in place
    /// of `interruptsLabel(mutes:)`.
    static var soundOnLabel: String {
        String(localized: "Sound on, may be paused",
               comment: "The menu's Playing Now: under an app that counts as playing only because its sound is on (AntiDot mode, or no Audio Recording access): it may really be paused")
    }

    /// The help tag of an app that says `soundOnLabel`, and its VoiceOver
    /// hint after it.
    static var soundOnHelp: String {
        String(localized: "Close it, or ignore it, if it isn’t playing.",
               comment: "The menu's Playing Now: help tag and VoiceOver hint of an app that counts as playing only because its sound is on (“Sound on, may be paused”); ignoring it is its switch")
    }

    /// The VoiceOver hint of an app that says `soundOnLabel`: that, then
    /// `soundOnHelp`.
    static var soundOnHint: String {
        String(localized: "\(soundOnLabel). \(soundOnHelp)",
               comment: "The menu's Playing Now: VoiceOver hint of an app that counts as playing only because its sound is on: the line under it (the first %@, “Sound on, may be paused”, already translated), then what to do (the second %@, already translated), as two sentences")
    }
}
