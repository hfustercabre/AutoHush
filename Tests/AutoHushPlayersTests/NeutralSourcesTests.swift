import AutoHushKit
import Foundation
import Testing
@testable import AutoHushPlayers
@testable import WebAppPlayers

/// Outside AutoHushPlayers and PlayersSupport/, code never names a player,
/// its comments and translator comments included (the user, 2026-10-30):
/// the engine (the full check's N5, 2026-10-20), the app, its executable,
/// the check's panel and the helper, whose report's names come from the app
/// it checks; their tests and Tools/ too. Browsers and engines (Safari,
/// Chrome, Chromium, WebKit, Electron) aren't players, so they may be named.
@Suite("no code outside the players' modules names a player")
struct NeutralSourcesTests {
    private static let package = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // AutoHushPlayersTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the package

    /// The folders of Sources/ that may name players: the catalog and one
    /// module per kind of player.
    private static let playersFolders: Set<String> = ["AutoHushPlayers", "PlayersSupport"]

    /// The folders of Tests/ that may name players: the catalog's tests (this
    /// one's) and those of the players' modules.
    private static let playersTestFolders: Set<String> = ["AutoHushPlayersTests", "PlayersSupport"]

    /// Every other folder of Sources/, one per module (AutoHushKit,
    /// AutoHushApp, AutoHush, CheckPanel, PlayerCheck…).
    static let neutralFolders: [String] = folders(in: "Sources", except: playersFolders)

    /// Every other folder of Tests/ (AutoHushKitTests, AutoHushAppTests, the
    /// tests' support…), as paths in the package, and Tools/.
    static let neutralTestFolders: [String] = folders(in: "Tests", except: playersTestFolders).map { "Tests/" + $0 } + ["Tools"]

    /// The folders in `parent` but `except`, sorted.
    private static func folders(in parent: String, except: Set<String>) -> [String] {
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: package.appending(path: parent).path)) ?? []
        return folders.filter { !$0.hasPrefix(".") && !except.contains($0) }.sorted()
    }

    /// Every code file (Swift; Tools/ also has C and shell) in `folder`, a
    /// path in the package, its subfolders' too (not hidden ones, as a
    /// tool's `.build`).
    private static func codeFiles(in folder: String) -> [URL] {
        let found = FileManager.default.enumerator(at: package.appending(path: folder), includingPropertiesForKeys: nil,
                                                   options: .skipsHiddenFiles)?.allObjects as? [URL] ?? []
        return found.filter { ["swift", "c", "sh"].contains($0.pathExtension) }
    }

    /// Players AutoHush has met that it doesn't list (added apps, examples
    /// in comments): named no more there than the supported ones.
    private static let otherPlayers = ["Apple TV", "Qobuz", "Deezer", "IINA", "YouTube Music", "Amazon Music"]

    /// The supported players' names and bundle IDs, the tested web apps'
    /// names, and `otherPlayers`: a one-word name anywhere, whatever its case;
    /// a name of several words whole, whatever its case, and each word but
    /// "Apple", "Player" (QuickTime Player's, as in Player Check) and "Amazon"
    /// on its own: anywhere, whatever its case, when its case changes inside
    /// it ("QuickTime", "YouTube": no English word); otherwise as a word of
    /// its own, capitalized as the name has it (so not the same word in
    /// lowercase, which may be ordinary English).
    private static func names() -> (anyCase: [String], asWords: [String]) {
        let players = SupportedPlayers.catalog.players
        let names = Set(players.map(\.name) + SupportedPlayers.testedWebApps.map(\.name) + otherPlayers)
        let words = Set(names.filter { $0.contains(" ") }.flatMap { $0.split(separator: " ").map(String.init) })
            .subtracting(["Apple", "Player", "Amazon"])
        let coined = words.filter { $0.dropFirst().contains(where: \.isUppercase) && $0.contains(where: \.isLowercase) }
        let anyCase = Array(names) + players.map(\.bundleID) + sites() + coined
        return (anyCase, Array(words.subtracting(coined)))
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

    /// `names()` as one pattern each, made once per run: `anyCase`
    /// lowercased, for each file's lowercased text (the longest first, so a
    /// match is the whole name), with each one's name as listed; `asWords`
    /// for the text as it is.
    private static let patterns: (anyCase: NSRegularExpression, listed: [String: String], asWords: NSRegularExpression) = {
        let (anyCase, asWords) = names()
        let listed = Dictionary(anyCase.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        func pattern(_ names: some Sequence<String>, around: (String) -> String) -> NSRegularExpression {
            let alternatives = names.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
            // The names are escaped, so the pattern is always valid.
            return try! NSRegularExpression(pattern: around(alternatives.joined(separator: "|")))
        }
        return (pattern(listed.keys) { "(?:\($0))" }, listed, pattern(asWords) { "\\b(?:\($0))\\b" })
    }()

    /// Each match of `pattern` in `text` as "path:line names <name>", `name`
    /// saying whose name the matched text is.
    private static func found(_ pattern: NSRegularExpression, in text: String, path: String,
                              name: (String) -> String = { $0 }) -> [String] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let line = text[..<range.lowerBound].utf8.count(where: { $0 == UInt8(ascii: "\n") }) + 1
            return "\(path):\(line) names \(name(String(text[range])))"
        }
    }

    /// The names in each code file of `folder`, each with its file and line:
    /// `anyCase`'s, and `asWords`' when `asWords`.
    private static func names(in folder: String, asWords: Bool) throws -> [String] {
        let files = codeFiles(in: folder)
        try #require(!files.isEmpty, "no code file in \(folder)")
        return try files.flatMap { file in
            let text = try String(contentsOf: file, encoding: .utf8)
            let path = file.path.hasPrefix(package.path + "/") ? String(file.path.dropFirst(package.path.count + 1)) : file.path
            let (anyCase, listed, words) = patterns
            return found(anyCase, in: text.lowercased(), path: path) { listed[$0] ?? $0 }
                + (asWords ? found(words, in: text, path: path) : [])
        }
    }

    @Test("every folder of Sources/ and Tests/ outside the players' modules is checked, and Tools/")
    func everyFolderChecked() throws {
        try #require(Self.neutralFolders.count >= 5, "Sources/ not found in \(Self.package.path)")
        for folder in ["AutoHushKit", "AutoHushApp", "AutoHush", "CheckPanel", "PlayerCheck"] {
            #expect(Self.neutralFolders.contains(folder), "\(folder) isn't checked")
        }
        for folder in ["AutoHushKitTests", "AutoHushAppTests", "AutoHushTestSupport", "CheckPanelTests", "PlayerCheckTests"] {
            #expect(Self.neutralTestFolders.contains("Tests/" + folder), "Tests/\(folder) isn't checked")
        }
        #expect(Self.neutralTestFolders.contains("Tools"), "Tools/ isn't checked")
        #expect(Self.sites().contains("music.youtube.com"), "the tested web apps' sites aren't checked")
        #expect(Self.sites().contains("music.amazon.de"), "the country sites aren't checked")
        #expect(Self.names().anyCase.contains("QuickTime"), "a name's coined word isn't checked whatever its case")
    }

    @Test("no Swift file there names a supported player, a tested web app, its site or another known player",
          arguments: NeutralSourcesTests.neutralFolders)
    func namesNoPlayer(folder: String) throws {
        for found in try Self.names(in: "Sources/" + folder, asWords: true) {
            Issue.record("\(found)")
        }
    }

    /// The tests' stand-ins use the names' English words ("Yodel Music", an
    /// app called TV), so only `anyCase`'s names are looked for.
    @Test("no test outside the players' modules, nor any tool, names one, whatever its case",
          arguments: NeutralSourcesTests.neutralTestFolders)
    func testsNameNoPlayer(folder: String) throws {
        for found in try Self.names(in: folder, asWords: false) {
            Issue.record("\(found)")
        }
    }
}
