import AppKit
import CheckedPlayers
import PlayerCheckKit

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
            guard stopState.beginMoving() else { stopIfRequested("stopped: nothing was moved"); stopNow(143) }
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
                    if on {
                        if setSwitch(attribute, true, pid: pid), !changes.switchesOn.contains(attribute) { changes.switchesOn.append(attribute) }
                        _ = waitForPage(pid, seconds: 4)
                    } else {
                        _ = setSwitch(attribute, false, pid: pid)
                    }
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
/// again by that way. Its window is put back as it was at the end.
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
        scriptProblem = "only “\(script.pause)”, which toggles, and no state it can be read by: AutoHush couldn't tell when to send it,"
            + " so it isn't tried"
        say("  AppleScript: \(scriptProblem!)")
    }
    let pid = running.processIdentifier
    notifications = NotificationLog(bundleID: bundleID)
    /// The window state the trials run in, and whether it's the first
    /// tested (learning the page's button and the volume check happen there).
    var state: WindowState?
    var first = true
    /// Whether the trial's pause pressed the player's own button (learned,
    /// or with a player's slider around it), so a pause that didn't take
    /// was the site's refusal, not a wrong button.
    var pressedPlayersPause = false
    func pressPage(pausing: Bool) -> Bool {
        guard let button = pageButtonToPress(pid: pid, pausing: pausing) else {
            let shown = !(pageButtons(pid: pid) ?? []).isEmpty
            say("    " + (shown ? "no button in sight to press" : "its page didn't show"))
            trialProblem = shown ? "its page showed no Play/Pause to press"
                : "its page didn't show" + (pageSwitch.map { " with \(switchName($0)) on" } ?? "")
            return false
        }
        var why: String?
        guard pressPageButton(button, pausing: pausing, why: &why) else {
            if let why { say("    \(why)") }
            trialProblem = why
            return false
        }
        if pausing {
            let players = [learned?.element, page?.withControls == true ? page?.toggle?.element : nil, barToggle].compactMap { $0 }
            pressedPlayersPause = players.contains { CFEqual($0, button.element) }
        }
        return true
    }
    /// After the first window state, the page is pressed as Player Check's
    /// own presses press it: its switch off between presses, each press
    /// turning it on, giving the page up to 4 s to show, and turning it off
    /// once it's seen whether it took. Kept on instead, a page built in view
    /// stays usable out of view (an Electron player's passed every state), which those
    /// presses don't get. The first state keeps it on, for learning the
    /// button. Only a switch this tool may turn off: Electron's, or one it
    /// turned on.
    let pressSwitch: String? = pageSwitch.flatMap { $0 == manualAccessibility || changes.switchesOn.contains($0) ? $0 : nil }
    /// Left on by the check (the page was readable already): on again at the end.
    let pressSwitchLeftOn = pressSwitch.map(changes.wasFoundOn) ?? false
    func switchForPress(_ on: Bool) {
        guard let pressSwitch, !first else { return }
        if on {
            if setSwitch(pressSwitch, true, pid: pid), !changes.switchesOn.contains(pressSwitch) {
                changes.switchesOn.append(pressSwitch)
            }
            _ = waitForPage(pid, seconds: 4)
        } else {
            _ = setSwitch(pressSwitch, false, pid: pid)
        }
    }
    let panelReachable = canBeNowPlaying && AXIsProcessTrusted()
    /// Each way's play, to play it again quietly when a way left it paused.
    var plays: [(way: Way, title: String, play: () -> Bool)] = []
    if let script { plays.append((.script, "AppleScript", { sendScript(script.play) })) }
    if menu != nil { plays.append((.menu, "its menu", { pressMenuToggle(pid: pid) })) }
    plays.append((.page, "its page's button", {
        guard page?.toggle != nil else { return false }
        switchForPress(true)
        return pressPage(pausing: false)
    }))
    if panelReachable { plays.append((.panel, "the Now Playing panel", { pressInPanel(pid: pid, pausing: false) })) }
    /// Whether a trial has run (before the first, whoever runs the check
    /// starts it), and the way whose trial ran last (its play was pressed
    /// twice already).
    var trialRan = false
    var lastWay: Way?
    /// Whether a way worked in this window state (with no window, in the one run).
    func workedHere(_ way: Way) -> Bool {
        guard let state else { return firstResults[way] == .worked }
        return stateResults[way]?.contains { $0.state == state && $0.result == .worked } == true
    }
    /// A way that left it paused, or a track that ended: before anyone is
    /// asked, in any state, it's played again by a way that worked in this
    /// state, else by the others: AppleScript, its menu, then the panel, a
    /// last resort as it shows on screen. Each only while it doesn't play (a
    /// toggle would pause it), judged by the surest sign it shows.
    func playAgain() -> Bool {
        let here = plays.filter { workedHere($0.way) }
        let others = plays.filter { play in
            [.script, .menu, .panel].contains(play.way) && play.way != lastWay && !here.contains { $0.way == play.way }
        }
        for play in here + others {
            let before = lookForSign(pid)
            let sign = Sign(before: before)
            guard !sign.playing(before) else { return true }
            guard play.play() else { continue }
            let after = waitFor(4, pid: pid, level: sign.byLevel, until: sign.playing)
            if play.way == .page { switchForPress(false) }
            if sign.playing(after) {
                say("    played again by \(play.title)")
                return true
            }
        }
        return false
    }
    // Each way needs it playing: whoever runs the tool is asked to start
    // it before the first, and whenever a way leaves it stopped and it
    // can't be played again otherwise.
    var going = true
    func ready() -> Bool {
        guard going else { return false }
        if trialRan, !isPlaying(pid), playAgain() {
            if first { noteLearningPlaying(pid: pid) }
            return true
        }
        going = waitUntilPlaying(pid)
        stopIfRequested(going ? nil : "stopped while waiting for \(appName) to play")
        if !going {
            notTried = "not tried: it didn't play"
            say("  stopped: \(appName) didn't play within 2 minutes")
        } else if first {
            // Its page while it plays, to learn its Play/Pause from the first pause.
            noteLearningPlaying(pid: pid)
        }
        return going
    }
    func record(_ way: Way, _ result: TrialResult) {
        if first { firstResults[way] = result }
        if let state { stateResults[way, default: []].append((state, result, whyFailed(way, in: state, result))) }
        trialProblem = nil
        trialRan = true
        lastWay = way
    }
    /// A trial whose track ended meanwhile (`trialTrackEnded`) is run
    /// again once it plays (`ready`): it said nothing about the way. Ended
    /// twice, it fails saying so.
    func trialAgainIfEnded(_ way: Way, _ run: () -> TrialResult) -> TrialResult {
        let result = run()
        guard trialTrackEnded else { return result }
        trialRan = true
        lastWay = way
        say("    its track ended during the trial: once more, once it plays")
        guard ready() else {
            trialProblem = "its track ended during the trial, and it didn't play again"
            return result
        }
        trialProblem = nil
        let again = run()
        if trialTrackEnded { trialProblem = "its track ended during the trial, twice: play a longer one and check again" }
        return again
    }
    let states: [WindowState?] = windowTest.map { $0.states } ?? [nil]
    for (index, next) in states.enumerated() where going {
        stopIfRequested(trialRan ? nil : "stopped: its window is put back")
        state = next
        if let next, let windowTest {
            say(CheckReportLine.windowState(index + 1, of: states.count, next))
            // Off, as between two presses, before the window goes.
            switchForPress(false)
            stopState.setInTrial(true)
            let why = windowTest.putIn(next)
            stopState.setInTrial(false)
            stopIfRequested()
            if let why {
                say("\(CheckReportLine.notTested): \(why)")
                windowTest.untested[next] = why
                continue
            }
            currentWindowState = next
        }
        trialProblem = nil
        if let script, scriptProblem == nil, ready() {
            // A toggle is sent for the pause only while it plays, and again to play.
            record(.script, trialAgainIfEnded(.script) {
                trial(CheckReportLine.trial(.script, detail: "\(script.pause), \(script.play)"), pid: pid,
                      pause: { _ in sendScript(script.pause) }, play: { _ in sendScript(script.play) },
                      whilePaused: first ? { checkVolume(); learnPageButton(pid: pid) } : nil)
            })
            stopIfRequested()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
        }
        if menu != nil, ready() {
            record(.menu, trialAgainIfEnded(.menu) {
                trial(CheckReportLine.trial(.menu), pid: pid,
                      pause: { _ in pressMenuToggle(pid: pid) }, play: { _ in pressMenuToggle(pid: pid) },
                      whilePaused: first ? { learnPageButton(pid: pid) } : nil)
            })
            stopIfRequested()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
        }
        // No other way paused it and no button is named Play or Pause: as
        // AutoHush asks ("It's Paused"), whoever runs the check pauses it, and
        // the button whose words changed is learned.
        let pausedByAnother = [firstResults[.script], firstResults[.menu]].contains { $0 == .worked || $0 == .pausedOnly }
        if first, learned == nil, !pausedByAnother, page?.toggle == nil, page?.buttons ?? 0 > 0, ready() {
            if !learner.hasPlayed {
                // Its page is out of sight, where its words can't be learned: nobody is asked.
                learnPageButton(pid: pid)
            } else {
                say(CheckReportLine.waitingToPause(appName, minutes: 2))
                let deadline = Date().addingTimeInterval(120)
                inputBlock.pause()
                while isPlaying(pid), Date() < deadline, !stopState.isRequested { RunLoop.main.run(until: Date().addingTimeInterval(0.5)) }
                inputBlock.resume()
                stopIfRequested("stopped while waiting for \(appName) to be paused")
                if !isPlaying(pid) {
                    say("  it paused: learning")
                    learnPageButton(pid: pid)
                } else {
                    say("  it didn't pause within 2 minutes: its page's Play/Pause isn't learned")
                }
            }
        }
        if page?.toggle != nil, ready() {
            let result = trialAgainIfEnded(.page) {
                pressedPlayersPause = false
                return trial(CheckReportLine.trial(.page, learned: learned != nil), pid: pid,
                             pause: { _ in switchForPress(true); return pressPage(pausing: true) },
                             play: { _ in switchForPress(true); return pressPage(pausing: false) },
                             undo: { switchForPress(false) },
                             whilePaused: first ? { learnPageButton(pid: pid) } : { switchForPress(false) })
            }
            switchForPress(false)
            if result == .didNotPause, pressedPlayersPause, (state ?? .visible) == .visible {
                say("    a pause its page refuses: AutoHush would mute it instead")
            }
            record(.page, result)
            stopIfRequested()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
        }
        if !canBeNowPlaying {
            if first {
                panelProblem = panelNotNowPlaying
                say("  the Now Playing panel: not pressed: \(notNowPlaying)")
                firstResults[.panel] = .didNotPause
            }
        } else if !AXIsProcessTrusted() {
            if first { say("  the Now Playing panel: not pressed: \(noPanelItem)") }
        } else if ready() {
            let result = trialAgainIfEnded(.panel) {
                panelProblem = nil
                return trial(CheckReportLine.trial(.panel), pid: pid, pause: { pressInPanel(pid: pid, pausing: true, heard: $0) },
                             play: { pressInPanel(pid: pid, pausing: false, choice: .lastElseApp, heard: $0) },
                             undo: {
                                 // The row pressed may have been another app's: pressed again, that app plays on.
                                 if panelRowText != nil { _ = pressInPanel(pid: pid, pausing: false, choice: .lastOnly) }
                             },
                             whilePaused: first ? { learnPageButton(pid: pid) } : nil)
            }
            if let panelProblem {
                say("    \(panelProblem)")
                // Its own reason, unless its play took only when pressed once more.
                trialProblem = trialProblem ?? panelProblem
            }
            // It paused with that row: its own, for later presses.
            if result != .didNotPause { rememberPanelRow() }
            if let state, !first, result == .didNotPause, panelProblem == noPanelItem {
                // Not found in this state only: the panel wasn't tried here.
                untestedStates[.panel, default: [:]][state] = "its item wasn't found in the menu bar then"
                say("    not counted: the panel isn't tested in this state")
                trialProblem = nil
                trialRan = true
                lastWay = .panel
            } else {
                record(.panel, result)
            }
            stopIfRequested()
        }
        first = false
    }
    if let windowTest {
        stopState.setInTrial(true)
        let problem = windowTest.restore()
        stopState.setInTrial(false)
        currentWindowState = nil
        if inputBlock.end() { say(CheckReportLine.free) }
        // Read again: another app's windows that covered it may be behind it now.
        let now = WindowStates.state(of: running)
        say(now == windowTest.original || problem != nil
            ? "  its window put back as it was (\(windowTest.original.title))" + (problem.map { ", but \($0)" } ?? "")
            : "  its window put back where it was, but it was \(windowTest.original.title) and it's \(now?.title ?? "gone") now")
        stopIfRequested()
    }
    if pressSwitchLeftOn, let pressSwitch, setSwitch(pressSwitch, true, pid: pid) {
        changes.switchesOn.removeAll { $0 == pressSwitch }
    }
    if let seen = notifications?.seen, !seen.isEmpty {
        for (name, keys) in seen.sorted(by: { $0.key < $1.key }) {
            say("  notification: \(name)" + (keys.isEmpty ? "" : " [\(keys.sorted().joined(separator: ", "))]"))
        }
    } else {
        say("  notifications: none under the usual names (\(bundleID).\(stateNotificationSuffixes[0]), …)")
    }
}
