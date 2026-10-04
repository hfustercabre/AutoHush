import Foundation

/// Where AutoHush lives on GitHub (update checks, About panel), and where
/// people can support it (the menu's Buy Me a Coffee).
enum ProjectInfo {
    static let repository = "hfustercabre/AutoHush"
    static let homepage = URL(string: "https://github.com/\(repository)")!
    static let supportPage = URL(string: "https://buymeacoffee.com/hfustercabre")!
}
