import Foundation

/// What the permission pieces say (`PermissionButton` and the windows that
/// ask), and Diagnostics' rows.
enum PermissionText {
    /// The heading over the permissions (Diagnostics, the welcome window).
    static var heading: String {
        String(localized: "Permissions", comment: "Settings → Diagnostics and the welcome window: the heading over the permissions AutoHush needs")
    }

    static func controlTitle(_ player: String) -> String {
        String(localized: "Control \(player)",
               comment: "Welcome window, the permission AutoHush needs to pause and resume the media player; %@ is the player")
    }

    static var audioTitle: String {
        String(localized: "Audio Recording",
               comment: "Welcome window and Diagnostics: the System Audio Recording permission (macOS’s name for it)")
    }

    /// Under the player's control permission, as it stands.
    static func controlNote(_ player: String, _ access: PermissionAccess) -> String {
        switch access {
        case .allowed, .notNeeded, .needsReopen:
            String(localized: "Pauses and resumes it for you.",
                   comment: "Welcome window, under “Control %@” once it's allowed")
        case .playerNotRunning:
            String(localized: "Open \(player) so macOS can ask.",
                   comment: "Welcome window and Settings: Automation can only be asked for while the player runs; %@ is the player")
        case .notAsked:
            askNote
        case .denied:
            String(localized: "Turn it on for AutoHush in System Settings.",
                   comment: "Welcome window, under a permission that isn't allowed")
        }
    }

    /// Under a permission macOS hasn't asked for yet: its Allow… asks.
    static var askNote: String {
        String(localized: "Click Allow, then Allow again when macOS asks.",
               comment: "Welcome window, under a permission macOS hasn't asked for yet")
    }

    /// Under Audio Recording, as it stands. Not asked yet, it's asked only
    /// by its Allow… (P1, the user's pick, 2026-11-06).
    static func audioNote(_ access: PermissionAccess) -> String {
        switch access {
        case .notAsked:
            askNote
        case .allowed, .playerNotRunning:
            String(localized: "Tells playing apps from silent ones. Never recorded.",
                   comment: "Welcome window, under “Audio Recording”: what AutoHush uses it for; it only measures how loud apps play, and never records their audio")
        case .denied:
            String(localized: "Turn it on for AutoHush in System Settings, then reopen AutoHush.",
                   comment: "Welcome window and Settings, while Audio Recording isn't allowed")
        case .needsReopen:
            // Not "Allowed": AutoHush can't tell it was switched on until it
            // reopens (R1, the user's pick, 2026-11-06).
            String(localized: "Turn it on in System Settings, then reopen AutoHush.",
                   comment: "Welcome window and Settings: after the user's Allow… opened System Settings for Audio Recording; macOS applies it only at AutoHush's next launch, and AutoHush can't tell before whether it was switched on")
        case .notNeeded:
            AntiDotText.notNeeded
        }
    }

    /// A permission that is granted (`AllowedLabel`; Diagnostics' rows).
    static var allowed: String {
        String(localized: "Allowed", comment: "Diagnostics, the welcome window and the Add an App window: a permission that is granted")
    }

    /// `permissions` (a list of their names) are allowed: Add an App's
    /// summary, and VoiceOver on the welcome window ("Audio Recording allowed").
    static func allowed(_ permissions: String) -> String {
        String(localized: "\(permissions) allowed", comment: "Add an App window, under the step “Allow what the check needs” once done; %@ lists the permissions, e.g. “Accessibility and Audio Recording”")
    }

    static var reopen: String {
        String(localized: "Reopen AutoHush",
               comment: "Menu item and button, after the user went to allow audio recording in System Settings: macOS applies it only once AutoHush is quit and opened again. Also Add an App’s step “Allow what the check needs” when Accessibility changed while AutoHush was open, and the alert that says why an app added with Add an App couldn't be paused or controlled while Audio Recording waits for the reopen")
    }

    static var useAntiDot: String {
        String(localized: "Use AntiDot Mode Instead",
               comment: "Button and menu item, while Audio Recording isn't allowed: switches to AntiDot mode, which doesn't need it")
    }

    /// What AntiDot mode trades, beside or under each Use AntiDot Mode
    /// Instead, and as its help tag and VoiceOver hint (F2a, 2026-11-02).
    static var antiDotTradeOff: String {
        String(localized: "No purple dot; a little less precise.",
               comment: "Welcome window, the menu and Settings, beside or under “Use AntiDot Mode Instead”, and its help tag: AntiDot mode hides macOS's purple dot (the recording indicator shown while AutoHush measures audio), but tells playing apps a little less precisely")
    }
}
