import AppKit
import AutoHushKit
import CheckedPlayers
import os
import PlayerCheckKit

// MARK: - What the tool changed

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
let changes = Changes()

/// Sets a switch on the app (a Chromium browser's web app's: on its
/// browser, `switchTarget`); whether it took. An app may answer an error
/// yet take it (CEF and Flutter apps and Chrome answer -25208 to VoiceOver's
/// switch, and read it back as set), or read one back as off while it's on
/// (Electron's): either sign counts.
func setSwitch(_ attribute: String, _ on: Bool, pid: pid_t) -> Bool {
    let app = AXUIElement.application(switchTarget(pid), timeout: 1)
    if on { changes.switchSetOn(attribute) }
    if AXUIElementSetAttributeValue(app, attribute as CFString, on ? kCFBooleanTrue : kCFBooleanFalse) == .success { return true }
    return app.value(attribute) as? Bool == on
}

/// Puts the switches this tool turned on back as they were (off, or on for
/// one it found on): those that didn't go.
@discardableResult
func switchesBackOff() -> [String] {
    let pid = changes.appPID
    guard pid > 0 else { return [] }
    return changes.takeSwitchesOn().filter { !setSwitch($0, changes.wasFoundOn($0), pid: pid) }
}

/// Brings an app forward through Launch Services, as `open` does (an app
/// in the background may not activate another itself), waiting for it.
func bringForward(_ url: URL) {
    _ = ToolRun(URL(fileURLWithPath: "/usr/bin/open"), [url.path]).runBlocking()
}

// MARK: - Stopping

let stopState = StopState()

/// Puts back what any thread may put back, then ends at once: `_exit`, as
/// `exit` could wait on the main thread's locks (stdout) from the stop's
/// thread. The window, when away, is put back first by `stopIfRequested`.
func stopNow(_ code: Int32) -> Never {
    log("(stopped)")
    inputBlock.end()
    switchesBackOff()
    if let front = changes.frontToRestore { bringForward(front) }
    // Now Playing, when a press shows it meanwhile (the user hid it).
    NowPlayingSetting.restoreIfLeft(defaults: nowPlayingRecord)
    nowPlayingReports.stop()
    fflush(nil)
    _exit(code)
}

/// After a trial, or another step a stop waited for: the stop it held back,
/// said by `line` (by default, after a trial: it played the app again); the
/// app's window put back first, when it's away.
@MainActor func stopIfRequested(_ line: String? = nil) {
    guard stopState.isRequested else { return }
    say("  " + (line ?? "stopped: \(appName) was played again first"))
    if stopState.isWindowAway { windowTest?.restore() }
    if inputBlock.end() { say(CheckReportLine.free) }
    stopNow(CheckExitStatus.stop)
}

/// Kept for as long as the tool runs.
@MainActor var stopWatches: [DispatchSourceProtocol] = []

/// A stop: Ctrl-C, Stop (AutoHush's panel, the Player Check app), or whoever
/// ran it ending without a word (its window closed, or it quit by force or
/// crashed). Its output then goes nowhere (and SIGPIPE is ignored), so it
/// stops as for Ctrl-C when its parent ends, rather than going on unwatched.
/// The handlers run on another thread, so they're `@Sendable`: a closure of
/// the main actor's would trap there (Swift 6 checks where it runs).
@MainActor func watchForStops() {
    for stop in [SIGINT, SIGTERM] {
        signal(stop, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: stop, queue: .global())
        source.setEventHandler { @Sendable in
            if stopState.request() { return } // the check stops itself
            stopNow(CheckExitStatus.stopped(by: stop))
        }
        source.resume()
        stopWatches.append(source)
    }
    let parent = getppid()
    // Whoever ran it is gone already (this process went to launchd): a test
    // would run on unwatched, with the mouse and keyboard blocked.
    guard parent > 1 else {
        if testing { stopNow(CheckExitStatus.stop) }
        return
    }
    let source = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .global())
    source.setEventHandler { @Sendable in
        if stopState.request() { return }
        stopNow(CheckExitStatus.stop)
    }
    source.resume()
    stopWatches.append(source)
    // Gone already, before the watch began: this process went to launchd.
    if getppid() != parent, !stopState.request() { stopNow(CheckExitStatus.stop) }
}
