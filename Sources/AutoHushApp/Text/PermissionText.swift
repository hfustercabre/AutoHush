import Foundation

/// What the permission pieces say (`PermissionButton` and the windows that
/// ask), and Diagnostics' rows.
enum PermissionText {
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
            String(localized: "Click Allow, then Allow again when macOS asks.",
                   comment: "Welcome window, under a permission macOS hasn't asked for yet")
        case .denied:
            String(localized: "Turn it on for AutoHush in System Settings.",
                   comment: "Welcome window, under a permission that isn't allowed")
        }
    }

    /// Under Audio Recording, as it stands.
    static func audioNote(_ access: PermissionAccess) -> String {
        switch access {
        case .allowed, .notAsked, .playerNotRunning:
            String(localized: "Tells playing apps from silent ones.",
                   comment: "Welcome window, under “Audio Recording”: what AutoHush uses it for")
        case .denied:
            String(localized: "Turn it on for AutoHush in System Settings, then reopen AutoHush.",
                   comment: "Welcome window and Settings, while Audio Recording isn't allowed")
        case .needsReopen:
            String(localized: "Allowed. Reopen AutoHush to start using it.",
                   comment: "Welcome window and Settings: Audio Recording was allowed in System Settings, which macOS applies at AutoHush's next launch")
        case .notNeeded:
            AntiDotText.notNeeded
        }
    }

    /// A permission that is granted (`AllowedLabel`; Diagnostics' rows).
    static var allowed: String {
        String(localized: "Allowed", comment: "Diagnostics, the welcome window and the Add an App window: a permission that is granted")
    }

    static var reopen: String {
        String(localized: "Reopen AutoHush",
               comment: "Menu item and button, after the user went to allow audio recording in System Settings: macOS applies it only once AutoHush is quit and opened again. Also Add an App’s step “Allow what the check needs” when Accessibility changed while AutoHush was open")
    }

    static var useAntiDot: String {
        String(localized: "Use AntiDot Mode Instead",
               comment: "Button and menu item, while Audio Recording isn't allowed: switches to AntiDot mode, which doesn't need it")
    }
}
