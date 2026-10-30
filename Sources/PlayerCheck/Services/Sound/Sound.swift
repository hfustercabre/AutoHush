import AppKit
import PlayerCheckKit
import AutoHushKit
import CoreAudio
import os
import WebAppPlayers

// MARK: - Sound

/// The process macOS holds responsible for `pid` (the app behind a helper),
/// as AutoHush asks it (`ProcessResponsibility`); itself when unknown.
func responsible(_ pid: pid_t) -> pid_t { ProcessResponsibility.responsiblePID(for: pid) ?? pid }

/// A process's executable, as AutoHush reads it (`proc_pidpath`).
func executablePath(of pid: pid_t) -> String? { ProcessAudioSourceIdentifier.executablePath(of: pid) }

/// An app's name, else its executable's.
func processName(_ pid: pid_t) -> String {
    if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return name }
    guard let path = executablePath(of: pid) else { return "pid \(pid)" }
    return URL(fileURLWithPath: path).lastPathComponent
}

/// The processes with sound output running that the app owns (its own, or
/// helpers such as a web app's WebKit process), found as AutoHush finds a
/// player's (`OwnedAudioProcesses`), as "name (bundle ID, pid)".
func soundProcesses(of pid: pid_t) -> [String] {
    OwnedAudioProcesses.objects(ownedBy: pid).compactMap { object in
        guard CoreAudioProperty.value(kAudioProcessPropertyIsRunningOutput, of: object, initial: UInt32(0)) == 1,
              let processPID = CoreAudioProperty.value(kAudioProcessPropertyPID, of: object, initial: pid_t(0)) else { return nil }
        let id = CoreAudioProperty.string(kAudioProcessPropertyBundleID, of: object) ?? ""
        return "\(processName(processPID)) (\(id.isEmpty ? "no bundle ID" : id), pid \(processPID))"
    }.sorted()
}

/// Whether its level can be measured (`setUpLevels`).
@MainActor var levelsAllowed = false

/// Sets `levelsAllowed`: whether its sound is measured, as AutoHush judges
/// sound by default: by its level, through process taps, which need Audio
/// Recording (and show macOS's recording indicator while they listen). A
/// check asks for it when it's undecided (in its Permissions, `saying`
/// nothing about its level yet); a press only uses it when it's allowed.
@MainActor func setUpLevels(asking: Bool, saying: Bool = true) {
    // AntiDot mode (--no-taps): nothing is tapped, so nothing is asked.
    guard !noTaps else {
        levelsAllowed = false
        if asking, saying { say("  its level: not measured: no audio taps in AntiDot mode; judged by what it tells macOS and its open output") }
        return
    }
    let permission = TCCAudioCapturePermission()
    var status = permission.status()
    if status == .notDetermined, asking {
        say("  Audio Recording: asked (to measure its sound as AutoHush does, and to keep it silent meanwhile)")
        let answer = OSAllocatedUnfairLock<Bool?>(initialState: nil)
        permission.request { @Sendable granted in answer.withLock { $0 = granted } } // answered on another thread
        Polling.wait(seconds: 120, every: 0.2, runLoop: true, until: { answer.withLock { $0 } != nil })
        status = answer.withLock { $0 } == true ? .granted : permission.status()
    }
    levelsAllowed = status == .granted
    guard asking, saying else { return }
    switch status {
    case .granted?:
        say("  its level: measured as AutoHush measures it (process taps; macOS shows its recording indicator meanwhile)")
    case .denied?, .notDetermined?:
        say("  its level: not measured: Audio Recording isn't allowed (System Settings → Privacy & Security →"
            + " Screen & System Audio Recording); judged by what it tells macOS and its open output instead")
    case nil:
        say("  its level: not measured: whether Audio Recording is allowed can't be asked")
    }
}

/// Whether it can be heard now, by its level (half a second of listening,
/// AutoHush's threshold: `ProcessTapLevelProbe`); nil when it isn't measured.
@MainActor func audible(_ pid: pid_t) -> Bool? {
    // A browser's web app: its sound can't be told from the browser's other pages'.
    guard webAppBrowser == nil else { return nil }
    return levelsAllowed ? ProcessTapLevelProbe().isAudible(appPID: pid) : nil
}

/// The pages a Chromium browser plays now, as AutoHush counts them for a
/// Chromium web app (`PlayingPages`: one "Playing audio" assertion each).
func playingPages(of browserPID: pid_t) -> Int { PlayingPages.count(ofBrowser: browserPID) }

/// A browser's web app found playing: the browser's other playing pages
/// then, which its keep-awake sign compares with (`pagesSay`); nil until
/// counted, and once they changed.
@MainActor var otherPlayingPages: Int?

/// Counts the browser's other playing pages, the web app playing: when
/// it's first found playing, and again after they changed.
@MainActor func countOtherPages(_ pid: pid_t) {
    guard let browser = webAppBrowser, otherPlayingPages == nil else { return }
    let total = playingPages(of: switchTarget(pid))
    // None held: nothing to count from (it's taken at the next look while it plays).
    guard total > 0 else { return }
    otherPlayingPages = total - 1
    say("  \(browser)'s playing pages: \(total), this one's among them (one “Playing audio” assertion each)")
}

/// Before a wait for it to play: the browser's playing pages now are the
/// others' (it doesn't play yet), so one more says it plays, the one sign of
/// it without what it reports to Now Playing (read by administrators only).
/// Counted again while waiting whenever they changed (`pagesSay` let them
/// go): one it played before the wait, and paused for it, lowers them.
@MainActor func countPagesBeforePlaying(_ pid: pid_t, saying: Bool) {
    guard let browser = webAppBrowser, otherPlayingPages == nil else { return }
    let total = playingPages(of: switchTarget(pid))
    otherPlayingPages = total
    if saying { say("  \(browser)'s playing pages now, without it: \(total); once it plays, there's one more") }
}

/// Whether a browser's web app plays, as the browser's "Playing audio"
/// assertions tell it: one more than its other pages', it plays; as many,
/// it doesn't (its own goes about 3 s after it pauses). Nil before they're
/// counted, and once another page started or stopped (said once).
@MainActor func pagesSay(_ pid: pid_t) -> Bool? {
    guard let others = otherPlayingPages else { return nil }
    let total = playingPages(of: switchTarget(pid))
    if let plays = PlayingPages.webAppPlays(total: total, others: others) { return plays }
    otherPlayingPages = nil
    say("    \(webAppBrowser ?? "its browser")'s playing pages went to \(total), from \(others) others: another page started or stopped,"
        + " so its assertions no longer tell")
    return nil
}

/// Its own keep-awake assertions now (its processes' and helpers'), as
/// AutoHush's AntiDot mode reads them (`IOKitPowerAssertionReader`): media
/// apps hold one while they play and let it go when they pause, though their
/// output stays open.
func assertions(of pid: pid_t) -> Set<PowerAssertion> {
    IOKitPowerAssertionReader().assertions(ownedBy: pid)
}

/// Whether it plays as its assertions tell it, AntiDot mode's rule
/// (`AnnouncedAssertions.announcing`, its names learned while its sound is
/// on, in this run): announcing, it plays; seen announcing while its sound
/// was on, but not now, it's paused; nil while it never did.
@MainActor var announcedAssertions = AnnouncedAssertions()
@MainActor var heldWhileSounding = false
@MainActor func awake(_ pid: pid_t, sounding: Bool) -> Bool? {
    if webAppBrowser != nil { return pagesSay(pid) }
    let own = assertions(of: pid)
    if sounding { announcedAssertions.learn(own) }
    let held = announcedAssertions.announcing(own)
    if held, sounding { heldWhileSounding = true }
    return held ? true : heldWhileSounding ? false : nil
}

@MainActor func reportSound() {
    say()
    say(CheckReportLine.Heading.sound.rawValue)
    // Only shown, so not read for --play or --pause (it asks a second copy of
    // this tool who's Now Playing: about 0.3 s).
    if action != nil {
        say("  not read: only shown in a check")
        setUpLevels(asking: false)
        return
    }
    guard let running else {
        say("  not checked: the app isn't running")
        return
    }
    if let browser = webAppBrowser {
        // A browser's web app: its sound and assertions are the browser's.
        let owner = switchTarget(running.processIdentifier)
        let sound = soundProcesses(of: owner)
        say("  its sound is \(browser)'s, shared with its tabs and other web apps: "
            + (sound.isEmpty ? "none running now" : sound.joined(separator: "; ")))
        setUpLevels(asking: true, saying: false)
        say("  its level: not measured: \(browser) plays all its pages' sound together")
        say("  \(browser)'s playing pages now: \(playingPages(of: owner)) (one “Playing audio” assertion each: tabs, calls, web apps);"
            + " counted once it plays, they tell whether it does")
    } else {
        let sound = soundProcesses(of: running.processIdentifier)
        say("  sound output running now: " + (sound.isEmpty ? "none (it isn't playing)" : sound.joined(separator: "; ")))
        setUpLevels(asking: true)
        if levelsAllowed { say("  heard now: " + (audible(running.processIdentifier) == true ? "yes" : "no")) }
        let held = assertions(of: running.processIdentifier)
        // Counted, not named: an app may name one for what it plays.
        let display = held.filter { $0.kind == .display }.count
        say("  keeps the Mac awake: " + (held.isEmpty ? "no assertion now (media apps hold one while they play, as AntiDot mode reads it)"
            : "\(held.count) assertion\(held.count == 1 ? "" : "s")" + (display == 0 ? "" : " (\(display) for the display only)")))
        _ = awake(running.processIdentifier, sounding: !sound.isEmpty)
    }
    let holder = nowPlayingPID()
    let holds = isNowPlaying(running.processIdentifier, holder: holder)
    let other = holder == 0 ? "no app" : NSRunningApplication(processIdentifier: responsible(holder))?.localizedName ?? "pid \(holder)"
    say("  Now Playing: " + (holder < 0 ? "MediaRemote didn't answer"
        : holds ? "this app (until another app reports playing)"
        : holder == 0 ? "no app" : "another app (\(other))"))
}

// MARK: - Silent through a test

/// The test's mute (`TestMute`), while it lasts.
@MainActor var testMute: TestMute?

/// Heard again once the test is done with it (playing again if it was).
@MainActor func unmuteAfterTest() {
    guard let mute = testMute else { return }
    testMute = nil
    say("  \(webAppBrowser ?? appName) unmuted: the test is over"
        + (mute.stop() ? " (its sound couldn't be muted for a while: it may have been heard)" : ""))
}
