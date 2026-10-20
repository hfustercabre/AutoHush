import Foundation
import Testing
@testable import AutoHushPlayers
@testable import WebAppPlayers

/// Outside AutoHushPlayers and PlayersSupport/, code never names a player,
/// its comments included: the engine (the full check's N5, 2026-10-20) and
/// the helper, whose report's names come from the app it checks.
@Suite("the engine and the helper name no player")
struct NeutralSourcesTests {
    private static let package = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // AutoHushPlayersTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the package

    /// Every Swift file in `folder`, its subfolders' too.
    private static func swiftFiles(in folder: URL) -> [URL] {
        let found = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        return found.filter { $0.pathExtension == "swift" }
    }

    /// The supported players' names and bundle IDs, and the tested web apps'
    /// names: a one-word name anywhere, whatever its case; a name of several
    /// words whole, whatever its case, and each word but "Apple" and
    /// "Player" (QuickTime Player's, as in Player Check) as a word of its
    /// own, capitalized as the name has it (so not the same word in
    /// lowercase, which may be ordinary English).
    private static func names() -> (anyCase: [String], asWords: [String]) {
        let players = SupportedPlayers.catalog.players
        let names = Set(players.map(\.name) + SupportedPlayers.testedWebApps.map(\.name))
        let anyCase = Array(names) + players.map(\.bundleID)
        let asWords = names.filter { $0.contains(" ") }.flatMap { $0.split(separator: " ").map(String.init) }.filter { !["Apple", "Player"].contains($0) }
        return (anyCase, asWords)
    }

    @Test("no Swift file there names a supported player or a tested web app", arguments: ["Sources/AutoHushKit", "Sources/PlayerCheck"])
    func namesNoPlayer(folder: String) throws {
        let files = Self.swiftFiles(in: Self.package.appending(path: folder))
        try #require(files.count > 20, "\(folder) not found in \(Self.package.path)")
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
