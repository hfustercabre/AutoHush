import AppKit

// MARK: - Ways to control it

/// One line per way known to control an app, each with a mark: ✓ it paused
/// and played again in the test, in every window state tested; ⚠ in some
/// (the states where it didn't, and why, on the lines under it); ✗ in none,
/// or not there; ? found but not tried (read only, or it didn't play); –
/// not checked. The Player Check app shows this section as a checklist.
@MainActor func way(_ mark: String, _ text: String) { say("  \(mark) \(text)") }

/// A way's results in the window states, when the test went through them:
/// its mark, what its line adds, and a line per state it failed in (only
/// for ⚠: a ✗ failed in all) or that wasn't tested.
@MainActor func stateSummary(_ key: Way) -> (mark: String, suffix: String, lines: [String])? {
    guard let windowTest, let results = stateResults[key], !results.isEmpty else { return nil }
    let passed = results.filter { $0.result == .worked }.count
    let mark = passed == results.count ? "✓" : passed == 0 ? "✗" : "⚠"
    let all = WindowState.allCases.count
    let suffix = passed == results.count
        ? " (" + (passed == all ? "all \(all) window states" : passed == 1 ? "the one window state tested" : "the \(passed) window states tested") + ")"
        : passed == 0 ? " (in every window state tested)" : ", in \(passed) of \(results.count) window states"
    var lines = mark == "⚠" ? results.filter { $0.result != .worked }.map { "      ✗ \($0.state.title): \($0.why)" } : []
    for state in WindowState.allCases where !results.contains(where: { $0.state == state }) {
        lines.append("      – \(state.title): not tested (\(windowTest.untested[state] ?? notTried.replacingOccurrences(of: "not tried: ", with: "")))")
    }
    return (mark, suffix, lines)
}

/// A tried way's line: ✓, ⚠ or ✗ over the window states tested (✓ or ✗ by
/// its only run when there were none), `worked` or `failed` saying how it went.
@MainActor func triedWay(_ key: Way, _ title: String, _ result: TrialResult, worked: String, failed: String) {
    if let summary = stateSummary(key) {
        way(summary.mark, "\(title): " + (summary.mark == "✗" ? failed : worked) + summary.suffix)
        summary.lines.forEach { say($0) }
    } else {
        way(result == .worked ? "✓" : "✗", "\(title): " + (result == .worked ? worked : failed))
        if let windowStatesNote { say("      – window states: not tested (\(windowStatesNote))") }
    }
}

/// A trial's line: ✓ paused and played again, ✗ it only paused or didn't.
@MainActor func resultLine(_ key: Way, _ title: String, _ result: TrialResult, problem: String? = nil) {
    triedWay(key, title, result, worked: "pressing it paused and played it",
             failed: problem ?? (result == .pausedOnly ? "it paused, but didn't play again" : "pressing it changed nothing"))
}

@MainActor func reportWays() {
    say()
    say("Ways to Control It")
    if let script = scriptControls() {
        let fits = scripting?.fitsScriptablePlayer == true
        let kind = fits ? ", as Spotify and Apple Music"
            : " (\(scripting?.playsDocuments == true ? "on its documents, " : "")its own kind, as VLC: not the way ScriptablePlayers expects)"
        if let result = firstResults[.script] {
            triedWay(.script, "AppleScript", result, worked: "“\(script.pause)” and “\(script.play)” paused and played it\(kind)",
                     failed: result == .pausedOnly ? "“\(script.pause)” paused it, but “\(script.play)” didn't play it again"
                                                   : scriptProblem ?? "“\(script.pause)” didn't pause it")
        } else if let scriptProblem {
            way("✗", "AppleScript: \(scriptProblem)")
        } else if fits {
            way("?", "AppleScript: pause, play and its state, as Spotify and Apple Music (\(notTried))")
        } else {
            way("?", "AppleScript: play or pause commands, but not as Spotify's (a player type of its own, as VLC) (\(notTried))")
        }
    } else {
        way("✗", "AppleScript: " + (scripting == nil ? "no scripting dictionary" : "a dictionary without play or pause"))
    }
    if running == nil {
        way("–", "Playback menu: not checked (it isn't running)")
    } else if !AXIsProcessTrusted() {
        way("–", "Playback menu: not checked (no Accessibility permission)")
    } else if let menu {
        let found = "Playback menu “\(menu.title)”" + (menu.asAutoHushFindsIt ? "" : " (found by \(menu.arrows), not ⌘← ⌘→)")
        if let result = firstResults[.menu] {
            resultLine(.menu, found, result)
        } else {
            way("?", "\(found): first item “\(menu.toggleTitle)” (\(notTried))")
        }
    } else {
        way("✗", "Playback menu: none with Play/Pause and Previous/Next")
    }
    if let pageNotChecked {
        way("–", "Page button: not checked (\(pageNotChecked))")
    } else if let page {
        let kind = pageSwitch.map { "Page button, with \(switchName($0)) on" } ?? "Page button"
        if let toggle = page.toggle {
            let found = "\(kind): " + (learned.map { "“\($0.recipe.pauseLabel)” / “\($0.recipe.playLabel)”, learned as AutoHush learns it" }
                                       ?? "“\(toggle.label)”" + (page.withControls ? "" : ", but no player bar around it"))
            if let result = firstResults[.page] {
                resultLine(.page, found, result)
            } else {
                way("?", "\(found) (\(notTried))")
            }
        } else {
            way("✗", "\(kind): " + (page.buttons == 0 ? "no page showed" : "none in sight named Play or Pause"))
        }
    }
    if let result = firstResults[.panel], canBeNowPlaying {
        triedWay(.panel, "Now Playing panel", result, worked: "pressing its row (“\(panelRowText ?? "")”) paused and played it",
                 failed: panelProblem ?? (result == .pausedOnly ? "it paused, but didn't play again" : "pressing its row changed nothing"))
    } else if running == nil {
        way("–", "Now Playing panel: not checked (it isn't running)")
    } else if !canBeNowPlaying {
        way("✗", "Now Playing panel: \(panelNotNowPlaying)")
    } else if !AXIsProcessTrusted() {
        way("–", "Now Playing panel: not checked (no Accessibility permission)")
    } else {
        way("?", "Now Playing panel: its rows in the menu bar's panel play and pause the apps listed there (\(notTried))")
    }
}

// MARK: - Verdict

@MainActor func reportVerdict() {
    say()
    say("Verdict")
    if isWebApp {
        say("  A Safari web app: AutoHush learns its page's Play/Pause button (WebAppPlayers).")
        say("  Test the site live, then add it to SupportedPlayers.testedWebApps.")
    } else if let scripting, scripting.fitsScriptablePlayer, let suite = scripting.suite {
        say("  Scriptable, like Spotify and Apple Music: a ScriptablePlayerProfile with suite fourCharCode(\"\(suite)\").")
        say("  " + (scripting.hasVolume ? "It has a volume: measure its curve (swift run measure-volume-curve \(bundleID))."
                                         : "No volume: it pauses without fading."))
        let stateNotes = notifications?.seen.filter { $0.value.contains("Player State") }.keys.sorted() ?? []
        if let announcingNotification {
            say("  State notification: \(announcingNotification), which announced each pause and play (the profile's stateNotification).")
        } else if !stateNotes.isEmpty {
            say("  State notification: \(stateNotes.joined(separator: ", ")), but it didn't announce both a pause and a play in the test.")
        } else if notifications == nil {
            say("  Its state notification (with “Player State”) isn't known yet: check it again while it plays.")
        } else {
            say("  No state notification with “Player State” under the usual names: unless it has one under another,")
            say("  its state must be read once a second (PolledStateObserver), so the profile needs that option.")
        }
        switch firstResults[.script] {
        case .didNotPause?: say("  But its scripted pause didn't take: check it by hand before building on it.")
        case .pausedOnly?: say("  But its scripted play didn't bring it back: check it by hand before building on it.")
        default: break
        }
    } else if let menu {
        switch firstResults[.menu] {
        case .worked?:
            say("  A menu player, like TIDAL and Apple Podcasts: a MenuPlayerProfile with menu “\(menu.title)”.")
            say("  Its words for Play and Pause in every language must be read from the app (TidalWords, PodcastsWords).")
            if !menu.asAutoHushFindsIt { say("  And AutoHush must find the menu by \(menu.arrows) as well as ⌘← ⌘→.") }
        case .pausedOnly?:
            say("  Its menu paused it, but pressing it again didn't play it: check it by hand before building on it.")
        case .didNotPause?:
            say("  Its menu has Play/Pause, but pressing it didn't take (as Deezer's menu): not controllable that way.")
        case nil:
            say("  Probably a menu player, like TIDAL and Apple Podcasts (menu “\(menu.title)”): confirm by testing it while it plays.")
            if !menu.asAutoHushFindsIt { say("  AutoHush would also have to find the menu by \(menu.arrows), not only ⌘← ⌘→.") }
        }
        if let scripting, scripting.commands.values.contains(where: { ["play", "pause", "playpause"].contains($0.lowercased()) }) {
            say("  It's scriptable too, but not the way ScriptablePlayers expects (see above): maybe a player type of its own, as VLC.")
        }
    } else if let scripting, scripting.commands.values.contains(where: { ["play", "pause", "playpause"].contains($0.lowercased()) }) {
        say("  Scriptable" + (scripting.playsDocuments ? " through its documents (its play and pause act on one)" : "")
            + ", but not the way ScriptablePlayers expects: a player type of its own, as VLC (VLCSupport).")
    } else if running == nil {
        say("  No usable scripting; open it and run again to look for a playback menu and a page.")
    } else if page?.toggle != nil {
        say("  Neither scriptable nor with a playback menu.")
    } else {
        say("  Neither scriptable nor with a playback menu: AutoHush can't control it. If it has a website, try that as a Safari web app.")
    }

    // What the page showed. AutoHush has no player kind for apps' pages yet: a
    // player that learns the page's button, as WebAppPlayers does for Safari
    // web apps, would be one.
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
                say("  \(its)'s Play/Pause works: it could be a player that learns that button,")
                say("  as Safari web apps (WebAppPlayers), with no fades; AutoHush has no such player for apps yet.")
            }
        case .pausedOnly?:
            say("  \(its)'s Pause works, but its Play didn't bring it back: check by ear.")
        case .didNotPause?:
            say("  \(its) has Play/Pause (“\(toggle.label)”), but pressing it didn't take: check by ear.")
        case nil:
            say("  \(its) has Play/Pause (“\(toggle.label)”): confirm by testing it while it plays.")
        }
        if let results = stateResults[.page], let summary = stateSummary(.page), summary.mark == "⚠" {
            let worked = results.filter { $0.result == .worked }.map(\.state.title)
            let failed = results.filter { $0.result != .worked }.map(\.state.title)
            say("  It works with its window " + worked.joined(separator: ", ") + "; not " + failed.joined(separator: ", ") + ".")
            if launchedWithOption == false, results.contains(where: { $0.result != .worked && WindowState.outOfView.contains($0.state) }) {
                say("  Opened with \(LaunchOption.occludedWindows), Chromium keeps its page taking presses while its window is covered")
                say("  or on another desktop: relaunch it with it (the Player Check app's Relaunch) and check again.")
            }
        }
        if !page.withControls {
            say("  But no player's slider is around it: likely a song's own button, not a player bar (is a song loaded,")
            say("  is someone signed in?). Run it again with a song playing.")
        }
    } else {
        say("  \(its) shows \(page.buttons) \(isFlutter ? "pressable items" : "buttons"), but none in sight is named Play or Pause:")
        say("  see them with Accessibility Inspector (in Xcode: Open Developer Tool; its language may not be one this tool")
        say("  knows, its player may be hidden, or its buttons may have no names, as Spotube's player bar).")
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
