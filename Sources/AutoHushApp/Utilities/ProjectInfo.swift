import Foundation

/// Where AutoHush lives on GitHub (update checks, Settings → About, the Help
/// menu), and where people can support it (Settings → About, and the foot of Settings'
/// sidebar).
enum ProjectInfo {
    static let repository = "hfustercabre/AutoHush"
    static let homepage = URL(string: "https://github.com/\(repository)")!
    static let supportPage = URL(string: "https://buymeacoffee.com/hfustercabre")!

    /// The GitHub page of the release of `version`, with its notes.
    static func releasePage(for version: AppVersion) -> URL {
        homepage.appending(path: "releases/tag/v\(version.tagName)")
    }

    /// What's New in Settings → About: the notes of the version running, or
    /// every release's when it isn't known.
    static func whatsNewPage(for version: AppVersion?) -> URL {
        version.map(releasePage(for:)) ?? homepage.appending(path: "releases")
    }

    /// AutoHush Help (the Help menu, ⌘?) and Help in Settings → About: the
    /// README's Tips and troubleshooting on GitHub (T7b, the user's pick,
    /// 2026-11-02). The README's heading makes the anchor, which a test checks.
    static let helpAnchor = "tips-and-troubleshooting"
    static let helpPage = URL(string: "\(homepage.absoluteString)#\(helpAnchor)")!

    /// Report an Issue in Settings → About: the bug report form, which asks
    /// for the version, macOS, the player and Diagnostics' report.
    static let newIssuePage = homepage.appending(path: "issues/new")
        .appending(queryItems: [URLQueryItem(name: "template", value: "bug.yml")])
}
