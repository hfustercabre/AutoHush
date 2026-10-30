import AutoHushKit

/// A state observer that does one more thing when it stops: a web app's,
/// and an added app's page way's, lifts a mute in place of a pause then, so
/// the app is never left silent once AutoHush stops watching it.
@MainActor
package final class StoppingObserver: PlayerStateObserving {
    private let observer: any PlayerStateObserving
    private let onStop: @MainActor () -> Void

    package init(_ observer: any PlayerStateObserving, onStop: @escaping @MainActor () -> Void) {
        self.observer = observer
        self.onStop = onStop
    }

    package func start() { observer.start() }

    package func stop() {
        observer.stop()
        onStop()
    }
}
