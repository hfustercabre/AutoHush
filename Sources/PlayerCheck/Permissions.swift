import AppKit
import CheckedPlayers
import AutoHushKit
import PlayerCheckKit

// MARK: - Permissions, before anything a test does

/// Automation's answer for the app (`automationRefusal`), asked first in a
/// test's Permissions.
@MainActor var automationAnswer: AutomationPermission?

/// Automation for the app, asked of macOS (its prompt shows when it hasn't
/// asked yet). An app still starting doesn't answer Apple events yet (-600,
/// as one Player Check opened just before), so it's asked again for up to
/// 20 s while the app runs.
@MainActor func askAutomation(pid: pid_t) -> AutomationPermission {
    let answer = AutomationPermission(status: AutomationPermission.check(pid: pid, ask: true))
    guard answer == .notRunning else { return answer }
    say(CheckReportLine.permission(.automation(app: appName), "\(appName) didn't answer yet (it may still be starting): asked again for up to 20 s"))
    return Polling.wait(seconds: 20, every: 0.5, runLoop: true, from: answer,
                        reading: { AutomationPermission(status: AutomationPermission.check(pid: pid, ask: true)) },
                        until: { $0 != .notRunning || running?.isTerminated != false })
}

/// What a test needs, asked before it does anything: Accessibility (the
/// window's states, the menu, the page, the panel), Audio Recording (its
/// level, and the mute that keeps it silent meanwhile), and Automation for
/// the app when it has AppleScript play or pause. Without all of them
/// nothing more is done: no window moved, nothing pressed. Its exit status
/// says so to whoever runs it (`CheckExitStatus.permissionMissing`). With --partial (AutoHush's), only
/// Accessibility is needed; with --no-taps, Audio Recording isn't used.
/// Then the app is muted until the test ends.
@MainActor func checkPermissions() {
    guard let running else { return }
    say()
    say(CheckReportLine.Heading.permissions.rawValue)
    let holder = NSRunningApplication(processIdentifier: responsible(getpid()))?.localizedName ?? "this tool"
    var missing: [CheckReportLine.Permission] = []
    if !AXIsProcessTrusted() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        say(CheckReportLine.waitingForAccessibility(holder, minutes: 2))
        Polling.wait(seconds: 120, every: 0.5, runLoop: true, until: AXIsProcessTrusted)
    }
    let trusted = AXIsProcessTrusted()
    say(CheckReportLine.permission(.accessibility, trusted ? .allowed : .notAllowed))
    if !trusted { missing.append(.accessibility) }
    setUpLevels(asking: true, saying: false)
    if noTaps {
        say(CheckReportLine.permission(.audioRecording,
                                       "not used (AntiDot mode, no audio taps): \(appName) isn't muted, and whether it plays is told by other signs"))
    } else {
        say(CheckReportLine.permission(.audioRecording, levelsAllowed ? .allowed : .notAllowed))
        if !levelsAllowed { missing.append(.audioRecording) }
    }
    var unanswered = false
    if scriptControls() != nil {
        let answer = askAutomation(pid: running.processIdentifier)
        if answer == .allowed || answer == .denied { automationAnswer = answer }
        let automation = CheckReportLine.Permission.automation(app: appName)
        switch answer {
        case .allowed: say(CheckReportLine.permission(automation, .allowed))
        case .denied: say(CheckReportLine.permission(automation, .notAllowed))
        case .notAsked: say(CheckReportLine.permission(automation, .notAnswered))
        case .notRunning:
            say(CheckReportLine.permission(automation, "no answer from \(appName)"))
            unanswered = true
        }
        if answer == .denied || answer == .notAsked { missing.append(automation) }
    }
    // --partial: only Accessibility is needed; without the others, the
    // check goes on with less (`partial`).
    if partial, trusted, !missing.isEmpty || unanswered {
        if !levelsAllowed { say("  without Audio Recording: \(appName) isn't muted, and whether it plays is told by other signs") }
        if unanswered || missing.contains(where: { if case .automation = $0 { true } else { false } }) {
            scriptProblem = "Automation for \(appName) isn't allowed, so its AppleScript isn't tried"
            say("  without Automation: \(appName)'s AppleScript isn't tried")
        }
        missing = []
        unanswered = false
    }
    if !missing.isEmpty {
        let names = missing.map(\.name)
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : names[0]
        say()
        say(CheckReportLine.notChecked("\(holder) needs \(list). Allow \(names.count > 1 ? "them" : "it") in System Settings → Privacy & Security,"
            + " then check again."))
        exit(CheckExitStatus.permissionMissing)
    }
    if unanswered {
        // Not a permission refused: the app doesn't answer, so whether it's
        // allowed can't be known yet.
        say()
        say(CheckReportLine.notChecked("\(appName) didn't answer whether \(holder) may control it by AppleScript (it may still be starting,"
            + " or it's busy): check again in a moment."))
        exit(CheckExitStatus.permissionMissing)
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
