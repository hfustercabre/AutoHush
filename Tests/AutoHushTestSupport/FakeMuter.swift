import Foundation
import AutoHushKit

// Stand-ins for the process taps a player mutes itself through, or listens
// to its own sound with (`AudioMuting`, `AudioLevelProbing`). Shared by the
// web apps' tests and the added apps'.

/// Mutes kept in memory, and each mute and unmute in order; `canMute`
/// false stands for a missing permission.
package final class FakeMuter: AudioMuting {
    private struct State {
        var muted: Set<pid_t> = []
        var log: [String] = []
        var canMute = true
    }

    private let state = Locked(State())

    package init() {}

    package var canMute: Bool {
        get { state.value.canMute }
        set { state.withLock { $0.canMute = newValue } }
    }

    package var muted: Set<pid_t> { state.value.muted }
    package var isMuted: Bool { !muted.isEmpty }
    package var log: [String] { state.value.log }

    package func mute(appPID: pid_t) -> Bool {
        state.withLock { state in
            guard state.canMute else { return false }
            state.muted.insert(appPID)
            state.log.append("mute \(appPID)")
            return true
        }
    }

    package func unmute(appPID: pid_t) {
        state.withLock { state in
            if state.muted.remove(appPID) != nil { state.log.append("unmute \(appPID)") }
        }
    }
}
