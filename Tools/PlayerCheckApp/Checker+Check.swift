import AppKit
import AutoHushKit
import CheckPanel
import PlayerCheckKit
import SwiftUI

/// Checking an app: opening it, asking for Accessibility, running playercheck, stopping it.
extension Checker {
    /// Asks macOS for the Accessibility permission: its own request, which
    /// leads to System Settings (the same as AutoHush's).
    nonisolated static func askForAccessibility() {
        _ = AccessibilityPermission.isTrusted(prompt: true)
    }

    /// Opens the app when it isn't running (and gives it time to load its
    /// window and page), then runs playercheck on it. Without the
    /// Accessibility permission, which its menu, page and panel ways need,
    /// macOS is asked for it first, and the check starts once it's allowed
    /// (Stop ends the wait).
    func check(_ app: InstalledApp) {
        guard !isBusy, let tool else { return }
        let token = UUID()
        attempt = token
        checkingID = app.id
        attemptNotes[app.id] = nil
        permissionProblems[app.id] = nil
        refreshRunning()
        let allowing = !isTrusted
        reports[app.id] = CheckReport(state: allowing ? .allowing : isRunning(app) ? .checking : .opening)
        panel.show { resized, dimmed in
            PlayerCheckPanelView(app: app, checker: self, resized: resized, dimmed: dimmed)
        }
        Task {
            if allowing {
                Self.askForAccessibility()
                while !AXIsProcessTrusted() {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard attempt == token else { return } // stopped
                }
                refreshRunning()
            }
            let opening = !isRunning(app)
            reports[app.id]?.state = opening ? .opening : .checking
            if opening {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                // An Electron app opens with the option its page needs to take
                // presses out of view.
                if app.isElectron {
                    let (_, said) = await Self.runAndWait(tool, CommandLineOptions.AppQuery.launchOption.arguments(app.url.path))
                    if let option = LaunchOptionAnswer(line: said)?.option { configuration.arguments = [option] }
                }
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    guard attempt == token else { return }
                    reports[app.id]?.state = .failed("Couldn't open it: \(error.localizedDescription)")
                    endAttempt(app.id)
                    return
                }
                // Stopped meanwhile (and maybe another check started since).
                guard attempt == token else { return }
                reports[app.id]?.state = .checking
                refreshRunning()
                readLaunchOption(app)
            }
            await run(tool, on: app)
        }
    }

    /// The end of a check: a finished one is kept (and saved); one stopped or
    /// failed gives way to the last finished check, if there's one, with a note.
    private func endAttempt(_ id: InstalledApp.ID) {
        if let report = reports[id], report.state == .finished {
            finished[id] = report
            saveReports()
        } else if let report = reports[id], let previous = finished[id] {
            switch report.state {
            case .stopped: attemptNotes[id] = "The check was stopped: the last finished check is shown."
            case .failed where permissionProblems[id] != nil:
                // Its warning says why, above the last finished check.
                break
            case .failed(let reason):
                // macOS's messages end with a full stop already.
                attemptNotes[id] = (reason.hasSuffix(".") ? String(reason.dropLast()) : reason) + ". The last finished check is shown."
            default: break
            }
            reports[id] = previous
        }
        process = nil
        attempt = nil
        checkingID = nil
        panel.hide()
    }

    private func run(_ tool: URL, on app: InstalledApp) async {
        let run: LineRun
        do {
            // --developer: the verdict also says how a built-in player of
            // its kind would be made, as AutoHush's Add an App… doesn't ask.
            run = try LineRun(tool, CommandLineOptions.check(app.url.path, developer: true))
        } catch {
            reports[app.id]?.state = .failed("Couldn't run playercheck: \(error.localizedDescription)")
            endAttempt(app.id)
            return
        }
        self.process = run.running
        let id = app.id
        for await line in run.lines where !line.isEmpty {
            reports[id]?.add(line)
        }
        let status = await run.status()
        if reports[id]?.state == .checking {
            if status == CheckExitStatus.permissionMissing {
                // Cancelled before doing anything: a permission it needs isn't
                // allowed (or not answered), or the app didn't answer whether
                // it is (no permission to show in System Settings).
                let lines = reports[id]?.lines ?? []
                let said = lines.lazy.compactMap { CheckReportLine.notChecked(in: $0) }.last
                    ?? "A permission the check needs isn't allowed."
                permissionProblems[id] = (said, lines.lazy.compactMap { CheckReportLine.missingPermission(in: $0) }.first)
                reports[id]?.state = .failed("The check was cancelled: \(said)")
            } else {
                // Stopped by Escape too, while it blocked the mouse and keyboard.
                reports[id]?.state = status == CheckExitStatus.done ? .finished : CheckExitStatus.isStop(status) ? .stopped
                    : .failed("playercheck ended with status \(status)")
            }
        }
        endAttempt(id)
        refreshRunning()
        readClients()
    }

    /// Stops the check: playercheck plays the app again if a test paused it,
    /// and turns the accessibility switches it turned on back off, first.
    func stop() {
        guard let id = checkingID else { return }
        reports[id]?.state = .stopped
        if let process {
            process.stop()
        } else {
            endAttempt(id) // still opening the app
        }
    }
}
