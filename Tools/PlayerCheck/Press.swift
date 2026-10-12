import AppKit

// MARK: - Play or pause (--play, --pause)

/// Turns back off the switches this tool turned on, then exits.
@MainActor func finish(_ code: Int32) -> Never {
    switchesBackOff()
    exit(code)
}

/// Plays or pauses the app by `via`, else by the first way that works
/// (AppleScript, the page's button, the menu), and says how in one line.
@MainActor func press(_ action: Action) -> Never {
    quiet = false
    guard let running else {
        say("\(appName) isn't running: open it first.")
        finish(1)
    }
    let pid = running.processIdentifier
    let pausing = action == .pause
    /// It's that way already: nothing pressed.
    func already() -> Never {
        say("It's \(pausing ? "paused" : "playing") already.")
        finish(0)
    }
    /// Waits up to 6 s for `done`, looking every 0.05 s.
    func within(_ done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(6)
        while !done() {
            guard Date() < deadline else { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return true
    }
    var tried: [String] = []
    for way in via.map({ [$0] }) ?? [.script, .page, .menu] {
        switch way {
        case .script:
            guard let script = scriptControls() else {
                tried.append("no AppleScript play or pause")
                continue
            }
            // Its state answers when it has one (Spotify's, VLC's playing flag); else what shows.
            let isThere = { isPlaying(pid) != pausing }
            if isThere() { already() }
            let command = pausing ? script.pause : script.play
            // Its state notification, as AutoHush follows it, confirms as
            // soon as it comes; else its asked state does.
            let announced = NotificationLog(bundleID: bundleID)
            let sentAt = Date()
            let byNotification = { announced.lastState(since: sentAt).map { pausing ? $0 != .playing : $0 == .playing } == true }
            guard sendScript(command) else {
                tried.append(scriptProblem ?? "AppleScript \(command) failed")
                continue
            }
            if within({ byNotification() || isThere() }) {
                say("\(pausing ? "Paused" : "Played") it by AppleScript (\(command))"
                    + (byNotification() ? ", as its notification announced." : "."))
                finish(0)
            }
            tried.append("AppleScript \(command) sent, but it didn't change in 6 s")
        case .page:
            guard page?.toggle != nil else {
                tried.append((pageOutOfView ? "its page didn't show with "
                    + (hiddenInterface?.switches.map(switchName).joined(separator: " or ") ?? "the switch") + " on" : "no Play/Pause button on its page")
                    + (pageOutOfView ? pagePressHint() : ""))
                continue
            }
            // As it reports to Now Playing, else as its page's button says
            // (Pause while it plays, Play while it doesn't).
            let done = { isPlaying(pid) != pausing }
            if done() { already() }
            guard let button = pageButtonToPress(pid: pid, pausing: pausing) else {
                tried.append("couldn't find its page's \(pausing ? "Pause" : "Play")")
                continue
            }
            var why: String?
            guard pressPageButton(button, pausing: pausing, why: &why) else {
                tried.append(why ?? "couldn't press its page's \(pausing ? "Pause" : "Play")")
                continue
            }
            if within(done) {
                learnFromPress(button, before: button.label, pausing: pausing)
                say("\(pausing ? "Paused" : "Played") it with its page's “\(button.label)” button"
                    + (pageSwitch.map { ", \(switchName($0)) on" } ?? "")
                    + (broughtForward ? " (brought forward a moment: Chromium and Flutter apps may build it only while their window can be seen)." : "."))
                finish(0)
            }
            tried.append("pressed its page's “\(button.label)”, but it didn't change in 6 s"
                + (pausing ? " (AutoHush would mute it instead)" : "")
                + (hiddenInterface != nil && !button.onScreen ? pagePressHint() : ""))
        case .menu:
            guard let menu else {
                tried.append("no playback menu")
                continue
            }
            // Its first item toggles, so it's pressed only when it's the
            // other way; judged as a test judges it (`Sign`): its menu's word
            // counts only for an app with no surer sign, as Deezer's changes
            // late by itself.
            let before = lookForSign(pid)
            let sign = Sign(before: before)
            let done = { (now: Look) in pausing ? sign.paused(now) : sign.playing(now) }
            if done(before) { already() }
            let word = before.menuTitle ?? ""
            guard pressMenuToggle(pid: pid) else {
                tried.append("couldn't press its menu's first item")
                continue
            }
            if within({ done(look(pid, level: sign.byLevel)) }) {
                say("\(pausing ? "Paused" : "Played") it with its “\(menu.title)” menu's “\(word)”.")
                finish(0)
            }
            tried.append("pressed its menu's “\(word)”, but nothing changed in 6 s")
        case .panel:
            // Its row says whether it's that way already, and shows the press take.
            switch panelPress(pid: pid, pausing: pausing) {
            case .already:
                already()
            case .changed:
                rememberPanelRow()
                say("\(pausing ? "Paused" : "Played") it with its row in the Now Playing panel (“\(panelRowText ?? "")”).")
                finish(0)
            case .notPressed:
                tried.append(panelProblem ?? "couldn't press its row in the Now Playing panel")
                continue
            case .pressed:
                break
            }
            if within({ isPlaying(pid) != pausing }) {
                rememberPanelRow()
                say("\(pausing ? "Paused" : "Played") it with its row in the Now Playing panel (“\(panelRowText ?? "")”).")
                finish(0)
            }
            // That row changed and this app didn't: another app's after all, put back as it was.
            let pressedRow = panelRowText ?? ""
            let putBack = pressInPanel(pid: pid, pausing: !pausing, choice: .lastOnly)
            tried.append("pressed a row in the Now Playing panel (“\(pressedRow)”), but it didn't change in 6 s"
                + (putBack ? "; that row had changed, so it was pressed again to put it back" : ""))
        }
    }
    say("Couldn't \(action.rawValue) it: " + tried.joined(separator: "; ") + ".")
    finish(1)
}
