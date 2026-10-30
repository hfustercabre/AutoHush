import Foundation
import PlayerCheckKit

/// How a trial reads the app: `look` and `waitFor` (its level measured when
/// asked), unless a test gives it what the app shows instead.
struct TrialReading {
    var look: @MainActor (_ pid: pid_t, _ level: Bool) -> Look
    var waitFor: @MainActor (_ seconds: Double, _ pid: pid_t, _ level: Bool, _ done: (Look) -> Bool) -> Look

    static let live = TrialReading(look: { pid, level in PlayerCheck.look(pid, level: level) },
                                   waitFor: { seconds, pid, level, done in PlayerCheck.waitFor(seconds, pid: pid, level: level, until: done) })
}
