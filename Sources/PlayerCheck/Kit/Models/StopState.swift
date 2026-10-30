import Foundation
import os

/// A stop (Ctrl-C, Stop in AutoHush's panel or the Player Check app, or
/// Escape while input is blocked: `InputBlock`) arrives on another thread. While the app's window
/// is away from where it was, and between a trial's pause and its play, it
/// only asks: the check stops itself at its next step (`stopIfRequested`:
/// after the trial, which plays the app again, the move or the page read
/// under way, or at once in a wait), then puts the window back. Put back
/// from the stop's thread meanwhile, the window was dragged while the next
/// trial ran, and stayed out of place. Otherwise the tool stops at once
/// (`stopNow`).
package final class StopState: Sendable {
    private struct State {
        var inTrial = false, away = false
        var requestedAt: Date?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    package init() {}

    package func setInTrial(_ value: Bool) { state.withLock { $0.inTrial = value } }
    /// Records the stop; true when the check must stop itself: in a trial,
    /// or while the window is away (`beginMoving`).
    package func request() -> Bool {
        state.withLock {
            if $0.requestedAt == nil { $0.requestedAt = Date() }
            return $0.inTrial || $0.away
        }
    }
    /// When the first stop came, while the check is to stop itself
    /// (`InputBlock` frees the mouse and keyboard if it takes long).
    package var since: Date? { state.withLock { $0.requestedAt } }
    /// Before the window is first moved; false when a stop came first (then
    /// nothing may move).
    package func beginMoving() -> Bool {
        state.withLock {
            guard $0.requestedAt == nil else { return false }
            $0.away = true
            return true
        }
    }
    /// The window is back where it was.
    package func windowBack() { state.withLock { $0.away = false } }
    package var isWindowAway: Bool { state.withLock { $0.away } }
    package var isRequested: Bool { state.withLock { $0.requestedAt != nil } }
}
