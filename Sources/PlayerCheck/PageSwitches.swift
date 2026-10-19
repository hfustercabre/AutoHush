import AppKit
import AutoHushKit

// MARK: - The switches for assistive tools

/// Turns a switch on; whether the app took it. One this tool turned on is
/// turned back off at the end, unless it may have been on before: VoiceOver's
/// reads back, so one already on is left alone; Electron's reads back off
/// even while it's on, so with the page readable already (someone
/// may have it on) a check leaves it on, and a stop sets it back on. A press
/// always turns it off at the end: it leaves the app as it found it, and a
/// page kept for later goes stale out of sight (an Electron player's took
/// no presses after minutes on another desktop).
@MainActor func turnOn(_ attribute: String, pid: pid_t, pageReadable: Bool) -> Bool {
    if attribute == enhancedUserInterface, AXUIElement.application(switchTarget(pid), timeout: 1).value(attribute) as? Bool == true {
        say("  \(switchName(attribute)) (\(attribute)) is on already: VoiceOver or another tool turned it on, so it's left on")
        changes.foundOn(attribute)
        return true
    }
    guard setSwitch(attribute, true, pid: pid) else {
        say("  \(switchName(attribute)) (\(attribute)): not taken")
        return false
    }
    if attribute == manualAccessibility, pageReadable, action == nil {
        say("  \(switchName(attribute)) on, and left on: VoiceOver or another tool may have it on")
        changes.foundOn(attribute)
    } else {
        changes.noteOn(attribute)
    }
    return true
}

/// Turns the page's switch on, as a press of Player Check's own turns it
/// (noted, to be put back at the end), giving its page up to 4 s to show;
/// or off.
@MainActor func setPageSwitch(_ attribute: String, on: Bool, pid: pid_t) {
    guard on else {
        _ = setSwitch(attribute, false, pid: pid)
        return
    }
    if setSwitch(attribute, true, pid: pid) { changes.noteOn(attribute) }
    _ = waitForPage(pid, seconds: 4)
}

/// An Electron app takes presses on its page only in its fuller
/// accessibility mode, which starts 2 s after its switch last went on
/// (Electron debounces the requests; an off sent meanwhile cancels it, and
/// keeps a fuller mode already on: electron_application.mm). A press right
/// after the switch goes on does nothing, though the page shows and the
/// press is accepted. So before a press: at once when the switch reads back
/// on (Electron says so only in that mode), else not before those 2 s. A
/// Chromium browser's web app the same, the browser's complete mode 2 s
/// after its switch (chrome_browser_application_mac.mm); its switch reads
/// back on at once, so that tells nothing.
func waitForFullerMode(pid: pid_t) {
    let attribute: String
    switch hiddenInterface {
    case .electron?: attribute = manualAccessibility
    case .chromiumWebApp?: attribute = enhancedUserInterface
    default: return
    }
    guard let since = changes.switchSetOnAt(attribute) else { return }
    if isElectron {
        guard AXUIElement.application(pid, timeout: 1).value(manualAccessibility) as? Bool != true else { return }
    }
    let wait = 2.2 - Date().timeIntervalSince(since)
    guard wait > 0 else { return }
    log(String(format: "  waited %.1f s for %@'s fuller mode: its page takes presses only 2 s after its switch goes on",
               wait, webAppBrowser ?? "Electron"))
    Thread.sleep(forTimeInterval: wait)
}

/// Turns on the app's `switches` in turn, each given 4 s for its page to
/// show: whether a page showed (in `count`, after `shownAfter` s), nil when
/// the app took none. A Chromium app builds its page only while its window
/// can be seen (an Electron player's, covered: none), and once built it
/// stays readable covered, hidden or on another desktop; a CEF app, on
/// another desktop when its switch went on, and a Flutter app, behind other
/// windows, showed nothing
/// until the switch went on again in front. So when nothing shows, a check
/// brings the app forward a moment, once, turns on there again each switch
/// it took until one shows, then brings back the app that was in front. A
/// press never does (the tool should be as unintrusive as possible): it says
/// why the page can't be read, and the page way isn't used.
@MainActor func showPage(with switches: [String], pid: pid_t, count: inout Int, shownAfter: inout TimeInterval?) -> Bool? {
    /// Turns a switch this tool turned on back off.
    func off(_ attribute: String) {
        if changes.switchesOn.contains(attribute), setSwitch(attribute, false, pid: pid) { changes.noteOff(attribute) }
    }
    // The switches it took, and whether this tool turned each on (VoiceOver's
    // may have been on already: left as it is).
    var taken: [(attribute: String, ours: Bool)] = []
    var shown: (attribute: String, waited: (count: Int, after: TimeInterval))?
    for attribute in switches where shown == nil {
        guard turnOn(attribute, pid: pid, pageReadable: false) else { continue }
        taken.append((attribute, changes.switchesOn.contains(attribute)))
        let waited = waitForPage(pid, seconds: 4)
        if waited.count > 0 {
            shown = (attribute, waited)
        } else {
            say("  \(switchName(attribute)) (\(attribute)) on, but nothing showed in 4 s")
            off(attribute)
        }
    }
    guard !taken.isEmpty else { return nil }
    if shown == nil, action != nil { pageOutOfView = true }
    if shown == nil, action == nil {
        shown = inFront(pid: pid) {
            for (attribute, ours) in taken {
                if ours, !changes.switchesOn.contains(attribute), setSwitch(attribute, true, pid: pid) { changes.noteOn(attribute) }
                let waited = waitForPage(pid, seconds: 6)
                if waited.count > 0 { return (attribute, waited) }
                off(attribute)
            }
            return nil
        }
        say("  its window was out of sight: brought it forward a moment, with "
            + (taken.count == 1 ? "the switch" : "each switch") + " turned on again there"
            + " (Chromium and Flutter apps may build their \(isFlutter ? "interface" : "page") only while their window can be seen)"
            + (shown == nil ? "; nothing showed there either" : ""))
    }
    guard let (attribute, waited) = shown else { return false }
    count = waited.count
    shownAfter = waited.after
    pageSwitch = attribute
    return true
}

/// For a check: brings the app forward a moment for its page to be built,
/// runs `build` there, then brings back the app that was in front.
@MainActor func inFront<T>(pid: pid_t, _ build: () -> T) -> T {
    let front = NSWorkspace.shared.frontmostApplication
    if let front, front.processIdentifier != pid { changes.frontToRestore = front.bundleURL }
    bringForward(appURL)
    broughtForward = true
    let result = build()
    if let url = changes.frontToRestore {
        bringForward(url)
        changes.frontToRestore = nil
        // Its desktop slides away for about half a second, and the
        // frames read meanwhile are off (a CEF app's Play: not in sight).
        Thread.sleep(forTimeInterval: 1)
    }
    return result
}

/// Whether the page shows a player's Play/Pause: a button in sight named
/// so, with a player's slider around it (no hit test: a quick look).
@MainActor func showsPlayerBar(_ pid: pid_t) -> Bool {
    (pageButtons(pid: pid) ?? []).contains { $0.inSight && named($0.label, playPauseWords) && playerBar(of: $0.element) != nil }
}

/// For a check that found the page readable already but with no player's
/// Play/Pause in it: the page may be a leftover, so it's built again.
/// Electron drops part of its page when its switch goes off, and doesn't
/// keep it up to date out of sight: a first check of an Electron player, on another
/// desktop some ten minutes after a press had turned its switch off, found
/// no page button, and later checks did. The switch goes off and on, and the
/// player's bar is looked for up to 4 s; when it doesn't show, the app is
/// brought forward a moment, as `showPage` does (once per check), the switch
/// turned off and on there.
@MainActor func rebuildPage(with attribute: String, pid: pid_t) {
    func waitForBar(_ seconds: Double) -> Bool {
        Polling.wait(seconds: seconds, every: 0.25, lookingFirst: false, until: { showsPlayerBar(pid) })
    }
    func switchAgain() {
        _ = setSwitch(attribute, false, pid: pid)
        _ = setSwitch(attribute, true, pid: pid)
    }
    say("  no player's Play/Pause in it: it may be a leftover, so it's built again (\(switchName(attribute)) turned off and on)")
    let start = Date()
    switchAgain()
    if waitForBar(4) {
        say(String(format: "  its player bar showed after %.1f s", Date().timeIntervalSince(start)))
        return
    }
    let shown = inFront(pid: pid) {
        switchAgain()
        return waitForBar(6)
    }
    say("  not in place: brought it forward a moment, with the switch turned off and on there"
        + (shown ? String(format: "; its player bar showed (%.1f s in all)", Date().timeIntervalSince(start))
                 : "; still no player's Play/Pause"))
}

/// Why a press by the page didn't work, and what to try instead.
func pagePressHint() -> String {
    "; " + (webAppBrowser.map { "a \($0) web app" } ?? "an \(hiddenInterface.map { "app built with \($0.name)" } ?? "app")")
        + " may build its page, or take presses on it, only while its"
        + " window is in view: bring it into view and try again, or use another way (AppleScript, its menu, or the Now Playing panel"
        + " as a last resort)"
}
