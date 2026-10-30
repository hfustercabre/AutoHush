import Foundation
import os

/// What this tool changed that a stop puts back, from whichever thread the
/// stop arrives on: the switches it turned on (and those it found on, set
/// back on), and the app that was in front when it brought the checked one
/// forward. (The `log stream` it follows Now Playing with ends with
/// `nowPlayingReports.stop()`; a Now Playing shown for a press is kept in
/// `nowPlayingRecord`.) Each change is made whole under its lock, so a stop
/// never reads a list halfway through one.
final class Changes: Sendable {
    private struct State {
        var switches: [String] = []
        var keptOn: Set<String> = []
        var front: URL?
        var setOnTimes: [String: Date] = [:]
        var pid: pid_t = 0
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// The checked app's process (0: not running).
    var appPID: pid_t {
        get { state.withLock { $0.pid } }
        set { state.withLock { $0.pid = newValue } }
    }
    /// The switches this tool turned on: turned back off when it ends.
    var switchesOn: [String] { state.withLock { $0.switches } }
    /// Notes a switch this tool turned on (once).
    func noteOn(_ attribute: String) {
        state.withLock { if !$0.switches.contains(attribute) { $0.switches.append(attribute) } }
    }
    /// Notes that a switch this tool turned on is off again, or back as it was.
    func noteOff(_ attribute: String) { state.withLock { $0.switches.removeAll { $0 == attribute } } }
    /// The switches this tool turned on, no longer noted: to put them back.
    func takeSwitchesOn() -> [String] {
        state.withLock { state in
            defer { state.switches = [] }
            return state.switches
        }
    }
    /// A switch that was (or may have been) on before this tool turned it
    /// on: a stop sets it back on, not off.
    func foundOn(_ attribute: String) { state.withLock { _ = $0.keptOn.insert(attribute) } }
    func wasFoundOn(_ attribute: String) -> Bool { state.withLock { $0.keptOn.contains(attribute) } }
    /// The app to bring back to the front, while another was brought forward.
    var frontToRestore: URL? {
        get { state.withLock { $0.front } }
        set { state.withLock { $0.front = newValue } }
    }
    /// When this tool last turned `attribute` on (`waitForFullerMode`).
    func switchSetOn(_ attribute: String) { state.withLock { $0.setOnTimes[attribute] = Date() } }
    func switchSetOnAt(_ attribute: String) -> Date? { state.withLock { $0.setOnTimes[attribute] } }
}
