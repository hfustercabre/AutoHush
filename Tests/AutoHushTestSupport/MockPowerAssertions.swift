import Foundation
import AutoHushKit

// Stand-ins for what AudioMonitor reads from macOS: the audio processes, their
// levels, the power assertions and the System Audio Recording permission.
// Shared by the engine's tests and the app's (the player session's pipelines).

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
