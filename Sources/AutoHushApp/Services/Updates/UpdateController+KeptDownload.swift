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
        let hadDownload = preferences.downloadedUpdate != nil
        downloads.tidy(running: currentVersion, latest: latestVersion, keeping: keeping, now: now())
        if let expired = preferences.expiredUpdateVersion.flatMap(AppVersion.init), let currentVersion,
           expired <= currentVersion {
            preferences.expiredUpdateVersion = nil
        }
        if hadDownload, preferences.downloadedUpdate == nil {
            withdrawOffer()
            reportOffer()
        }
    }
}
