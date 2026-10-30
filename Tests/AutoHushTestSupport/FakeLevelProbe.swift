import Foundation
import AutoHushKit

// Stand-ins for the process taps a player mutes itself through, or listens
// to its own sound with (`AudioMuting`, `AudioLevelProbing`). Shared by the
// web apps' tests and the added apps'.

/// Says whether the app can be heard, as the test says; counts how often it
/// listened.
package final class FakeLevelProbe: AudioLevelProbing {
    private let state: Locked<(audible: Bool, listens: Int)>

    package init(audible: Bool = false) {
        state = Locked((audible, 0))
    }

    package var audible: Bool {
        get { state.value.audible }
        set { state.withLock { $0.audible = newValue } }
    }

    package var listens: Int { state.value.listens }

    package func isAudible(appPID: pid_t) -> Bool {
        state.withLock { state in
            state.listens += 1
            return state.audible
        }
    }
}
