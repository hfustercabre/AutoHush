import AutoHushKit

/// A state observer that does one more thing when it stops: an added app's
/// page way lifts a mute in place of a pause then, as a web app's observer
/// does, so the app is never left silent once AutoHush stops watching it.
@MainActor
final class StoppingObserver: PlayerStateObserving {
    private let observer: any PlayerStateObserving
    private let onStop: @MainActor () -> Void

    init(_ observer: any PlayerStateObserving, onStop: @escaping @MainActor () -> Void) {
        self.observer = observer
        self.onStop = onStop
    }

    func start() { observer.start() }

    func stop() {
        observer.stop()
        onStop()
    }
}
