import Foundation
import AutoHushKit

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
