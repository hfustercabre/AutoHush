import Foundation

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
