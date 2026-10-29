import AppKit
import AutoHushKit
import CheckedPlayers
import PlayerCheckKit
import WebAppPlayers

/// One run of the press test (`runPressTest`): each way to control it,
/// tried in each window state, and what its trials share as they go (the
/// state they run in, the ways' plays, whether it still plays). Its window
/// is put back as it was at the end.
@MainActor final class PressTestRun {
    private let running: NSRunningApplication
    private let pid: pid_t
    /// Its AppleScript play and pause (`scriptControls`), when it has them.
    private let script: (pause: ScriptCommand, play: ScriptCommand, toggles: Bool)?
    /// The window state the trials run in, and whether it's the first
    /// tested (learning the page's button and the volume check happen there).
    private var state: WindowState?
    private var first = true
    /// Whether the trial's pause pressed the player's own button (learned,
    /// or with a player's slider around it), so a pause that didn't take
    /// was the site's refusal, not a wrong button.
    private var pressedPlayersPause = false
    /// After the first window state, the page is pressed as Player Check's
    /// own presses press it: its switch off between presses, each press
    /// turning it on, giving the page up to 4 s to show, and turning it off
    /// once it's seen whether it took. Kept on instead, a page built in view
    /// stays usable out of view (an Electron player's passed every state), which those
    /// presses don't get. The first state keeps it on, for learning the
    /// button. Only a switch this tool may turn off: Electron's, or one it
    /// turned on.
    private let pressSwitch: String?
    /// Left on by the check (the page was readable already): on again at the end.
    private let pressSwitchLeftOn: Bool
    private let panelReachable: Bool
    /// Each way's play, to play it again quietly when a way left it paused.
    private var plays: [(way: Way, title: String, play: () -> Bool)] = []
    /// Whether a trial has run (before the first, whoever runs the check
    /// starts it), and the way whose trial ran last (its play was pressed
    /// twice already).
    private var trialRan = false
    private var lastWay: Way?
    // Each way needs it playing: whoever runs the tool is asked to start
    // it before the first, and whenever a way leaves it stopped and it
    // can't be played again otherwise.
    private var going = true

    init(running: NSRunningApplication, script: (pause: ScriptCommand, play: ScriptCommand, toggles: Bool)?) {
        self.running = running
        self.script = script
        let pid = running.processIdentifier
        self.pid = pid
        let pressSwitch = PageState.shownBySwitch.flatMap { $0 == manualAccessibility || changes.switchesOn.contains($0) ? $0 : nil }
        self.pressSwitch = pressSwitch
        pressSwitchLeftOn = pressSwitch.map(changes.wasFoundOn) ?? false
        panelReachable = canBeNowPlaying && AXIsProcessTrusted()
        if let script { plays.append((.script, "AppleScript", { sendScript(script.play) })) }
        if menu != nil { plays.append((.menu, "its menu", { pressMenuToggle(pid: pid) })) }
        plays.append((.page, "its page's button", { [unowned self] in
            guard page?.toggle != nil else { return false }
            self.switchForPress(true)
            return self.pressPage(pausing: false)
        }))
        if panelReachable { plays.append((.panel, "the Now Playing panel", { pressInPanel(pid: pid, pausing: false) })) }
    }

    private func pressPage(pausing: Bool) -> Bool {
        guard let button = pageButtonToPress(pid: pid, pausing: pausing) else {
            let shown = !(pageButtons(pid: pid) ?? []).isEmpty
            say("    " + (shown ? "no button in sight to press" : "its page didn't show"))
            trialProblem = shown ? "its page showed no Play/Pause to press"
                : "its page didn't show" + (PageState.shownBySwitch.map { " with \(switchName($0)) on" } ?? "")
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

    private func switchForPress(_ on: Bool) {
        guard let pressSwitch, !first else { return }
        setPageSwitch(pressSwitch, on: on, pid: pid)
    }

    /// Whether a way worked in this window state (with no window, in the one run).
    private func workedHere(_ way: Way) -> Bool {
        guard let state else { return TestResults.first[way] == .worked }
        return TestResults.byState[way]?.contains { $0.state == state && $0.result == .worked } == true
    }

    /// A way that left it paused, or a track that ended: before anyone is
    /// asked, in any state, it's played again by a way that worked in this
    /// state, else by the others: AppleScript, its menu, then the panel, a
    /// last resort as it shows on screen. Each only while it doesn't play (a
    /// toggle would pause it), judged by the surest sign it shows.
    private func playAgain() -> Bool {
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

    private func ready() -> Bool {
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

    private func record(_ way: Way, _ result: TrialResult) {
        if first { TestResults.first[way] = result }
        if let state { TestResults.byState[way, default: []].append((state, result, whyFailed(way, in: state, result))) }
        trialProblem = nil
        trialRan = true
        lastWay = way
    }

    /// A trial whose track ended meanwhile (`trialTrackEnded`) is run
    /// again once it plays (`ready`): it said nothing about the way. Ended
    /// twice, it fails saying so.
    private func trialAgainIfEnded(_ way: Way, _ run: () -> TrialResult) -> TrialResult {
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

    /// Each window state in turn (with its windows closed, that state's one
    /// run, as it is; with no window states, one run as it is), each way
    /// tried there; then its window put back, and a page switch that was
    /// found on turned on again.
    func run() {
        let states: [WindowState?] = TestScope.windowTest.map { $0.states } ?? [TestScope.windowsClosed ? .windowsClosed : nil]
        for (index, next) in states.enumerated() where going {
            stopIfRequested(trialRan ? nil : "stopped: its window is put back")
            state = next
            if let next {
                say(CheckReportLine.windowState(index + 1, of: states.count, next))
            }
            if let next, let windowTest = TestScope.windowTest {
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
            }
            WindowTest.currentState = next
            trialProblem = nil
            if let script, scriptProblem == nil, ready() {
                // A toggle is sent for the pause only while it plays, and again to play.
                record(.script, trialAgainIfEnded(.script) {
                    trial(CheckReportLine.trial(.script, detail: "\(script.pause.name), \(script.play.name)"), pid: pid,
                          pause: { _ in sendScript(script.pause) }, play: { _ in sendScript(script.play) },
                          whilePaused: first ? { [self] in checkVolume(); learnPageButton(pid: pid) } : nil)
                })
                stopIfRequested()
                RunLoop.main.run(until: Date().addingTimeInterval(1))
            }
            if menu != nil, ready() {
                record(.menu, trialAgainIfEnded(.menu) {
                    trial(CheckReportLine.trial(.menu), pid: pid,
                          pause: { _ in pressMenuToggle(pid: pid) }, play: { _ in pressMenuToggle(pid: pid) },
                          whilePaused: first ? { [self] in learnPageButton(pid: pid) } : nil)
                })
                stopIfRequested()
                RunLoop.main.run(until: Date().addingTimeInterval(1))
            }
            // No other way paused it and no button is named Play or Pause: as
            // AutoHush asks ("It's Paused"), whoever runs the check pauses it, and
            // the button whose words changed is learned.
            let pausedByAnother = [TestResults.first[.script], TestResults.first[.menu]].contains { $0 == .worked || $0 == .pausedOnly }
            if first, learned == nil, !pausedByAnother, page?.toggle == nil, page?.buttons ?? 0 > 0, ready() {
                if !learner.hasPlayed {
                    // Its page is out of sight, where its words can't be learned: nobody is asked.
                    learnPageButton(pid: pid)
                } else {
                    say(CheckReportLine.waitingToPause(appName, minutes: 2))
                    inputBlock.pause()
                    Polling.wait(seconds: 120, every: 0.5, runLoop: true, until: { !isPlaying(pid) || stopState.isRequested })
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
                                 undo: { [self] in switchForPress(false) },
                                 whilePaused: first ? { [self] in learnPageButton(pid: pid) } : { [self] in switchForPress(false) })
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
                    TestResults.first[.panel] = .didNotPause
                }
            } else if !AXIsProcessTrusted() {
                if first { say("  the Now Playing panel: not pressed: \(noPanelItem)") }
            } else if ready() {
                let result = trialAgainIfEnded(.panel) {
                    panelProblem = nil
                    return trial(CheckReportLine.trial(.panel), pid: pid, pause: { pressInPanel(pid: pid, pausing: true, heard: $0) },
                                 play: { pressInPanel(pid: pid, pausing: false, choice: .lastElseApp, heard: $0) },
                                 undo: { [self] in
                                     // The row pressed may have been another app's: pressed again, that app plays on.
                                     if panelRowText != nil { _ = pressInPanel(pid: pid, pausing: false, choice: .lastOnly) }
                                 },
                                 whilePaused: first ? { [self] in learnPageButton(pid: pid) } : nil)
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
                    TestResults.untested[.panel, default: [:]][state] = "its item wasn't found in the menu bar then"
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
        WindowTest.currentState = nil
        if let windowTest = TestScope.windowTest {
            stopState.setInTrial(true)
            let problem = windowTest.restore()
            stopState.setInTrial(false)
            WindowTest.currentState = nil
            if inputBlock.end() { say(CheckReportLine.free) }
            // Read again: another app's windows that covered it may be behind it now.
            let now = AppWindows.state(of: running)
            say(now == windowTest.original || problem != nil
                ? "  its window put back as it was (\(windowTest.original.title))" + (problem.map { ", but \($0)" } ?? "")
                : "  its window put back where it was, but it was \(windowTest.original.title) and it's \(now?.title ?? "gone") now")
            stopIfRequested()
        }
        if pressSwitchLeftOn, let pressSwitch, setSwitch(pressSwitch, true, pid: pid) {
            changes.noteOff(pressSwitch)
        }
        if let seen = notifications?.seen, !seen.isEmpty {
            for (name, keys) in seen.sorted(by: { $0.key < $1.key }) {
                say("  notification: \(name)" + (keys.isEmpty ? "" : " [\(keys.sorted().joined(separator: ", "))]"))
            }
        } else {
            say("  notifications: none under the usual names (\(bundleID).\(stateNotificationSuffixes[0]), …)")
        }
    }
}
