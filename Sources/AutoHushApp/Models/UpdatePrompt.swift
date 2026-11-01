import Foundation

/// What the update popup says about a release, and the buttons it offers:
/// which version is running, which one is available or downloaded, and
/// whether installing it downloads it first.
struct UpdatePrompt: Equatable {
    enum Choice: Equatable {
        case install, later, openReleasePage
    }

    struct Button: Equatable {
        let title: String
        let choice: Choice
    }

    let title: String
    let message: String
    /// The first is the default button.
    let buttons: [Button]

    /// `canInstall` is false where this copy can't update itself, or the
    /// release has no disk image: then it says how to update by hand.
    init(release: AppRelease, running: AppVersion, isDownloaded: Bool, canInstall: Bool, isHomebrewInstall: Bool) {
        let new = release.version.description
        let current = running.description
        let later = Button(title: LaterText.title, choice: .later)
        let openPage = Button(title: String(localized: "Open Release Page", comment: "Update alert button"),
                              choice: .openReleasePage)
        // A release candidate says so, and the latest release offered back
        // from one (Get release candidates turned off) says why (WA6, R1, the
        // user's pick, 2026-10-31), by hand too (S2, the user's pick,
        // 2026-11-01).
        let offer = Offer(current: current, new: new, isBack: release.version < running,
                          isCandidate: release.version.isReleaseCandidate)
        guard canInstall else {
            title = String(localized: "AutoHush \(new) Is Available", comment: "Alert title; %@ is the new version number")
            message = isHomebrewInstall ? offer.withHomebrew : offer.byHand
            buttons = [openPage, later]
            return
        }
        if isDownloaded {
            title = String(localized: "AutoHush \(new) Is Ready to Install",
                           comment: "Update popup title; %@ is the new version, already downloaded")
            buttons = [
                Button(title: String(localized: "Install and Relaunch", comment: "Update alert button"), choice: .install),
                later, openPage,
            ]
        } else {
            title = String(localized: "AutoHush \(new) Is Available", comment: "Alert title; %@ is the new version number")
            buttons = [
                Button(title: String(localized: "Download and Install",
                                     comment: "Update popup button: downloads the update, installs it and restarts"),
                       choice: .install),
                later, openPage,
            ]
        }
        message = offer.installing(isDownloaded: isDownloaded)
    }

    /// What's offered, said for each way it's installed.
    private struct Offer {
        let current: String
        let new: String
        /// The latest release offered back from a release candidate.
        let isBack: Bool
        let isCandidate: Bool

        func installing(isDownloaded: Bool) -> String {
            if isBack {
                return String(localized: "Version \(current) is a release candidate, and Get release candidates is off. Installing the latest release restarts AutoHush.",
                              comment: "Update popup, offering the latest release, older than the release candidate running, after Get release candidates (a setting) was turned off; %@ is the installed version")
            }
            switch (isCandidate, isDownloaded) {
            case (true, true):
                return String(localized: "You’re running version \(current), and version \(new) is downloaded. It’s a release candidate, a test version of the next release. Installing it restarts AutoHush.",
                              comment: "Update popup for a release candidate, a test version of the next release; the first %@ is the installed version, the second the downloaded one")
            case (true, false):
                return String(localized: "You’re running version \(current), and version \(new) is available. It’s a release candidate, a test version of the next release. Installing it restarts AutoHush.",
                              comment: "Update popup for a release candidate, a test version of the next release; the first %@ is the installed version, the second the new one")
            case (false, true):
                return String(localized: "You’re running version \(current), and version \(new) is downloaded. Installing it restarts AutoHush.",
                              comment: "Update popup; the first %@ is the installed version, the second the downloaded one")
            case (false, false):
                return String(localized: "You’re running version \(current), and version \(new) is available. Installing it restarts AutoHush.",
                              comment: "Update popup; the first %@ is the installed version, the second the new one")
            }
        }

        /// Where this copy can't update itself (not in a folder it can
        /// write to, or not signed with AutoHush's certificate).
        var byHand: String {
            if isBack {
                return String(localized: "Version \(current) is a release candidate, and Get release candidates is off. Download the latest release from GitHub and replace AutoHush in your Applications folder.",
                              comment: "Update alert where AutoHush can't update itself, offering the latest release, older than the release candidate running, after Get release candidates (a setting) was turned off; %@ is the installed version")
            }
            if isCandidate {
                return String(localized: "You have version \(current). Version \(new) is a release candidate, a test version of the next release: download it from GitHub and replace AutoHush in your Applications folder.",
                              comment: "Update alert where AutoHush can't update itself, offering a release candidate, a test version of the next release; the first %@ is the installed version, the second the new one")
            }
            return String(localized: "You have version \(current). Download it from GitHub and replace AutoHush in your Applications folder.",
                          comment: "Update alert; %@ is the installed version")
        }

        /// Installed with Homebrew, whose tap never has a release candidate:
        /// one is downloaded by hand, and the way back from one is a
        /// reinstall, since an upgrade never goes to an older version.
        var withHomebrew: String {
            if isBack {
                return String(localized: "Version \(current) is a release candidate, and Get release candidates is off. Go back to the latest release with Homebrew:",
                              comment: "Update alert for a copy installed with Homebrew, offering the latest release, older than the release candidate running, after Get release candidates (a setting) was turned off; %@ is the installed version. The Homebrew command follows.")
                    + "\n\nbrew reinstall --cask autohush"
            }
            if isCandidate {
                return String(localized: "You have version \(current). Version \(new) is a release candidate, which Homebrew doesn’t offer: download it from GitHub and replace AutoHush in your Applications folder.",
                              comment: "Update alert for a copy installed with Homebrew, offering a release candidate, a test version of the next release, which Homebrew doesn't have; the first %@ is the installed version, the second the new one")
            }
            return String(localized: "You have version \(current). Update with Homebrew:",
                          comment: "Update alert; %@ is the installed version. The Homebrew command follows.")
                + "\n\nbrew upgrade --cask autohush"
        }
    }
}
