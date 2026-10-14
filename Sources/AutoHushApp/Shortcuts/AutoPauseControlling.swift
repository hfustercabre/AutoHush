import Foundation
import AutoHushKit

/// How Shortcuts' actions and the Focus filter reach Auto-Pause: read how it
/// is set, change it, and put back a setting noted earlier. `UserSettings`
/// conforms. Sendable, as App Intents' dependencies must be (conformers are
/// main-actor classes, so they are).
@MainActor
protocol AutoPauseControlling: AnyObject, Sendable {
    /// On now: neither off nor turned off for a time.
    var isAutoPauseActive: Bool { get }
    /// As stored: on, off, or off until a time.
    var autoPauseSetting: AutoPauseSetting { get }
    func setAutoPause(_ on: Bool)
    func toggleAutoPause(now: Date)
    func snooze(_ snooze: AutoPauseSnooze, now: Date)
    /// Puts back a setting noted earlier; an expired "turn off for" comes back as on.
    func restoreAutoPause(_ setting: AutoPauseSetting, now: Date)
}
