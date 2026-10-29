import AppKit
import AutoHushKit

// UpdateController: the user's settings.
extension UpdateController {
    /// Checks by itself once a day, or not, as the user chose in Settings;
    /// turned on, it checks at once if a check is due.
    func setChecksAutomatically(_ enabled: Bool) {
        if enabled != checksAutomatically {
            AutoHushLogger.settings.info("Check for updates automatically: \(enabled ? "on" : "off", privacy: .public)")
        }
        checksAutomatically = enabled
        if enabled { Task { await runAutomaticTasks() } }
    }

    /// Looks for release candidates too, or not, and checks again at once
    /// while checks are automatic: on, a candidate may be offered; off while
    /// one runs, the latest release is (`UpdateChecker.check`).
    func setGetsReleaseCandidates(_ enabled: Bool) {
        guard enabled != getsReleaseCandidates else { return }
        AutoHushLogger.settings.info("Get release candidates: \(enabled ? "on" : "off", privacy: .public)")
        getsReleaseCandidates = enabled
        guard checksAutomatically else { return }
        Task {
            await check(userInitiated: false)
            await runAutomaticTasks()
        }
    }

    /// Stores what automatic checks lead to, and acts on an update already
    /// found the new way (e.g. downloads it). A choice that notifies asks for
    /// permission to, if the user hasn't answered yet.
    func setMode(_ newMode: AutomaticUpdates) {
        if newMode != mode {
            AutoHushLogger.settings.info("When an update is found: \(mode.rawValue, privacy: .public) → \(newMode.rawValue, privacy: .public)")
        }
        mode = newMode
        if newMode != .install { notifier.requestPermission() }
        Task { await runAutomaticTasks() }
    }
}
