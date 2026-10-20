import AppKit
import AutoHushKit
import CheckedPlayers
import MenuPlayers
import PlayerCheckKit

// MARK: - Whether it plays

/// What a look shows, for the log: its menu's and page's words only (`shown`).
extension Look {
    @MainActor var line: String {
        [menuTitle.map { "menu \(shown($0))" + (menuState == .stopped ? " (disabled)" : "") }, state.map { "state \($0.rawValue)" },
         reported.map { "reports \($0.lowercased())" },
         pageToggle.map { "page \(shown($0))" + (pageCurrent ? "" : " (out of sight: its word lags)") }, "sound \(sounding ? "on" : "off")",
         audible.map { $0 ? "heard" : "silent" },
         awake.map { awake in
             // A browser's web app: the browser's "Playing audio" assertions, counted (`pagesSay`).
             webAppBrowser == nil ? (awake ? "keeps the Mac awake" : "no keep-awake assertion")
                 : awake ? "its “Playing audio” held" : "no “Playing audio” of its own"
         }]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

@MainActor func look(_ pid: pid_t, level: Bool = false) -> Look {
    // The log is read only for an app with no scripted state (its own is
    // surer), and, for a press, only while its player bar isn't on screen.
    let state = scriptedState()
    let toggle = menu == nil ? nil : menuToggle(pid: pid)
    // A browser's web app's sound is its browser's (its launcher has none).
    let sounding = !soundProcesses(of: soundOwner(pid)).isEmpty
    let heard = level ? audible(pid) : nil
    var reported = state == nil && !barShowsState ? reportedState() : nil
    if heard == true {
        noteHeard(against: reported)
        if reportIsStale { reported = nil }
    }
    let pageToggle = page?.toggle == nil ? nil : pageToggleLabel(pid)
    return Look(menuTitle: toggle?.title, menuState: toggle.flatMap(menuState), state: state,
                reported: reported,
                pageToggle: pageToggle, pageSays: pageToggle.flatMap(wordSays), pageCurrent: pageWordCurrent,
                sounding: sounding, audible: heard, awake: awake(pid, sounding: sounding))
}

/// A look for a press's `Sign`: its level is measured (half a second) only
/// when nothing surer shows the state, so presses stay quick.
@MainActor func lookForSign(_ pid: pid_t) -> Look {
    let quick = look(pid)
    // A report of a pause is checked against its level once: it may be stale.
    let reportOfPause = quick.surest == .report && quick.says(.report) != .playing
    guard levelsAllowed, reportOfPause || [SignKind.script, .report, .page].allSatisfy({ quick.says($0) == nil }) else { return quick }
    return look(pid, level: true)
}

/// Whether it plays, as far as can be seen, in `SignKind`'s order (its
/// level measured only when it comes to it), else by its sound output
/// (which an Electron app or a web app keeps a few seconds after a pause,
/// some players a minute).
@MainActor func isPlaying(_ pid: pid_t) -> Bool {
    let now = look(pid)
    for kind in SignKind.allCases {
        if kind == .level {
            if let heard = audible(pid) { return heard }
        } else if let said = now.says(kind) {
            // A report of a pause may be stale: heard, it plays.
            if kind == .report, said != .playing, audible(pid) == true {
                noteHeard(against: now.reported)
                return true
            }
            return said == .playing
        }
    }
    return now.sounding
}

/// Waits up to `seconds`, running the run loop (for notifications), until
/// `done` holds, then a second more for late notifications; the last look
/// (its level measured when `level`). A stop doesn't cut it short: it waits
/// in trials and plays, whose end it waits for anyway.
@MainActor func waitFor(_ seconds: Double, pid: pid_t, level: Bool = false, until done: (Look) -> Bool) -> Look {
    let current = Polling.wait(seconds: seconds, every: 0.25, runLoop: true, reading: { look(pid, level: level) }, until: done)
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    return current
}

/// Waits until it plays, asking whoever runs the tool to start it (the
/// Player Check app shows the "waiting:" line as a request): true once it
/// plays, false after `seconds` (or at a stop).
@MainActor func waitUntilPlaying(_ pid: pid_t, seconds: Double = 120) -> Bool {
    if isPlaying(pid) {
        countOtherPages(pid)
        return true
    }
    countPagesBeforePlaying(pid, saying: true)
    say(CheckReportLine.waitingToPlay(appName, minutes: Int(seconds / 60))
        + (testMute == nil ? "" : ". It stays muted meanwhile, so you won't hear it start"))
    // Whoever runs the check may need the mouse and keyboard for it.
    inputBlock.pause()
    defer { inputBlock.resume() }
    // From the look above (it didn't play): a stop ends the wait before its first pause.
    let plays = Polling.wait(seconds: seconds, every: 0.5, runLoop: true, from: false, reading: {
        countPagesBeforePlaying(pid, saying: false)
        return isPlaying(pid)
    }, until: { $0 || stopState.isRequested })
    guard plays else { return false }
    say("  it plays: testing")
    RunLoop.main.run(until: Date().addingTimeInterval(1.5)) // it settles, and reports to Now Playing
    countOtherPages(pid)
    return true
}

// MARK: - A trial

/// Set by `trial` when, after its play, the app read stopped where its pause
/// had left it paused: its track ended meanwhile, so the trial says nothing
/// about the way and is run again.
@MainActor var trialTrackEnded = false
/// Why the trial running failed, as its press said (no button to press…).
@MainActor var trialProblem: String?

/// Pauses with `pause`, sees whether it took (`Sign`), plays again with
/// `play` if it did; `undo` runs when it didn't (a press that may have hit
/// another app), `whilePaused` between a pause that took and the play (to
/// learn the page's button, or check the volume, while it's silent). What
/// the state notifications announced is said after each. A play that didn't
/// take is pressed once more (still a failure, said so in `trialProblem`); a
/// track that ended meanwhile sets `trialTrackEnded`. A stop meanwhile waits
/// until it plays again. `pause` and `play` are given its level as the
/// trial heard it last (nil when it wasn't measured), for a press that needs
/// it (the panel's, for a row that doesn't follow the app).
@MainActor func trial(_ label: String, pid: pid_t, pause: (_ heard: Bool?) -> Bool, play: (_ heard: Bool?) -> Bool,
                      undo: (() -> Void)? = nil, whilePaused: (() -> Void)? = nil, reading: TrialReading = .live) -> TrialResult {
    stopState.setInTrial(true)
    defer { stopState.setInTrial(false) }
    trialTrackEnded = false
    let before = reading.look(pid, true)
    let sign = Sign(before: before)
    say("  \(label): before, \(before.line)")
    let pausedAt = Date()
    guard pause(before.audible) else { say("    couldn't send it"); return .didNotPause }
    let after = reading.waitFor(4, pid, sign.byLevel, sign.paused)
    guard sign.paused(after) else {
        say("\(CheckReportLine.afterPause): \(after.line) → it didn't pause in 4 s")
        announcementLine(since: pausedAt).map { say($0) }
        undo?()
        return .didNotPause
    }
    say("\(CheckReportLine.afterPause): \(after.line) → it paused")
    announcementLine(since: pausedAt).map { say($0) }
    let pauseAnnounced = notifications?.announced(since: pausedAt).last.flatMap { $0.state == .playing ? nil : $0.name }
    whilePaused?()
    /// Once more, before anyone is asked: a play it missed shows as such, and
    /// still fails the way. Not when it plays by now (a toggle would pause it again).
    func pressedOnceMore() -> TrialResult {
        let now = reading.look(pid, sign.byLevel)
        guard !sign.playing(now) else {
            say("    now: \(now.line) → it plays: its play took late")
            trialProblem = "it paused, but played again only after more than 4 s"
            return .pausedOnly
        }
        guard play(now.audible) else {
            say("    pressed once more: couldn't play it again either")
            return .pausedOnly
        }
        let second = reading.waitFor(4, pid, sign.byLevel, sign.playing)
        if sign.playing(second) {
            say("    pressed once more: \(second.line) → it plays: the first didn't take")
            trialProblem = "it paused, but played again only when pressed a second time" + (trialProblem.map { " (the first: \($0))" } ?? "")
        } else if second.stopped, !after.stopped {
            say("    pressed once more: \(second.line) → it stopped: its track ended meanwhile")
            trialTrackEnded = true
        } else {
            say("    pressed once more: \(second.line) → it didn't play either")
        }
        return .pausedOnly
    }
    let playedAt = Date()
    guard play(after.audible) else {
        say("    couldn't play it again")
        return pressedOnceMore()
    }
    let back = reading.waitFor(4, pid, sign.byLevel, sign.playing)
    let again = sign.playing(back)
    if !again, back.stopped, !after.stopped {
        say("    after playing again: \(back.line) → it stopped: its track ended meanwhile")
        trialTrackEnded = true
        return .pausedOnly
    }
    say("    after playing again: \(back.line) → " + (again ? "it plays" : "it didn't play again in 4 s"))
    announcementLine(since: playedAt).map { say($0) }
    if let pauseAnnounced, notifications?.announced(since: playedAt).last.map({ $0.state == .playing && $0.name == pauseAnnounced }) == true {
        announcingNotification = announcingNotification ?? pauseAnnounced
    }
    return again ? .worked : pressedOnceMore()
}

/// How a trial reads the app: `look` and `waitFor` (its level measured when
/// asked), unless a test gives it what the app shows instead.
struct TrialReading {
    var look: @MainActor (_ pid: pid_t, _ level: Bool) -> Look
    var waitFor: @MainActor (_ seconds: Double, _ pid: pid_t, _ level: Bool, _ done: (Look) -> Bool) -> Look

    static let live = TrialReading(look: { pid, level in PlayerCheck.look(pid, level: level) },
                                   waitFor: { seconds, pid, level, done in PlayerCheck.waitFor(seconds, pid: pid, level: level, until: done) })
}
