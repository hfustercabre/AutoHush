import Foundation

/// Waits before a deferred decision (a resume tried again, or a pause once
/// auto-pause is back on): the real one sleeps, tests complete it by hand.
package protocol PlaybackArbiterDebounceScheduling: Sendable {
    /// A task that finishes after `delay` seconds.
    func scheduleDebounce(after delay: TimeInterval) -> Task<Void, Never>
    /// For tests only: a restart watch's look got past its wait, on its way
    /// to the arbiter (T-4 of 11-11).
    func lookPassedWait()
}

extension PlaybackArbiterDebounceScheduling {
    package func lookPassedWait() {}
}

/// Waits with `Task.sleep`.
struct TaskSleepDebounceScheduler: PlaybackArbiterDebounceScheduling {
    func scheduleDebounce(after delay: TimeInterval) -> Task<Void, Never> {
        Task { try? await Task.sleep(for: .seconds(delay)) }
    }
}
