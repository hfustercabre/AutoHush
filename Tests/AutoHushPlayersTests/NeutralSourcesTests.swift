import AutoHushKit
import Foundation
import Testing
@testable import AutoHushPlayers
@testable import WebAppPlayers

/// Outside AutoHushPlayers and PlayersSupport/, code never names a player,
/// its comments and translator comments included (the user, 2026-10-30):
/// the engine (the full check's N5, 2026-10-20), the app, its executable,
/// the check's panel and the helper, whose report's names come from the app
/// it checks. Browsers and engines (Safari, Chrome, Chromium, WebKit,
/// Electron) aren't players, so they may be named.
@Suite("no code outside the players' modules names a player")
struct NeutralSourcesTests {
    private static let package = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // AutoHushPlayersTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the package

    /// The folders of Sources/ that may name players: the catalog and one
    /// module per kind of player.
    private static let playersFolders: Set<String> = ["AutoHushPlayers", "PlayersSupport"]

    /// Every other folder of Sources/, one per module (AutoHushKit,
    /// AutoHushApp, AutoHush, CheckPanel, PlayerCheck…).
    static let neutralFolders: [String] = {
        let sources = package.appending(path: "Sources")
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: sources.path)) ?? []
        return folders.filter { !$0.hasPrefix(".") && !playersFolders.contains($0) }.sorted()
    }()

    /// Every Swift file in `folder`, its subfolders' too.
    private static func swiftFiles(in folder: URL) -> [URL] {
        let found = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        return found.filter { $0.pathExtension == "swift" }
    }

    /// Players AutoHush has met that it doesn't list (added apps, examples
    /// in comments): named no more there than the supported ones.
    private static let otherPlayers = ["Apple TV", "Qobuz", "Deezer", "IINA", "YouTube Music", "Amazon Music"]

    /// The supported players' names and bundle IDs, the tested web apps'
    /// names, and `otherPlayers`: a one-word name anywhere, whatever its case; a name of several
    /// words whole, whatever its case, and each word but "Apple",
    /// "Player" (QuickTime Player's, as in Player Check) and "Amazon" as a word of its
    /// own, capitalized as the name has it (so not the same word in
    /// lowercase, which may be ordinary English).
    private static func names() -> (anyCase: [String], asWords: [String]) {
        let players = SupportedPlayers.catalog.players
        let names = Set(players.map(\.name) + SupportedPlayers.testedWebApps.map(\.name) + otherPlayers)
        let anyCase = Array(names) + players.map(\.bundleID) + sites()
        let asWords = names.filter { $0.contains(" ") }.flatMap { $0.split(separator: " ").map(String.init) }
            .filter { !["Apple", "Player", "Amazon"].contains($0) }
        return (anyCase, asWords)
    }

    /// The tested web apps' sites (their addresses and other hosts), the
    /// catalog's country sites and its example address, whatever their case;
    /// for a host of three parts or more, also the domain it's on
    /// (consent.youtube.com is on youtube.com as music.youtube.com is), unless
    /// that's only a country's ending (co.uk, com.br).
    private static func sites() -> [String] {
        let catalog = SupportedPlayers.catalog
        let hosts = SupportedPlayers.testedWebApps.flatMap(\.hosts) + catalog.countrySites.flatMap(\.hosts)
            + [catalog.exampleWebAddress].compactMap { $0 }
        let domains = hosts.compactMap { host -> String? in
            let parts = host.split(separator: ".")
            guard parts.count >= 3, parts[1].count > 3 else { return nil }
            return parts.dropFirst().joined(separator: ".")
        }
        return Array(Set(hosts + domains))
    }

    @Test("every folder of Sources/ outside the players' modules is checked")
    func everyFolderChecked() throws {
        try #require(Self.neutralFolders.count >= 5, "Sources/ not found in \(Self.package.path)")
        for folder in ["AutoHushKit", "AutoHushApp", "AutoHush", "CheckPanel", "PlayerCheck"] {
            #expect(Self.neutralFolders.contains(folder), "\(folder) isn't checked")
        }
        #expect(Self.sites().contains("music.youtube.com"), "the tested web apps' sites aren't checked")
        #expect(Self.sites().contains("music.amazon.de"), "the country sites aren't checked")
    }

    @Test("no Swift file there names a supported player, a tested web app, its site or another known player",
          arguments: NeutralSourcesTests.neutralFolders)
    func namesNoPlayer(folder: String) throws {
        let files = Self.swiftFiles(in: Self.package.appending(path: "Sources").appending(path: folder))
        try #require(!files.isEmpty, "no Swift file in Sources/\(folder)")
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
