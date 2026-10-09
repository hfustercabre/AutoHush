import CoreAudio
import Foundation
import AutoHushKit

// Stand-ins for what AudioMonitor reads from macOS: the audio processes, their
// levels, the power assertions and the System Audio Recording permission.
// Shared by the engine's tests and the app's (MonitoringPipeline).

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

    package func activeProcesses() -> [AudioProcessInfo] { processes }

    package func startObserving(on queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
        lock.withLock {
            self.queue = queue
            self.onChange = onChange
        }
    }

    package func stopObserving() {
        lock.withLock { onChange = nil }
    }

    package func waitUntilObserving() {
        let deadline = TestWait.deadline
        while !isObserving, Date() < deadline { usleep(1000) }
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

package final class MockLevelMeter: AudioLevelMetering, @unchecked Sendable {
    package init() {}

    private let lock = NSLock()
    private var _peaks: [AudioObjectID: Float] = [:]
    private var _metered: Set<AudioObjectID> = []
    private var _stopAllCount = 0

    /// Peaks reported for every metered process (missing entries read as 0).
    package var peaks: [AudioObjectID: Float] {
        get { lock.withLock { _peaks } }
        set { lock.withLock { _peaks = newValue } }
    }

    package var lastMetered: Set<AudioObjectID> { lock.withLock { _metered } }
    package var stopAllCount: Int { lock.withLock { _stopAllCount } }

    /// Waits until exactly these processes are metered, e.g. after a delayed release.
    package func waitUntilMetered(_ objectIDs: Set<AudioObjectID>) async {
        let deadline = TestWait.deadline
        while lastMetered != objectIDs, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    package func setMeteredProcesses(_ objectIDs: Set<AudioObjectID>) {
        lock.withLock { _metered = objectIDs }
    }

    package func drainPeaks() -> [AudioObjectID: Float] {
        lock.withLock {
            Dictionary(uniqueKeysWithValues: _metered.map { ($0, _peaks[$0] ?? 0) })
        }
    }

    package func stopAll() {
        lock.withLock {
            _metered = []
            _stopAllCount += 1
        }
    }
}

package final class MockPowerAssertions: PowerAssertionReading, @unchecked Sendable {
    package init() {}

    /// An app saying it plays, keeping the Mac awake.
    package static let playing: Set<PowerAssertion> = [PowerAssertion(.system, "Playing")]

    private let lock = NSLock()
    private var _held: [pid_t: Set<PowerAssertion>] = [:]
    package var held: [pid_t: Set<PowerAssertion>] {
        get { lock.withLock { _held } }
        set { lock.withLock { _held = newValue } }
    }
    package func assertionsByProcess() -> [pid_t: Set<PowerAssertion>] { held }
}

package final class MockAudioCapturePermission: AudioCapturePermissionChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var _current: AudioCapturePermission?
    private var _requestCount = 0
    private var pending: (@Sendable (Bool) -> Void)?

    package init(_ status: AudioCapturePermission?) { _current = status }

    package var current: AudioCapturePermission? {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }

    package var requestCount: Int { lock.withLock { _requestCount } }

    package func status() -> AudioCapturePermission? { current }

    package func request(completion: @escaping @Sendable (Bool) -> Void) {
        lock.withLock {
            _requestCount += 1
            pending = completion
        }
    }

    /// Simulates the user answering the system prompt.
    package func complete(granted: Bool) {
        let completion = lock.withLock {
            _current = granted ? .granted : .denied
            return pending
        }
        completion?(granted)
    }
}
