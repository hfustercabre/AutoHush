import Foundation
import AutoHushTestSupport

/// The keyboard's Play/Pause key in tests: counts its presses, and does
/// what a test says (by default, nothing: it reached another app).
final class PlayPauseKeyBox: Sendable {
    private let state = Locked<(presses: Int, onPress: (@Sendable () -> Void)?)>((0, nil))

    var count: Int { state.value.presses }
    var onPress: (@Sendable () -> Void)? {
        get { state.value.onPress }
        set { state.withLock { $0.onPress = newValue } }
    }

    func press() {
        let action = state.withLock {
            $0.presses += 1
            return $0.onPress
        }
        action?()
    }
}
