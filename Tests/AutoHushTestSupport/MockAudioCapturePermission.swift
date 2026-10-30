import Foundation
import AutoHushKit

// Stand-ins for what AudioMonitor reads from macOS: the audio processes, their
// levels, the power assertions and the System Audio Recording permission.
// Shared by the engine's tests and the app's (the player session's pipelines).

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
