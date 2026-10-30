import AppKit
import AutoHushKit

// UpdateController: checking for an update.
extension UpdateController {
    func checkFromUser() {
        Task { await check(userInitiated: true) }
    }

    func checkNow() async {
        await check(userInitiated: true)
    }

    /// Asks GitHub for the latest release. A check asked for while one is
    /// under way (a double click, the automatic one, the menu's while
    /// Settings' runs) doesn't start another: it waits for the one under
    /// way, which shows its result if anyone asked.
    func check(userInitiated: Bool) async {
        resultWanted = resultWanted || userInitiated
        if let checking { return await checking.value }
        let task = Task {
            await runCheck()
            // As it ends, not once its caller is back: a check asked for in
            // between would join one that no longer shows its result.
            checking = nil
            resultWanted = false
        }
        checking = task
        await task.value
    }

    private func runCheck() async {
        guard let currentVersion else {
            let unknown = String(localized: "AutoHush’s version is unknown.",
                                 comment: "Update status in Settings, and the alert after a check asked for from the menu or Settings")
            logger.error("Can’t check for updates: AutoHush’s version is unknown")
            showStatus(unknown)
            if resultWanted { await presentFailure(unknown) }
            return
        }
        logger.info("Checking for updates (\(resultWanted ? "asked for" : "automatic", privacy: .public))")
        showStatus(UpdateOffer.checkingTitle)
        do {
            var asked = getsReleaseCandidates
            var result = try await checker.check(currentVersion: currentVersion, releaseCandidates: asked)
            // Release candidates turned on or off while it ran: asked again
            // as they are now, so the answer follows the switch (B1, the
            // user, 2026-10-30). Turned on, a check joined (the switch's own)
            // would otherwise find no candidate until the next due check.
            while getsReleaseCandidates != asked {
                asked = getsReleaseCandidates
                logger.info("Release candidates were turned \(asked ? "on" : "off", privacy: .public) during the check: checking again \(asked ? "with" : "without", privacy: .public) them")
                result = try await checker.check(currentVersion: currentVersion, releaseCandidates: asked)
            }
            lastCheck = now()
            switch result {
            case .available(let release):
                logger.info("Version \(release.version.description, privacy: .public) is available (running \(currentVersion.description, privacy: .public))")
            case .upToDate(let latest):
                logger.info("Up to date: \(currentVersion.description, privacy: .public) is running, \(latest.description, privacy: .public) is the latest")
            case .noReleases:
                logger.info("Up to date: no releases have been published yet")
            }
            switch result {
            case .available(let release):
                latestVersion = release.version
                availableUpdate = release
            case .upToDate(let latest):
                latestVersion = latest
                availableUpdate = nil
            case .noReleases:
                latestVersion = currentVersion
                availableUpdate = nil
            }
            if availableUpdate == nil { withdrawOffer() }
            tidy()
            switch result {
            case .available(let release):
                showStatus(availableStatus(release))
            case .upToDate:
                showStatus(String(localized: "AutoHush \(currentVersion.description) is up to date.",
                                  comment: "Update status in Settings; %@ is a version number"))
            case .noReleases:
                showStatus(String(localized: "No releases have been published yet.", comment: "Update status in Settings"))
            }
            if resultWanted {
                await beforePresenting()
                showAlert { self.present(result) }
            }
        } catch {
            logger.error("Update check failed: \(error)")
            showStatus(String(localized: "Couldn’t check for updates.", comment: "Update status in Settings"))
            if resultWanted { await presentFailure(error.localizedDescription) }
        }
    }

    /// Says why a check asked for couldn't tell, in an alert.
    private func presentFailure(_ reason: String) async {
        await beforePresenting()
        let title = String(localized: "Couldn’t Check for Updates", comment: "Alert title")
        showAlert { InfoAlert.show(title, reason, run: self.runAlert) }
    }
}
