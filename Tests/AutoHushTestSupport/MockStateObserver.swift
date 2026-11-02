import AutoHushKit

@MainActor
package final class MockStateObserver: PlayerStateObserving {
    /// Started and not stopped since.
    package private(set) var isObserving = false
    package init() {}
    package func start() { isObserving = true }
    package func stop() { isObserving = false }
}
