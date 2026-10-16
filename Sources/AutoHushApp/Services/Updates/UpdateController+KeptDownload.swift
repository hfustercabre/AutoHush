import AppKit
import AutoHushKit

// UpdateController: the kept download.
extension UpdateController {
    /// Deletes a kept download that's no longer wanted (see
    /// `UpdateDownloads.tidy`). Downloads are kept only while automatic checks
    /// are on and the choice isn't "Notify me".
    func tidy() {
        guard !isDownloading else { return }
        let keeping = checksAutomatically && mode != .notify && installUnavailability == nil
        let hadDownload = preferences.downloadedUpdate
        downloads.tidy(running: currentVersion, latest: latestVersion, keeping: keeping, now: now())
        if let hadDownload, preferences.downloadedUpdate == nil {
            let why = preferences.expiredUpdateVersion == hadDownload.version ? "it expired after 7 days" : "it's no longer needed"
            logger.info("Removed the kept download of \(hadDownload.version, privacy: .public): \(why, privacy: .public)")
        }
        if let expired = preferences.expiredUpdateVersion.flatMap(AppVersion.init), let currentVersion,
           expired <= currentVersion {
            preferences.expiredUpdateVersion = nil
        }
        if hadDownload != nil, preferences.downloadedUpdate == nil {
            withdrawOffer()
            reportOffer()
        }
    }
}
