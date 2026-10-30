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
}
