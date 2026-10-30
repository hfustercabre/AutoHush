import Foundation
import AutoHushKit

// Stand-ins for what AudioMonitor reads from macOS: the audio processes, their
// levels, the power assertions and the System Audio Recording permission.
// Shared by the engine's tests and the app's (the player session's pipelines).

/// Stands in for the outputs' watcher: `disconnect()` is the output in use going away.
package final class MockOutputDisconnects: OutputDisconnectWatching, @unchecked Sendable {
    package init() {}

    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    package var isWatching: Bool { lock.withLock { handler != nil } }
    package func start(onDisconnect: @escaping @Sendable () -> Void) { lock.withLock { handler = onDisconnect } }
    package func stop() { lock.withLock { handler = nil } }
    package func disconnect() { lock.withLock { handler }?() }
}
