import AppKit
import AutoHushKit

// UpdateController: notifications.
extension UpdateController {
    /// Sends `notice`, unless it was the last one sent.
    func announce(_ notice: UpdateNotice) {
        guard preferences.lastUpdateNotice != notice.key else { return }
        preferences.lastUpdateNotice = notice.key
        notifier.announce(notice)
    }

    /// Removes a notification about an update that no longer applies: one
    /// saying it's available, downloaded or failed, never "updated to".
    func withdrawOffer() {
        guard let notice = preferences.lastUpdateNotice,
              !notice.hasPrefix(UpdateNotice.Kind.installed.rawValue + " ")
        else { return }
        notifier.withdraw()
    }

    /// Where a click on a notification leads: for "updated to", that
    /// release's page; otherwise the update's popup, as things stand now.
    func open(_ kind: UpdateNotice.Kind, version: AppVersion) {
        switch kind {
        case .installed:
            openURL(ProjectInfo.releasePage(for: version))
        case .available, .downloaded, .installFailed:
            presentAvailableUpdate()
        }
    }
}
