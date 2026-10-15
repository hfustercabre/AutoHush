import AppKit
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
        logger.info("Downloading \(version, privacy: .public)")
        onStatus(String(localized: "Downloading version \(version)…",
                        comment: "Update status in Settings; %@ is a version number"))
        do {
            try await downloads.store(release, at: now(), allowsConstrainedNetwork: false)
            logger.info("Downloaded \(version, privacy: .public), kept for 7 days")
            preferences.expiredUpdateVersion = nil
            reportOffer()
            onStatus(availableStatus(release))
            announce(.downloaded(release.version))
        } catch {
            logger.error("Downloading \(version, privacy: .public) failed: \(error)")
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
        let image = downloads.image(for: release)
        logger.info("Installing \(version, privacy: .public) (\(userInitiated ? "asked for" : "automatic", privacy: .public), \(image == nil ? "downloading it" : "from the kept download", privacy: .public))")
        onStatus(String(localized: "Installing version \(version)…",
                        comment: "Update status in Settings; %@ is a version number"))
        do {
            // Automatic installs, like automatic downloads, wait out Low Data Mode.
            let update = try await installer.prepare(release, image: image, allowsConstrainedNetwork: userInitiated)
            guard userInitiated || isQuietMoment() else {
                logger.info("AutoHush got busy while \(version, privacy: .public) was prepared: it installs at the next quiet moment")
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
            logger.error("Installing \(version, privacy: .public) failed: \(error)")
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
