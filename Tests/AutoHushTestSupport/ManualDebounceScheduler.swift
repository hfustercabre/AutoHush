import Foundation
import AutoHushKit

package final class ManualDebounceScheduler: PlaybackArbiterDebounceScheduling, @unchecked Sendable {
    package init() {}
    private var pendingTasks: [Task<Void, Never>] = []
    private var recordedDelays: [TimeInterval] = []
    private let lock = NSLock()
    /// Never stepped: a debounce's task sleeps until it's cancelled.
    private let held = ManualSleep()

    /// A task that ends once it's cancelled (by the arbiter, or
    /// `completeNext`). Until then it waits without running, so one the
    /// arbiter drops uncancelled costs nothing for the rest of the run.
    package func scheduleDebounce(after delay: TimeInterval) -> Task<Void, Never> {
        lock.withLock {
            recordedDelays.append(delay)
            let task = Task<Void, Never> { [held] in await held.sleep(.seconds(delay)) }
            pendingTasks.append(task)
            return task
        }
    }

    /// Cancels the oldest pending debounce task, letting the resume path proceed.
    package func completeNext() async {
        let task: Task<Void, Never>? = lock.withLock {
            pendingTasks.isEmpty ? nil : pendingTasks.removeFirst()
        }
        guard let task else { return }
        task.cancel()
        _ = await task.value
    }

    package var scheduledDelays: [TimeInterval] {
        lock.withLock { recordedDelays }
    }
}
