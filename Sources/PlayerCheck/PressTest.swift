import AppKit
import AutoHushKit
import CheckedPlayers
import PlayerCheckKit
import ScriptablePlayers

// MARK: - The test's results

/// Each way's result in the first window state tested (visible), or in the
/// only run when there were no states.
@MainActor var firstResults: [Way: TrialResult] = [:]
/// Each way's result in each window state, and why it failed there, for
/// "Ways to Control It".
@MainActor var stateResults: [Way: [(state: WindowState, result: TrialResult, why: String)]] = [:]
/// The window states a way couldn't be tried in, and why: the Now Playing
/// item missing from the menu bar in one state while there in others says
/// nothing about the app, so that state isn't counted against the panel.
@MainActor var untestedStates: [Way: [WindowState: String]] = [:]
/// Why a way wasn't tried, for "Ways to Control It".
@MainActor var notTried = readOnly ? "not tried: read only" : "not tried"

/// Why a way's trial failed in a window state: what's known of the state
/// (an Electron page out of view), else what its press said, else the trial's.
@MainActor func whyFailed(_ way: Way, in state: WindowState, _ result: TrialResult) -> String {
    if way == .page, isElectron, launchedWithOption == false, WindowState.outOfView.contains(state) {
        return "Chromium neither builds nor presses a page whose window is fully out of view; \(appName) wasn't opened with"
            + " \(LaunchOption.occludedWindows)"
    }
    if let trialProblem { return trialProblem }
    return result == .pausedOnly ? "it paused, but didn't play again" : "pressing it changed nothing"
}

// MARK: - Before the trials: playing, then the first state, last of all

/// A test with nothing else to press (no AppleScript play or pause, no
/// playback menu, no row in the Now Playing panel): its page is read first,
/// as it is, so an app with nothing to press is neither asked to play nor moved.
@MainActor var onlyItsPage = false
/// Whether it played before its window was moved: moving it to the first
/// state comes last, once the rest a test needs is known: the permissions,
/// something to press, and the app playing, asked for when it isn't. Nil
/// when not asked (no test, or nothing to press).
@MainActor var playedFirst: Bool?

/// Whether its page offers something to press: a button named Play or
/// Pause, or buttons whose words a pause by whoever runs the check can teach it.
@MainActor var pageOffersAPress: Bool { page?.toggle != nil || (page?.buttons ?? 0) > 0 }

/// The test's start: the app playing, its window in the first state
/// (visible on this desktop), then its page read in view (a Chromium page is
/// built and current only in view). Outside a test, only the page.
@MainActor func firstStateThenPage() {
    onlyItsPage = testing && running != nil && scriptControls() == nil && menu == nil && !(canBeNowPlaying && AXIsProcessTrusted())
    if onlyItsPage { readPageButtons() }
    if testing, let running, !onlyItsPage || pageOffersAPress {
        say()
        say(CheckReportLine.Heading.playing.rawValue)
        let pid = running.processIdentifier
        if isPlaying(pid) {
            playedFirst = true
            say("  it plays: testing")
        } else {
            playedFirst = waitUntilPlaying(pid)
            stopIfRequested("stopped while waiting for \(appName) to play: nothing was moved or pressed")
            if playedFirst == false { say("  stopped: \(appName) didn't play within 2 minutes; nothing was moved or pressed") }
        }
    }
    if testing, let running, AXIsProcessTrusted() {
        say()
        say(CheckReportLine.Heading.windowStates.rawValue)
        if playedFirst != true {
            let why = playedFirst == false ? "it didn't play" : "nothing to press"
            windowStatesNote = why
            say("  not tested: \(why), so its window wasn't moved")
        } else if let test = WindowTest(app: running) {
            windowTest = test
            guard stopState.beginMoving() else { stopIfRequested("stopped: nothing was moved"); stopNow(CheckExitStatus.stop) }
            if blockInput {
                say(inputBlock.start()
                    ? CheckReportLine.blocked + " until its window is put back (the pointer still moves;"
                        + " Escape or the panel's Stop ends the check)"
                    : "  input not blocked: blocking it needs the Accessibility permission")
            }
            if let hidden = hiddenInterface {
                let pid = running.processIdentifier
                test.revealPage = { on in
                    guard let attribute = pageSwitch ?? hidden.switches.first else { return }
                    setPageSwitch(attribute, on: on, pid: pid)
                }
            }
            say("  each way is tested with its window in each state: " + WindowState.allCases.map(\.title).joined(separator: ", ")
                + "; it's put back as it is now: \(test.original.title)")
            for state in WindowState.allCases { if let why = test.untested[state] { say("  \(state.title): not tested (\(why))") } }
            stopState.setInTrial(true)
            let why = test.putIn(.visible)
            stopState.setInTrial(false)
            stopIfRequested("stopped: its window is put back")
            if let why {
                say("  not visible: \(why); its page is read as it is")
            } else {
                currentWindowState = .visible
                say("  visible now: its page is read in view, and the test starts there")
            }
        } else {
            windowStatesNote = "no window open"
            say("  not tested: no window open (each way is tried once, as it is)")
        }
    }
    guard !onlyItsPage else { return }
    if playedFirst == false {
        // The test stopped: its page isn't built (an Electron app's may be
        // brought forward for it) for nothing.
        say()
        say(CheckReportLine.Heading.page.rawValue)
        say("  not read: \(appName) didn't play, so the check stopped")
        pageNotChecked = "it didn't play"
    } else {
        readPageButtons()
    }
}

// MARK: - The press test

/// Each way to control it, tried in each window state: paused and played
/// again by that way (a `PressTestRun`), once there's something to press
/// and it plays. Its window is put back as it was at the end.
@MainActor func runPressTest() {
    say()
    say(CheckReportLine.Heading.pressTest.rawValue)
    let script = scriptControls()
    guard let running else {
        say("  not run: the app isn't running")
        return
    }
    if script == nil, menu == nil, !pageOffersAPress, !canBeNowPlaying || !AXIsProcessTrusted() {
        // Nothing to press, and nothing for the panel to reach (or no
        // Accessibility to reach it with): asking for it to play would only wait.
        say("  not run: nothing to press (no AppleScript play or pause, playback menu or page button), and "
            + (canBeNowPlaying ? "without the Accessibility permission the Now Playing panel can't be reached" : notNowPlaying))
        notTried = "not tried: nothing to press"
        return
    }
    if playedFirst == false {
        say("  not run: \(appName) didn't play")
        notTried = "not tried: it didn't play"
        return
    }
    // AppleScript that only toggles, with no state of its own: AutoHush sends
    // it only when another sign tells its state, so with none it isn't tried.
    if let script, script.toggles, scripting?.hasState != true, menu == nil, !pageOffersAPress,
       !(canBeNowPlaying && isAdministrator), scriptProblem == nil {
        scriptProblem = "only “\(script.pause.name)”, which toggles, and no state it can be read by: AutoHush couldn't tell when to send it,"
            + " so it isn't tried"
        say("  AppleScript: \(scriptProblem!)")
    }
    notifications = NotificationLog(bundleID: bundleID)
    PressTestRun(running: running, script: script).run()
}
