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
        let later = Button(title: String(localized: "Later", comment: "Button that closes it for now: an update alert, or a window that learns a web app's controls (the learning window, the Add a Web App window)"),
                           choice: .later)
        let openPage = Button(title: String(localized: "Open Release Page", comment: "Update alert button"),
                              choice: .openReleasePage)
        guard canInstall else {
            title = String(localized: "AutoHush \(new) Is Available", comment: "Alert title; %@ is the new version number")
            message = isHomebrewInstall
                ? String(localized: "You have version \(current). Update with Homebrew:",
                         comment: "Update alert; %@ is the installed version. The Homebrew command follows.")
                    + "\n\nbrew upgrade --cask autohush"
                : String(localized: "You have version \(current). Download it from GitHub and replace AutoHush in your Applications folder.",
                         comment: "Update alert; %@ is the installed version")
            buttons = [openPage, later]
            return
        }
        if isDownloaded {
            title = String(localized: "AutoHush \(new) Is Ready to Install",
                           comment: "Update popup title; %@ is the new version, already downloaded")
            message = String(localized: "You're running version \(current), and version \(new) is downloaded. Installing it restarts AutoHush.",
                             comment: "Update popup; the first %@ is the installed version, the second the downloaded one")
            buttons = [
                Button(title: String(localized: "Install and Relaunch", comment: "Update alert button"), choice: .install),
                later, openPage,
            ]
        } else {
            title = String(localized: "AutoHush \(new) Is Available", comment: "Alert title; %@ is the new version number")
            message = String(localized: "You're running version \(current), and version \(new) is available. Installing it restarts AutoHush.",
                             comment: "Update popup; the first %@ is the installed version, the second the new one")
            buttons = [
                Button(title: String(localized: "Download and Install",
                                     comment: "Update popup button: downloads the update, installs it and restarts"),
                       choice: .install),
                later, openPage,
            ]
        }
    }
}
