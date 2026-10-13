import AppKit
import AutoHushKit
import CoreAudio
import IOKit.pwr_mgt
import os

// MARK: - Sound

/// The process macOS holds responsible for `pid` (the app behind a helper),
/// as AutoHush asks it (`ProcessResponsibility`); itself when unknown.
func responsible(_ pid: pid_t) -> pid_t { ProcessResponsibility.responsiblePID(for: pid) ?? pid }

/// A process's executable, as `proc_pidpath` tells it.
func executablePath(of pid: pid_t) -> String? {
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
    return String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

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
    let permission = TCCAudioCapturePermission()
    var status = permission.status()
    if status == .notDetermined, asking {
        say("  Audio Recording: asked (to measure its sound as AutoHush does, and to keep it silent meanwhile)")
        let answer = OSAllocatedUnfairLock<Bool?>(initialState: nil)
        permission.request { @Sendable granted in answer.withLock { $0 = granted } } // answered on another thread
        let deadline = Date().addingTimeInterval(120)
        while answer.withLock({ $0 }) == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
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

/// The process that owns the app's sound and keep-awake assertions: a
/// Chromium browser's web app's browser (one process for all its pages:
/// tabs, calls, web apps), else the app.
func soundOwner(_ pid: pid_t) -> pid_t { switchTarget(pid) }

/// The pages a Chromium browser plays now: it holds one "Playing audio"
/// assertion per playing page (its audio wake lock), all on its own process
/// (Chrome and Brave, measured: a web app, a tab's file, a Web Audio tone, a
/// WebRTC call, a tab in another profile each added one). AutoHush's reader
/// keeps a process's assertions as a set, so they're counted here.
func playingPages(of browserPID: pid_t) -> Int {
    var byProcess: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
          let all = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return 0 }
    return (all[NSNumber(value: browserPID)] ?? []).filter {
        $0["AssertionOnBehalfOfPID"] == nil && $0["AssertName"] as? String == "Playing audio"
    }.count
}

/// A browser's web app found playing: the browser's other playing pages
/// then, which its keep-awake sign compares with (`pagesSay`); nil until
/// counted, and once they changed.
@MainActor var otherPlayingPages: Int?

/// Counts the browser's other playing pages, the web app playing: when
/// it's first found playing, and again after they changed.
@MainActor func countOtherPages(_ pid: pid_t) {
    guard let browser = webAppBrowser, otherPlayingPages == nil else { return }
    let total = playingPages(of: soundOwner(pid))
    otherPlayingPages = total > 0 ? total - 1 : nil
    say("  \(browser)'s playing pages: \(total), this one's among them (one “Playing audio” assertion each)")
}

/// Whether a browser's web app plays, as the browser's "Playing audio"
/// assertions tell it: one more than its other pages', it plays; as many,
/// it doesn't (its own goes about 3 s after it pauses). Nil before they're
/// counted, and once another page started or stopped (said once).
@MainActor func pagesSay(_ pid: pid_t) -> Bool? {
    guard let others = otherPlayingPages else { return nil }
    let total = playingPages(of: soundOwner(pid))
    if total == others + 1 { return true }
    if total == others { return false }
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
    IOKitPowerAssertionReader().assertionsByProcess()
        .filter { ProcessResponsibility.isOwned($0.key, by: pid) }
        .reduce(into: Set()) { $0.formUnion($1.value) }
}

/// Whether it plays as its assertions tell it, AntiDot mode's rule: holding
/// its own "keep the Mac awake" one, it plays; seen holding one while its
/// sound was on (in this run), but not now, it's paused; nil while it never did.
@MainActor var heldWhileSounding = false
@MainActor func awake(_ pid: pid_t, sounding: Bool) -> Bool? {
    if webAppBrowser != nil { return pagesSay(pid) }
    let held = assertions(of: pid).contains { $0.kind == .system }
    if held, sounding { heldWhileSounding = true }
    return held ? true : heldWhileSounding ? false : nil
}

@MainActor func reportSound() {
    say()
    say("Sound and Now Playing")
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
        let owner = soundOwner(running.processIdentifier)
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
        say("  keeps the Mac awake: " + (held.isEmpty ? "no assertion now (media apps hold one while they play, as AntiDot mode reads it)"
            : held.sorted { $0.name < $1.name }.map { "“\($0.name)”" + ($0.kind == .display ? " (display only)" : "") }.joined(separator: ", ")))
        _ = awake(running.processIdentifier, sounding: !sound.isEmpty)
    }
    let holder = nowPlayingPID()
    let holds = holder > 0 && (holder == running.processIdentifier || responsible(holder) == running.processIdentifier)
    let other = holder == 0 ? "no app" : NSRunningApplication(processIdentifier: responsible(holder))?.localizedName ?? "pid \(holder)"
    say("  Now Playing: " + (holder < 0 ? "MediaRemote didn't answer"
        : holds ? "this app (until another app reports playing)"
        : holder == 0 ? "no app" : "another app (\(other))"))
}

// MARK: - Silent through a test

/// Keeps the app silent through a test: its audio processes behind a muted
/// process tap, as AutoHush mutes a web app's ad (`ProcessTapMuter`). Its
/// sound still reaches every other tap, so its level is still measured
/// (measured with VLC: nothing reached the output while an unmuted tap, and
/// the muting one, heard it at 0.7–0.8). Nothing else it shows changes (its
/// scripted state, what it reports to Now Playing, its page, its keep-awake
/// assertions, its menu, its open output): the app doesn't know. Its
/// processes are looked at every 0.1 s, so one it starts later (an audio
/// service started at its first play) is muted within that, a new tap made
/// before the old one goes; a set of processes that can't be tapped yet is
/// tried again every half second. A tap ends with this tool, so a stop or a
/// crash lets it be heard again too.
final class TestMute: @unchecked Sendable {
    private let pid: pid_t
    private let queue = DispatchQueue(label: "playercheck.mute")
    private var timer: DispatchSourceTimer?
    private var muter: ProcessTapMuter?
    /// The processes behind `muter`.
    private var muted: Set<AudioObjectID> = []
    /// When a set that couldn't be muted is tried again.
    private var retryAt = Date.distantPast
    /// Whether a mute failed at some point: the app may have been heard.
    private var failed = false

    init(pid: pid_t) { self.pid = pid }

    /// Mutes it once before it returns (so it's silent when the test says
    /// so), then keeps it so; whether its processes are muted now (true too
    /// when it has none yet).
    func start() -> Bool {
        let now = queue.sync { () -> Bool in
            refresh()
            return Set(OwnedAudioProcesses.objects(ownedBy: pid)).isSubset(of: muted)
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in self?.refresh() }
        queue.sync { self.timer = timer }
        timer.resume()
        return now
    }

    private func refresh() {
        let now = Set(OwnedAudioProcesses.objects(ownedBy: pid))
        guard !now.isEmpty, !now.isSubset(of: muted), Date() >= retryAt else { return }
        let next = ProcessTapMuter()
        guard next.mute(appPID: pid) else {
            failed = true
            retryAt = Date().addingTimeInterval(0.5)
            return
        }
        muter?.unmute(appPID: pid)
        muter = next
        muted = now
        retryAt = .distantPast
    }

    /// Lets it be heard again; whether a mute failed meanwhile.
    func stop() -> Bool {
        queue.sync {
            timer?.cancel()
            timer = nil
            muter?.unmute(appPID: pid)
            muter = nil
            return failed
        }
    }
}

@MainActor var testMute: TestMute?

/// Heard again once the test is done with it (playing again if it was).
@MainActor func unmuteAfterTest() {
    guard let mute = testMute else { return }
    testMute = nil
    say("  \(webAppBrowser ?? appName) unmuted: the test is over"
        + (mute.stop() ? " (its sound couldn't be muted for a while: it may have been heard)" : ""))
}
