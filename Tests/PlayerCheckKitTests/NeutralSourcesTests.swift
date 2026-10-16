import Foundation
import Testing
import AutoHushPlayers

/// The helper names no player: outside AutoHushPlayers and PlayersSupport/,
/// code never does. A name in its report comes from the app it checks.
@Suite("Sources/PlayerCheck names no player")
struct NeutralSourcesTests {
    private static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // PlayerCheckKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the package
        .appending(path: "Sources/PlayerCheck")

    /// Every Swift file there, its Kit's too.
    private static func swiftFiles() -> [URL] {
        let found = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        return found.filter { $0.pathExtension == "swift" }
    }

    /// The supported players' names and bundle IDs, and the tested web apps'
    /// names: a one-word name anywhere, whatever its case; a name of several
    /// words whole, whatever its case, and each word but Apple's as a word
    /// of its own, capitalized as the name has it (so not the same word in
    /// lowercase, which may be ordinary English).
    private static func names() -> (anyCase: [String], asWords: [String]) {
        let players = SupportedPlayers.catalog.players
        let names = Set(players.map(\.name) + SupportedPlayers.testedWebApps.map(\.name))
        let anyCase = Array(names) + players.map(\.bundleID)
        let asWords = names.filter { $0.contains(" ") }.flatMap { $0.split(separator: " ").map(String.init) }.filter { $0 != "Apple" }
        return (anyCase, asWords)
    }

    @Test("no Swift file in Sources/PlayerCheck names a supported player or a tested web app")
    func namesNoPlayer() throws {
        let files = Self.swiftFiles()
        try #require(files.count > 20, "Sources/PlayerCheck not found at \(Self.folder.path)")
        let (anyCase, asWords) = Self.names()
        try #require(!anyCase.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for name in anyCase {
                #expect(text.range(of: name, options: .caseInsensitive) == nil, "\(file.lastPathComponent) names \(name)")
            }
            for word in asWords {
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
                #expect(text.range(of: pattern, options: .regularExpression) == nil, "\(file.lastPathComponent) names \(word)")
            }
        }
    }
}
