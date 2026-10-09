import SwiftUI
import AutoHushKit

// What AutoHush needs before it can work for the chosen player, wherever it
// waits for it: the welcome window's second page, the learning window, the
// Add a Web App window and Settings → General. Each says what's missing,
// offers the way to allow it, and goes on by itself once it's allowed.

/// What the permission pieces say.
enum PermissionText {
    static func controlTitle(_ player: String) -> String {
        String(localized: "Control \(player)",
               comment: "Welcome window, the permission AutoHush needs to pause and resume the music player; %@ is the player")
    }

    static var audioTitle: String {
        String(localized: "Audio Recording",
               comment: "Welcome window, the System Audio Recording permission (macOS's name for it)")
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
            String(localized: "Not needed in AntiDot mode.",
                   comment: "Welcome window, under “Audio Recording” while AntiDot mode is on")
        }
    }

    static var reopen: String {
        String(localized: "Reopen AutoHush",
               comment: "Menu item, after the user went to allow audio recording in System Settings: macOS applies it only once AutoHush is quit and opened again")
    }

    static var useAntiDot: String {
        String(localized: "Use AntiDot Mode Instead",
               comment: "Button and menu item, while Audio Recording isn't allowed: switches to AntiDot mode, which doesn't need it")
    }
}

/// The button that allows a missing permission: "Open <player>" while
/// Automation waits for the player to run, "Reopen AutoHush" once Audio
/// Recording only needs a relaunch, else "Allow…" (or the permission's own
/// "Allow … Access…" with `long`). Nothing once it's allowed.
struct PermissionButton: View {
    let model: SettingsModel
    let permission: Permission
    let access: PermissionAccess
    var long = false
    var prominent = false

    var body: some View {
        if let title {
            let button = Button { model.requestPermission(permission) } label: { Text(verbatim: title) }
            if prominent {
                button.buttonStyle(ChipButtonStyle(filled: true, isSelected: true, padded: true))
            } else {
                button.buttonStyle(.chip)
            }
        }
    }

    private var title: String? {
        switch access {
        case .allowed, .notNeeded: nil
        case .playerNotRunning:
            String(localized: "Open \(model.chosenPlayerName ?? "")", comment: "Button that opens the music player, so macOS can ask for Automation; %@ is the player")
        case .needsReopen:
            PermissionText.reopen
        case .notAsked, .denied:
            long ? permission.grantTitle
                : String(localized: "Allow…", comment: "Welcome window: button that asks for a permission (macOS's prompt, or System Settings)")
        }
    }
}
