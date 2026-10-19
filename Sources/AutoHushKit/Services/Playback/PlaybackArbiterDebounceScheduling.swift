import Foundation

/// Waits before a deferred decision (a resume tried again, or a pause once
/// auto-pause is back on): the real one sleeps, tests complete it by hand.
package protocol PlaybackArbiterDebounceScheduling: Sendable {
    /// A task that finishes after `delay` seconds.
    func scheduleDebounce(after delay: TimeInterval) -> Task<Void, Never>
}

/// Waits with `Task.sleep`.
struct TaskSleepDebounceScheduler: PlaybackArbiterDebounceScheduling {
    func scheduleDebounce(after delay: TimeInterval) -> Task<Void, Never> {
        Task { try? await Task.sleep(for: .seconds(delay)) }
    }
}
