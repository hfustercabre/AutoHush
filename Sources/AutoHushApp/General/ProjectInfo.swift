import Foundation

/// Where AutoHush lives on GitHub (update checks, About panel), and where
/// people can support it (About panel, Settings → General).
enum ProjectInfo {
    static let repository = "hfustercabre/AutoHush"
    static let homepage = URL(string: "https://github.com/\(repository)")!
    static let supportPage = URL(string: "https://buymeacoffee.com/hfustercabre")!

    /// The GitHub page of the release of `version`, with its notes.
    static func releasePage(for version: AppVersion) -> URL {
        homepage.appending(path: "releases/tag/v\(version)")
    }
}
