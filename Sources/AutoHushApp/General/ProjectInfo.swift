import Foundation

/// Where AutoHush lives on GitHub (update checks, Settings → About), and
/// where people can support it (Settings → About and → General).
enum ProjectInfo {
    static let repository = "hfustercabre/AutoHush"
    static let homepage = URL(string: "https://github.com/\(repository)")!
    static let supportPage = URL(string: "https://buymeacoffee.com/hfustercabre")!

    /// The GitHub page of the release of `version`, with its notes.
    static func releasePage(for version: AppVersion) -> URL {
        homepage.appending(path: "releases/tag/v\(version)")
    }

    /// What's New in Settings → About: the notes of the version running, or
    /// every release's when it isn't known.
    static func whatsNewPage(for version: AppVersion?) -> URL {
        version.map(releasePage(for:)) ?? homepage.appending(path: "releases")
    }

    /// Report an Issue in Settings → About.
    static let newIssuePage = homepage.appending(path: "issues/new")
}
