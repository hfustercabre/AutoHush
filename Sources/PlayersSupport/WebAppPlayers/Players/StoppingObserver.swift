import AutoHushKit

/// A state observer that does one more thing when it stops: a web app's,
/// and an added app's page way's, lifts a mute in place of a pause then, so
/// the app is never left silent once AutoHush stops watching it; not when it
/// hands that pause over to a new monitoring of the same player, which lifts
/// it in its turn.
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
        stop(handingOver: false)
    }

    /// Handing over to a new monitoring of the same player that has taken
    /// its pause over, the mute is that one's now: it stays.
    package func stop(handingOver: Bool) {
        observer.stop(handingOver: handingOver)
        if !handingOver { onStop() }
    }
}
