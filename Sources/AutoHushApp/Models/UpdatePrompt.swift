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
        let offer = Offer(current: current, isBack: release.version < running,
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
        message = offer.installing()
    }

    /// What's offered, said for each way it's installed. The title names
    /// the new version, so the text names only the one running (U3, the
    /// user's pick of 2026-11-08: shorter texts).
    private struct Offer {
        let current: String
        /// The latest release offered back from a release candidate.
        let isBack: Bool
        let isCandidate: Bool

        func installing() -> String {
            if isBack {
                return String(localized: "You have version \(current), and Get release candidates is off. Installing this release restarts AutoHush.",
                              comment: "Update popup, offering the latest release, older than the release candidate running, after Get release candidates (a setting) was turned off; %@ is the installed version")
            }
            if isCandidate {
                return String(localized: "You have version \(current). Installing this release candidate restarts AutoHush.",
                              comment: "Update popup for a release candidate, a test version of the next release, available or downloaded (the title names it); %@ is the installed version")
            }
            return String(localized: "You have version \(current). Installing it restarts AutoHush.",
                          comment: "Update popup, the new version available or downloaded (the title names it); %@ is the installed version")
        }

        /// Where this copy can't update itself (not in a folder it can
        /// write to, or not signed with AutoHush's certificate).
        var byHand: String {
            if isBack {
                return String(localized: "You have version \(current), and Get release candidates is off. Download this release from GitHub and replace AutoHush in Applications.",
                              comment: "Update alert where AutoHush can't update itself, offering the latest release, older than the release candidate running, after Get release candidates (a setting) was turned off; %@ is the installed version. Applications is the Applications folder")
            }
            if isCandidate {
                return String(localized: "You have version \(current). Download this release candidate from GitHub and replace AutoHush in Applications.",
                              comment: "Update alert where AutoHush can't update itself, offering a release candidate, a test version of the next release (the title names it); %@ is the installed version. Applications is the Applications folder")
            }
            return String(localized: "You have version \(current). Download the new one from GitHub and replace AutoHush in Applications.",
                          comment: "Update alert where AutoHush can't update itself (the title names the new version); %@ is the installed version. Applications is the Applications folder")
        }

        /// Installed with Homebrew, whose tap never has a release candidate:
        /// one is downloaded by hand, and the way back from one is a
        /// reinstall, since an upgrade never goes to an older version.
        var withHomebrew: String {
            if isBack {
                return String(localized: "You have version \(current), and Get release candidates is off. Go back with Homebrew:",
                              comment: "Update alert for a copy installed with Homebrew, offering the latest release, older than the release candidate running, after Get release candidates (a setting) was turned off; %@ is the installed version. The Homebrew command follows.")
                    + "\n\nbrew reinstall --cask autohush"
            }
            if isCandidate {
                return String(localized: "You have version \(current). Homebrew has no release candidates: download this one from GitHub and replace AutoHush in Applications.",
                              comment: "Update alert for a copy installed with Homebrew, offering a release candidate, a test version of the next release, which Homebrew doesn't have; %@ is the installed version. Applications is the Applications folder")
            }
            return String(localized: "You have version \(current). Update with Homebrew:",
                          comment: "Update alert; %@ is the installed version. The Homebrew command follows.")
                + "\n\nbrew upgrade --cask autohush"
        }
    }
}
