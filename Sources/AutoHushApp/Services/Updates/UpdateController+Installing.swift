import AppKit
import OSLog
import AutoHushKit

// UpdateController: downloading and installing.
extension UpdateController {
    /// Downloads `release` and keeps it, then lets the user know. A failed
    /// download is tried again at the next automatic run.
    func download(_ release: AppRelease) async {
        guard !isDownloading else { return }
        isDownloading = true
        defer { isDownloading = false }
        let version = release.version.description
        onStatus(String(localized: "Downloading version \(version)…",
                        comment: "Update status in Settings; %@ is a version number"))
        do {
            try await downloads.store(release, at: now(), allowsConstrainedNetwork: false)
            preferences.expiredUpdateVersion = nil
            reportOffer()
            onStatus(availableStatus(release))
            announce(.downloaded(release.version))
        } catch {
            logger.error("Downloading \(version, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            onStatus(String(localized: "Couldn’t download version \(version).",
                            comment: "Update status in Settings; %@ is a version number"))
        }
    }

    /// Installs `release`, from a kept download when there's an intact one,
    /// then quits so that the new version opens. An automatic install gives
    /// up quietly when AutoHush got busy meanwhile; a failed one is reported:
    /// in an alert when the user asked for it, otherwise in a notification.
    func install(_ release: AppRelease, userInitiated: Bool) async {
        guard !isInstalling else { return }
        isInstalling = true
        let version = release.version.description
        onStatus(String(localized: "Installing version \(version)…",
                        comment: "Update status in Settings; %@ is a version number"))
        let image = downloads.image(for: release)
        do {
            // Automatic installs, like automatic downloads, wait out Low Data Mode.
            let update = try await installer.prepare(release, image: image, allowsConstrainedNetwork: userInitiated)
            guard userInitiated || isQuietMoment() else {
                installer.discard(update)
                isInstalling = false
                onStatus(availableStatus(release))
                return
            }
            try installer.install(update)
            downloads.remove()
            logger.info("Installed \(version, privacy: .public); relaunching")
            quit()
        } catch {
            // A kept download that didn't install isn't trusted again.
            if image != nil { downloads.remove() }
            isInstalling = false
            logger.error("Installing \(version, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            onStatus(String(localized: "Couldn’t install version \(version).",
                            comment: "Update status in Settings; %@ is a version number"))
            if userInitiated {
                let reason = error.localizedDescription
                showAlert { self.presentInstallError(reason, release: release) }
            } else {
                failedAutomaticInstall = release.version
                announce(.installFailed(release.version))
            }
        }
    }
}
