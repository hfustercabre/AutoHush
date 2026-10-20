import AppKit
import CheckedPlayers
import PlayerCheckKit
import ScriptablePlayers
import WebAppPlayers

// MARK: - Ways to control it

/// One line per way known to control an app, each with a mark
/// (`CheckReportLine.WayMark`): ✓ it paused and played again in the test, in
/// every window state tested; ⚠ in some (the states where it didn't, and
/// why, on the lines under it); ✗ in none, or not there; ? found but not
/// tried (read only, or it didn't play); – not checked. The Player Check app
/// shows this section as a checklist (`CheckReportLine.way(in:)`).
@MainActor func way(_ mark: CheckReportLine.WayMark, _ text: String) { say(CheckReportLine.way(mark, text)) }

/// A way's title (`CheckReportLine.wayTitle`).
func wayTitle(_ key: Way) -> String { CheckReportLine.wayTitle(key) }

/// A way's results in the window states, when the test went through them:
/// its mark, what its line adds, and a line per state it failed in (only
/// for ⚠: a ✗ failed in all) or that wasn't tested.
@MainActor func stateSummary(_ key: Way) -> (mark: CheckReportLine.WayMark, suffix: String, lines: [String])? {
    guard let windowTest, let results = stateResults[key], !results.isEmpty else { return nil }
    let passed = results.filter { $0.result == .worked }.count
    let mark: CheckReportLine.WayMark = passed == results.count ? .works : passed == 0 ? .none : .some
    let all = WindowState.allCases.count
    let suffix = passed == results.count
        ? " (" + (passed == all ? "all \(all) window states" : passed == 1 ? "the one window state tested" : "the \(passed) window states tested") + ")"
        : passed == 0 ? " (in every window state tested)" : ", in \(passed) of \(results.count) window states"
    var lines = mark == .some ? results.filter { $0.result != .worked }.map { CheckReportLine.wayState(.none, $0.state.title, $0.why) } : []
    for state in WindowState.allCases where !results.contains(where: { $0.state == state }) {
        let why = untestedStates[key]?[state] ?? windowTest.untested[state] ?? notTried.replacingOccurrences(of: "not tried: ", with: "")
        lines.append(CheckReportLine.wayState(.notChecked, state.title, "not tested (\(why))"))
    }
    return (mark, suffix, lines)
}

/// A tried way's line: ✓, ⚠ or ✗ over the window states tested (✓ or ✗ by
/// its only run when there were none), `worked` or `failed` saying how it went.
@MainActor func triedWay(_ key: Way, _ title: String, _ result: TrialResult, worked: String, failed: String) {
    if let summary = stateSummary(key) {
        way(summary.mark, "\(title): " + (summary.mark == .none ? failed : worked) + summary.suffix)
        summary.lines.forEach { say($0) }
    } else {
        way(result == .worked ? .works : .none, "\(title): " + (result == .worked ? worked : failed))
        if let windowStatesNote { say(CheckReportLine.wayState(.notChecked, "window states", "not tested (\(windowStatesNote))")) }
    }
}

/// A trial's line: ✓ paused and played again, ✗ it only paused or didn't.
@MainActor func resultLine(_ key: Way, _ title: String, _ result: TrialResult, problem: String? = nil) {
    triedWay(key, title, result, worked: "pressing it paused and played it",
             failed: problem ?? (result == .pausedOnly ? "it paused, but didn't play again" : "pressing it changed nothing"))
}

@MainActor func reportWays() {
    say()
    say(CheckReportLine.Heading.ways.rawValue)
    if let script = scriptControls() {
        let fits = scripting?.fitsScriptablePlayer == true
        let kind = fits ? ", as the supported scriptable players do"
            : " (\(scripting?.playsDocuments == true ? "on its documents, " : "")in a way of its own, unlike the supported scriptable players)"
        if let result = firstResults[.script] {
            triedWay(.script, wayTitle(.script), result, worked: "“\(script.pause.name)” and “\(script.play.name)” paused and played it\(kind)",
                     failed: result == .pausedOnly ? "“\(script.pause.name)” paused it, but “\(script.play.name)” didn't play it again"
                                                   : scriptProblem ?? "“\(script.pause.name)” didn't pause it")
        } else if let scriptProblem {
            way(.none, "\(wayTitle(.script)): \(scriptProblem)")
        } else if fits {
            way(.notTried, "\(wayTitle(.script)): pause, play and its state, as the supported scriptable players have them (\(notTried))")
        } else {
            // The Player Check app offers no AppleScript Play or Pause for
            // this line until a check tried it: it looks for these words.
            way(.notTried, "\(wayTitle(.script)): play or pause commands, but \(CheckReportLine.unlikeScriptablePlayers) have them (\(notTried))")
        }
    } else {
        way(.none, "\(wayTitle(.script)): " + (scripting == nil ? "no scripting dictionary" : "a dictionary without play or pause"))
    }
    if running == nil {
        way(.notChecked, "\(wayTitle(.menu)): not checked (it isn't running)")
    } else if !AXIsProcessTrusted() {
        way(.notChecked, "\(wayTitle(.menu)): not checked (no Accessibility permission)")
    } else if let menu {
        let found = "\(wayTitle(.menu)) “\(menu.title)”" + (menu.arrows == "⌘← ⌘→" ? "" : " (found by its first item on Space, its arrows \(menu.arrows))")
        if let result = firstResults[.menu] {
            resultLine(.menu, found, result)
        } else {
            way(.notTried, "\(found): first item \(shown(menu.toggleTitle)) (\(notTried))")
        }
    } else {
        way(.none, "\(wayTitle(.menu)): none with Play/Pause and Previous/Next")
    }
    if let pageNotChecked {
        way(.notChecked, "\(wayTitle(.page)): not checked (\(pageNotChecked))")
    } else if let page {
        let kind = pageSwitch.map { "\(wayTitle(.page)), with \(switchName($0)) on" } ?? wayTitle(.page)
        if let toggle = page.toggle {
            let found = "\(kind): " + (learned.map { "\(shown($0.recipe.pauseLabel)) / \(shown($0.recipe.playLabel)), learned as AutoHush learns it" }
                                       ?? shown(toggle.label) + (page.withControls ? "" : ", but no player bar around it"))
            if let result = firstResults[.page] {
                resultLine(.page, found, result)
            } else {
                way(.notTried, "\(found) (\(notTried))")
            }
        } else {
            way(.none, "\(kind): " + (page.buttons == 0 ? "no page showed" : "none in sight named Play or Pause"))
        }
    }
    if let result = firstResults[.panel], canBeNowPlaying {
        triedWay(.panel, wayTitle(.panel), result, worked: "pressing its row (\(panelRowSaid ?? "the row")) paused and played it",
                 failed: panelProblem ?? (result == .pausedOnly ? "it paused, but didn't play again" : "pressing its row changed nothing"))
    } else if running == nil {
        way(.notChecked, "\(wayTitle(.panel)): not checked (it isn't running)")
    } else if !canBeNowPlaying {
        way(.none, "\(wayTitle(.panel)): \(panelNotNowPlaying)")
    } else if !AXIsProcessTrusted() {
        way(.notChecked, "\(wayTitle(.panel)): not checked (no Accessibility permission)")
    } else {
        way(.notTried, "\(wayTitle(.panel)): its rows in the menu bar's panel play and pause the apps listed there (\(notTried))")
    }
}

// MARK: - Verdict

@MainActor func reportVerdict() {
    say()
    say(CheckReportLine.Heading.verdict.rawValue)
    var facts = PlayerKindVerdict.Facts(bundleID: bundleID)
    facts.isSafariWebApp = isWebApp
    facts.webAppBrowser = webAppBrowser
    facts.scripting = scripting
    let stateNotes = notifications?.seen.filter { $0.value.contains("Player State") }.keys.sorted() ?? []
    facts.stateNotification = announcingNotification.map { .announced($0) }
        ?? (!stateNotes.isEmpty ? .seen(stateNotes) : notifications == nil ? .notFollowed : .noneSeen)
    facts.scriptResult = firstResults[.script]
    facts.menuResult = firstResults[.menu]
    facts.menuTitle = menu?.title
    facts.isRunning = running != nil
    facts.pageHasPlayPause = page?.toggle != nil
    PlayerKindVerdict.lines(facts, developer: developer).forEach { say($0) }

    // What the page showed: Add an App adds an app whose page's Play/Pause
    // works, pressed there (`PlayerSetup.Way.page`) as a Safari web app's is.
    guard let page else { return }
    let pageWord = isFlutter ? "interface" : "page"
    let its = pageSwitch.map { "With \(switchName($0)) on, its \(pageWord)" } ?? "Its \(pageWord)"
    if page.buttons == 0 {
        say(hiddenInterface != nil ? "  No switch showed its \(pageWord): its buttons can't be read that way."
                                   : "  Its page showed no buttons: is the site loaded?")
    } else if let toggle = page.toggle {
        switch firstResults[.page] {
        case .worked?:
            if isWebApp {
                say("  Its page's Play/Pause works.")
            } else {
                say("  \(its)'s Play/Pause works: Add an App can make it a player pressed there,")
                say("  as Safari web apps are, with no fades.")
            }
        case .pausedOnly?:
            say("  \(its)'s Pause works, but its Play didn't bring it back: check by ear.")
        case .didNotPause?:
            say("  \(its) has Play/Pause (\(shown(toggle.label))), but pressing it didn't take: check by ear.")
        case nil:
            say("  \(its) has Play/Pause (\(shown(toggle.label))): confirm by testing it while it plays.")
        }
        if let results = stateResults[.page], let summary = stateSummary(.page), summary.mark == .some {
            let worked = results.filter { $0.result == .worked }.map(\.state.title)
            let failed = results.filter { $0.result != .worked }.map(\.state.title)
            say("  It works with its window " + worked.joined(separator: ", ") + "; not " + failed.joined(separator: ", ") + ".")
            if let browser = webAppBrowser,
               results.contains(where: { $0.result != .worked && [WindowState.minimized, .hidden].contains($0.state) }) {
                say("  \(browser) makes a page pressable only while its window can be seen, and this tool turns its switch on for")
                say("  each press: minimized or hidden, that fails. Turned on while the window was in view and kept on (as a player")
                say("  could keep it), presses take minimized too (a Chrome web app's did).")
            }
            if launchedWithOption == false, results.contains(where: { $0.result != .worked && WindowState.outOfView.contains($0.state) }) {
                say("  Opened with \(LaunchOption.occludedWindows), Chromium keeps its page taking presses while its window is covered")
                say("  or on another desktop: relaunch it with that option (Add an App's Reopen, or the Player Check app's Relaunch)")
                say("  and check again.")
            }
        }
        if !page.withControls {
            say("  But no player's slider is around it: likely a song's own button, not a player bar (is a song loaded,")
            say("  is someone signed in?). Run it again with a song playing.")
        }
    } else {
        say("  \(its) shows \(page.buttons) \(isFlutter ? "pressable items" : "buttons"), but none in sight is named Play or Pause:")
        say("  see them with Accessibility Inspector (in Xcode: Open Developer Tool; its language may not be one this tool")
        say("  knows, its player may be hidden, or its buttons may have no names).")
    }
}

/// The switches this tool turned on, set back as they were.
@MainActor func reportSwitchesBack() {
    let turnedOn = changes.switchesOn
    guard !turnedOn.isEmpty else { return }
    let stuck = switchesBackOff()
    say()
    for attribute in turnedOn {
        say(stuck.contains(attribute) ? "(Couldn't set \(switchName(attribute)) back to off.)"
                                      : "(\(switchName(attribute)) set back to off, as it was.)")
    }
}
