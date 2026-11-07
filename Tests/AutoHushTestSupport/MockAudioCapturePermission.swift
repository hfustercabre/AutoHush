import Foundation
import AutoHushKit

// Stand-ins for what AudioMonitor reads from macOS: the audio processes, their
// levels, the power assertions and the System Audio Recording permission.
// Shared by the engine's tests and the app's (the player session's pipelines).

package final class MockAudioCapturePermission: AudioCapturePermissionChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var _current: AudioCapturePermission?

    package init(_ status: AudioCapturePermission?) { _current = status }

    package var current: AudioCapturePermission? {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }

    package func status() -> AudioCapturePermission? { current }
}
