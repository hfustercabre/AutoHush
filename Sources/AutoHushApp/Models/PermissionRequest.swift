import Foundation
import AutoHushKit

/// What a click on a missing permission's button does.
enum PermissionRequest: Equatable, Sendable {
    /// Shows macOS's own prompt: it hasn't asked yet.
    case askMacOS(Permission)
    /// Opens where it's switched on in System Settings.
    case openSettings(SystemSettingsPane)
    /// Opens the player, so macOS can ask for Automation.
    case openPlayer
    /// Quits and opens AutoHush again, so macOS applies Audio Recording.
    case reopen
}
