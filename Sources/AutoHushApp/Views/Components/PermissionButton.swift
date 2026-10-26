import SwiftUI
import AutoHushKit

// What AutoHush needs before it can work for the chosen player, wherever it
// waits for it: the welcome window's second page, the learning window, the
// Add a Web App window and Settings → General. Each says what's missing,
// offers the way to allow it, and goes on by itself once it's allowed.

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
            let button = Button { model.actions?.requestPermission(permission) } label: { Text(verbatim: title) }
            if prominent {
                button.buttonStyle(ChipButtonStyle(filled: true, isSelected: true))
            } else {
                button.buttonStyle(.chip)
            }
        }
    }

    private var title: String? {
        Self.title(for: access, permission: permission, long: long, player: model.chosenPlayerName ?? "")
    }

    /// Its words while `permission` stands at `access`, for `player`; `nil`
    /// once it's allowed or not needed: no button then.
    static func title(for access: PermissionAccess, permission: Permission, long: Bool, player: String) -> String? {
        switch access {
        case .allowed, .notNeeded: nil
        case .playerNotRunning:
            ButtonText.open(player)
        case .needsReopen:
            PermissionText.reopen
        case .notAsked, .denied:
            long ? permission.grantTitle : ButtonText.allow
        }
    }
}
