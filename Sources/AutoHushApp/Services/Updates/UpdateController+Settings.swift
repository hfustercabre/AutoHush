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

    /// Looks for release candidates too, or not. On, it checks again at once
    /// while checks are automatic: a candidate may be offered; the latest
    /// release offered back from one is withdrawn at once (the 1.2.9 review).
    /// Off, a candidate offered is withdrawn at once (B1, the user, 2026-10-30);
    /// with no check, but while one runs: then the latest release is offered
    /// at once, as Settings says (D2, the user, 2026-10-30). Either way, a
    /// check under way asks again as the switch is now (`runCheck`).
    func setGetsReleaseCandidates(_ enabled: Bool) {
        guard enabled != getsReleaseCandidates else { return }
        AutoHushLogger.settings.info("Get release candidates: \(enabled ? "on" : "off", privacy: .public)")
        getsReleaseCandidates = enabled
        withdrawUnwantedOffer()
        guard checksAutomatically, enabled || currentVersion?.isReleaseCandidate == true else { return }
        Task {
            await check(userInitiated: false)
            await runAutomaticTasks()
        }
    }

    /// The offer the switch no longer wants, if any, is no longer: off, a
    /// release candidate; on, a release older than the one running (offered
    /// back from a candidate while it was off). The menu, Settings and its
    /// notification stop offering it, and Settings says when the last check
    /// was. Its notice is forgotten too, so offered again it's announced
    /// again. One being installed goes on.
    private func withdrawUnwantedOffer() {
        guard let offered = availableUpdate, !isInstalling else { return }
        let unwanted = getsReleaseCandidates
            ? currentVersion.map { offered.version < $0 } ?? false
            : offered.version.isReleaseCandidate
        guard unwanted else { return }
        logger.info("Release candidates \(self.getsReleaseCandidates ? "on" : "off", privacy: .public): \(offered.version.description, privacy: .public) is no longer offered")
        availableUpdate = nil
        withdrawOffer()
        if preferences.lastUpdateNotice?.hasSuffix(" \(offered.version)") == true { preferences.lastUpdateNotice = nil }
        showStatus(nil)
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
