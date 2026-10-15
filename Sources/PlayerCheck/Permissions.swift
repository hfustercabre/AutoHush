import AppKit
import CheckedPlayers
import AutoHushKit

// MARK: - Permissions, before anything a test does

/// Automation's answer for the app (`automationRefusal`), asked first in a
/// test's Permissions.
@MainActor var automationAnswer: AutomationPermission?

/// Automation for the app, asked of macOS (its prompt shows when it hasn't
/// asked yet). An app still starting doesn't answer Apple events yet (-600,
/// as one Player Check opened just before), so it's asked again for up to
/// 20 s while the app runs.
@MainActor func askAutomation(pid: pid_t) -> AutomationPermission {
    var answer = AutomationPermission(status: AutomationPermission.check(pid: pid, ask: true))
    guard answer == .notRunning else { return answer }
    say("  Automation for \(appName): \(appName) didn't answer yet (it may still be starting): asked again for up to 20 s")
    let deadline = Date().addingTimeInterval(20)
    while answer == .notRunning, Date() < deadline, running?.isTerminated == false {
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        answer = AutomationPermission(status: AutomationPermission.check(pid: pid, ask: true))
    }
    return answer
}

/// What a test needs, asked before it does anything: Accessibility (the
/// window's states, the menu, the page, the panel), Audio Recording (its
/// level, and the mute that keeps it silent meanwhile), and Automation for
/// the app when it has AppleScript play or pause. Without all of them
/// nothing more is done: no window moved, nothing pressed. Exit status 3
/// says so to whoever runs it. With --partial (AutoHush's), only
/// Accessibility is needed; with --no-taps, Audio Recording isn't used.
/// Then the app is muted until the test ends.
@MainActor func checkPermissions() {
    guard let running else { return }
    say()
    say(CheckReportLine.Heading.permissions.rawValue)
    let holder = NSRunningApplication(processIdentifier: responsible(getpid()))?.localizedName ?? "this tool"
    var missing: [String] = []
    if !AXIsProcessTrusted() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        say(CheckReportLine.waiting(.allowAccessibility, "allow Accessibility for \(holder) in System Settings; the check goes on as soon as it's allowed",
                                    minutes: 2))
        let deadline = Date().addingTimeInterval(120)
        while !AXIsProcessTrusted(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.5)) }
    }
    let trusted = AXIsProcessTrusted()
    say("  Accessibility: " + (trusted ? "allowed" : "not allowed"))
    if !trusted { missing.append("Accessibility") }
    setUpLevels(asking: true, saying: false)
    if noTaps {
        say("  Audio Recording: not used (AntiDot mode, no audio taps): \(appName) isn't muted, and whether it plays is told by other signs")
    } else {
        say("  Audio Recording: " + (levelsAllowed ? "allowed" : "not allowed"))
        if !levelsAllowed { missing.append("Audio Recording") }
    }
    var unanswered = false
    if scriptControls() != nil {
        let answer = askAutomation(pid: running.processIdentifier)
        if answer == .allowed || answer == .denied { automationAnswer = answer }
        switch answer {
        case .allowed: say("  Automation for \(appName): allowed")
        case .denied: say("  Automation for \(appName): not allowed")
        case .notAsked: say("  Automation for \(appName): not answered")
        case .notRunning:
            say("  Automation for \(appName): no answer from \(appName)")
            unanswered = true
        }
        if answer == .denied || answer == .notAsked { missing.append("Automation for \(appName)") }
    }
    // --partial: only Accessibility is needed; without the others, the
    // check goes on with less (`partial`).
    if partial, trusted, !missing.isEmpty || unanswered {
        if !levelsAllowed { say("  without Audio Recording: \(appName) isn't muted, and whether it plays is told by other signs") }
        if unanswered || missing.contains(where: { $0.hasPrefix("Automation") }) {
            scriptProblem = "Automation for \(appName) isn't allowed, so its AppleScript isn't tried"
            say("  without Automation: \(appName)'s AppleScript isn't tried")
        }
        missing = []
        unanswered = false
    }
    if !missing.isEmpty {
        let list = missing.count > 1 ? missing.dropLast().joined(separator: ", ") + " and " + missing.last! : missing[0]
        say()
        say("Not checked: \(holder) needs \(list). Allow \(missing.count > 1 ? "them" : "it") in System Settings → Privacy & Security,"
            + " then check again.")
        exit(3)
    }
    if unanswered {
        // Not a permission refused: the app doesn't answer, so whether it's
        // allowed can't be known yet.
        say()
        say("Not checked: \(appName) didn't answer whether \(holder) may control it by AppleScript (it may still be starting,"
            + " or it's busy): check again in a moment.")
        exit(3)
    }
    guard levelsAllowed else { return } // nothing to mute it with
    // A browser's web app plays through its browser: the whole browser is
    // muted (its tabs and other web apps too): its own sound can't be told apart.
    let mute = TestMute(pid: soundOwner(running.processIdentifier))
    testMute = mute
    let muted = webAppBrowser.map { "\($0) is muted until the check ends, its tabs and other web apps too: you won't hear \(appName)" }
        ?? "\(appName) is muted until the check ends: you won't hear it, while its sound still reaches what measures it"
    say(mute.start()
        ? "  " + muted
        : "  \(webAppBrowser ?? appName) couldn't be muted yet (macOS didn't take the tap): you may hear it; it's tried again meanwhile")
}
