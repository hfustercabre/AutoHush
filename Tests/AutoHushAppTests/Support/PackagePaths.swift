import Foundation

/// Where the package's files are, found from this file's place in it
/// (Tests/AutoHushAppTests/Support).
enum PackagePaths {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Support
        .deletingLastPathComponent() // AutoHushAppTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the package
    /// The String Catalogs, AutoHush's text in every language.
    static let catalogs = root.appending(path: "Resources/Localization")
}
