import AppKit
import AutoHushKit
import CheckedPlayers
import PlayerCheckKit

// MARK: - What the tool changed

/// What this run changed (`Changes`).
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
    if stopState.isWindowAway { TestScope.windowTest?.restore() }
    if inputBlock.end() { say(CheckReportLine.free) }
    stopNow(CheckExitStatus.stop)
}

/// Kept for as long as the tool runs.
@MainActor var stopWatches: [any DispatchSourceProtocol] = []

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
