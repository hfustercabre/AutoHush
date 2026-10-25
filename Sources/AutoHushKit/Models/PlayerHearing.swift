import Foundation

/// Whether the media player is heard on this Mac, as the monitor measures
/// it alongside the other apps (`AudioMonitor.playerHearing`).
enum PlayerHearing: Equatable, Sendable {
    /// Heard lately.
    case heard
    /// Measured long enough, and nothing of it heard.
    case silent
    /// Measured, not heard yet, and not long enough to tell: asked again
    /// after this long.
    case measuring(remaining: TimeInterval)
    /// It can't be told: levels aren't measured (AntiDot mode, no Audio
    /// Recording), or the player's processes aren't.
    case unknown
}
