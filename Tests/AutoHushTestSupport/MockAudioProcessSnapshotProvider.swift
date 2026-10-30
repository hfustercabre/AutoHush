import Foundation
import AutoHushKit

// Stand-ins for what AudioMonitor reads from macOS: the audio processes, their
// levels, the power assertions and the System Audio Recording permission.
// Shared by the engine's tests and the app's (the player session's pipelines).

package final class MockAudioProcessSnapshotProvider: AudioProcessSnapshotProviding, @unchecked Sendable {
    package init() {}

    private let lock = NSLock()
    private var _processes: [AudioProcessInfo] = []
    private var queue: DispatchQueue?
    private var onChange: (@Sendable () -> Void)?

    package var processes: [AudioProcessInfo] {
        get { lock.withLock { _processes } }
        set { lock.withLock { _processes = newValue } }
    }

    package var isObserving: Bool { lock.withLock { onChange != nil } }

    package func activeProcesses(includingInputOnly: Bool) -> [AudioProcessInfo] {
        processes.filter { includingInputOnly || $0.isRunningOutput }
    }

    package func startObserving(on queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
        lock.withLock {
            self.queue = queue
            self.onChange = onChange
        }
    }

    package func stopObserving() {
        lock.withLock { onChange = nil }
    }

    /// Simulates a HAL change callback and waits until the monitor handled it.
    package func triggerChange() {
        let (queue, onChange) = lock.withLock { (self.queue, self.onChange) }
        guard let queue else { return }
        queue.sync { onChange?() }
    }

    /// Waits until all work already queued on the monitor has run.
    package func flush() {
        let queue = lock.withLock { self.queue }
        queue?.sync {}
    }
}
