import AppKit
import AutoHushKit

/// Where a permission stands, read without asking for it.
enum PermissionAccess: Equatable, Sendable {
    case allowed
    /// macOS hasn't asked yet: asking shows its own prompt.
    case notAsked
    /// Not allowed: only System Settings changes it.
    case denied
    /// Automation can only be asked for while the player runs, and AutoHush
    /// never opens it by itself.
    case playerNotRunning
    /// Allowed in System Settings, but macOS applies Audio Recording only from
    /// AutoHush's next launch.
    case needsReopen
    /// Not used: Audio Recording in AntiDot mode.
    case notNeeded

    var isSatisfied: Bool { self == .allowed || self == .notNeeded }
}

/// What AutoHush needs to work for the chosen player, as it stands: the
/// player's control permission, and Audio Recording unless AntiDot mode is on.
struct PermissionsState: Equatable, Sendable {
    /// The player they were read for (its bundle ID); `nil` with none chosen.
    var player: String?
    /// The chosen player's control permission; `nil` with no player chosen.
    var control: Permission?
    var controlAccess: PermissionAccess = .allowed
    var audio: PermissionAccess = .allowed
    /// Accessibility, whatever the player: adding a web app drives Safari with it.
    var accessibility = true

    /// Nothing missing: windows that wait for the permissions go on.
    var allSatisfied: Bool { controlAccess.isSatisfied && audio.isSatisfied }

    /// Whether `player`'s control permission is missing, as read for it: a
    /// read for the previous player, while the new one's is under way, says
    /// nothing about it (its lock would show for a moment, 2026-10-18).
    func controlMissing(for player: String?) -> Bool {
        self.player == player && control != nil && !controlAccess.isSatisfied
    }
}

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
