import Foundation

/// A stop (Ctrl-C, Stop in AutoHush's panel or the Player Check app, or
/// Escape while input is blocked: `InputBlock`) arrives on another thread. While the app's window
/// is away from where it was, and between a trial's pause and its play, it
/// only asks: the check stops itself at its next step (`stopIfRequested`:
/// after the trial, which plays the app again, the move or the page read
/// under way, or at once in a wait), then puts the window back. Put back
/// from the stop's thread meanwhile, the window was dragged while the next
/// trial ran, and stayed out of place. Otherwise the tool stops at once
/// (`stopNow`).
package final class StopState: @unchecked Sendable {
    private let lock = NSLock()
    private var inTrial = false, away = false
    private var requestedAt: Date?

    package init() {}

    package func setInTrial(_ value: Bool) { lock.withLock { inTrial = value } }
    /// Records the stop; true when the check must stop itself: in a trial,
    /// or while the window is away (`beginMoving`).
    package func request() -> Bool {
        lock.withLock {
            if requestedAt == nil { requestedAt = Date() }
            return inTrial || away
        }
    }
    /// When the first stop came, while the check is to stop itself
    /// (`InputBlock` frees the mouse and keyboard if it takes long).
    package var since: Date? { lock.withLock { requestedAt } }
    private var requested: Bool { requestedAt != nil }
    /// Before the window is first moved; false when a stop came first (then
    /// nothing may move).
    package func beginMoving() -> Bool {
        lock.withLock {
            guard !requested else { return false }
            away = true
            return true
        }
    }
    /// The window is back where it was.
    package func windowBack() { lock.withLock { away = false } }
    package var isWindowAway: Bool { lock.withLock { away } }
    package var isRequested: Bool { lock.withLock { requested } }
}
