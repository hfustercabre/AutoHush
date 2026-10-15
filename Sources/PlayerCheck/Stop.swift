import AppKit
import CheckedPlayers

// MARK: - What the tool changed

/// What this tool changed that a stop puts back, from whichever thread the
/// stop arrives on: the switches it turned on (and those it found on, set
/// back on), and the app that was in front when it brought the checked one
/// forward. (The `log stream` it follows Now Playing with ends with
/// `nowPlayingReports.stop()`.)
final class Changes: @unchecked Sendable {
    private let lock = NSLock()
    private var switches: [String] = []
    private var keptOn: Set<String> = []
    private var front: URL?
    private var setOnTimes: [String: Date] = [:]
    private var pid: pid_t = 0

    /// The checked app's process (0: not running).
    var appPID: pid_t {
        get { lock.withLock { pid } }
        set { lock.withLock { pid = newValue } }
    }
    /// The switches this tool turned on: turned back off when it ends.
    var switchesOn: [String] {
        get { lock.withLock { switches } }
        set { lock.withLock { switches = newValue } }
    }
    /// A switch that was (or may have been) on before this tool turned it
    /// on: a stop sets it back on, not off.
    func foundOn(_ attribute: String) { lock.withLock { _ = keptOn.insert(attribute) } }
    func wasFoundOn(_ attribute: String) -> Bool { lock.withLock { keptOn.contains(attribute) } }
    /// The app to bring back to the front, while another was brought forward.
    var frontToRestore: URL? {
        get { lock.withLock { front } }
        set { lock.withLock { front = newValue } }
    }
    /// When this tool last turned `attribute` on (`waitForFullerMode`).
    func switchSetOn(_ attribute: String) { lock.withLock { setOnTimes[attribute] = Date() } }
    func switchSetOnAt(_ attribute: String) -> Date? { lock.withLock { setOnTimes[attribute] } }
}
let changes = Changes()

/// Sets a switch on the app (a Chromium browser's web app's: on its
/// browser, `switchTarget`); whether it took. An app may answer an error
/// yet take it (CEF and Flutter apps and Chrome answer -25208 to VoiceOver's
/// switch, and read it back as set), or read one back as off while it's on
/// (Electron's): either sign counts.
func setSwitch(_ attribute: String, _ on: Bool, pid: pid_t) -> Bool {
    let app = AXUIElementCreateApplication(switchTarget(pid))
    AXUIElementSetMessagingTimeout(app, 1)
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
    let stuck = changes.switchesOn.filter { !setSwitch($0, changes.wasFoundOn($0), pid: pid) }
    changes.switchesOn = []
    return stuck
}

/// Brings an app forward through Launch Services, as `open` does (an app
/// in the background may not activate another itself).
func bringForward(_ url: URL) {
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = [url.path]
    try? open.run()
    open.waitUntilExit()
}

// MARK: - Stopping

/// A stop (Ctrl-C, Stop in AutoHush's panel or the Player Check app, or
/// Escape while input is blocked: `InputBlock`) arrives on another thread. While the app's window
/// is away from where it was, and between a trial's pause and its play, it
/// only asks: the check stops itself at its next step (`stopIfRequested`:
/// after the trial, which plays the app again, the move or the page read
/// under way, or at once in a wait), then puts the window back. Put back
/// from the stop's thread meanwhile, the window was dragged while the next
/// trial ran, and stayed out of place. Otherwise the tool stops at once
/// (`stopNow`).
final class StopState: @unchecked Sendable {
    private let lock = NSLock()
    private var inTrial = false, away = false
    private var requestedAt: Date?

    func setInTrial(_ value: Bool) { lock.withLock { inTrial = value } }
    /// Records the stop; true when the check must stop itself: in a trial,
    /// or while the window is away (`beginMoving`).
    func request() -> Bool {
        lock.withLock {
            if requestedAt == nil { requestedAt = Date() }
            return inTrial || away
        }
    }
    /// When the first stop came, while the check is to stop itself
    /// (`InputBlock` frees the mouse and keyboard if it takes long).
    var since: Date? { lock.withLock { requestedAt } }
    private var requested: Bool { requestedAt != nil }
    /// Before the window is first moved; false when a stop came first (then
    /// nothing may move).
    func beginMoving() -> Bool {
        lock.withLock {
            guard !requested else { return false }
            away = true
            return true
        }
    }
    /// The window is back where it was.
    func windowBack() { lock.withLock { away = false } }
    var isWindowAway: Bool { lock.withLock { away } }
    var isRequested: Bool { lock.withLock { requested } }
}
let stopState = StopState()

/// Puts back what any thread may put back, then ends at once: `_exit`, as
/// `exit` could wait on the main thread's locks (stdout) from the stop's
/// thread. The window, when away, is put back first by `stopIfRequested`.
func stopNow(_ code: Int32) -> Never {
    log("(stopped)")
    inputBlock.end()
    switchesBackOff()
    if let front = changes.frontToRestore { bringForward(front) }
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
    stopNow(143)
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
            stopNow(128 + stop)
        }
        source.resume()
        stopWatches.append(source)
    }
    let parent = getppid()
    // Whoever ran it is gone already (this process went to launchd): a test
    // would run on unwatched, with the mouse and keyboard blocked.
    guard parent > 1 else {
        if testing { stopNow(143) }
        return
    }
    let source = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .global())
    source.setEventHandler { @Sendable in
        if stopState.request() { return }
        stopNow(143)
    }
    source.resume()
    stopWatches.append(source)
    // Gone already, before the watch began: this process went to launchd.
    if getppid() != parent, !stopState.request() { stopNow(143) }
}
