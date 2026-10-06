import CoreGraphics
import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("PlayerOption")
@MainActor
struct PlayerOptionTests {
    @Test("every player in the catalog is offered, in its order, with where it's installed and its placeholder")
    func list() {
        let placeholder = PlayerIconPlaceholder(tile: [.init(0x000000)], mark: .init(0x1ED760)) { CGMutablePath() }
        let catalog = MusicPlayerCatalog(players: [
            MockMusicPlayer(bundleID: "com.example.first", name: "First", iconPlaceholder: placeholder),
            MockMusicPlayer(bundleID: "com.example.second", name: "Second"),
        ])
        let url = URL(fileURLWithPath: "/Applications/Second.app")
        let options = PlayerOption.list(catalog) { $0 == "com.example.second" ? url : nil }

        #expect(options == [
            PlayerOption(bundleID: "com.example.first", name: "First", appURL: nil),
            PlayerOption(bundleID: "com.example.second", name: "Second", appURL: url),
        ])
        #expect(options.map(\.isInstalled) == [false, true])
        #expect(options[0].iconPlaceholder?.mark == placeholder.mark)
        #expect(options[1].iconPlaceholder == nil)
        #expect(!options.noneInstalled)
        #expect([options[0]].noneInstalled)
    }

    @Test("players are offered installed first, then the others, each in the catalog's order")
    func installedFirst() {
        let options = [option("A", installed: false), option("B", installed: true), option("C", installed: false),
                       option("D", installed: true)]
        #expect(options.offered.map(\.name) == ["B", "D", "A", "C"])
        #expect(options.filter(\.isInstalled).offered.map(\.name) == ["B", "D"])
        #expect(options.offered.webAppsStart == nil)
    }

    @Test("Safari web apps come after every app, under their heading")
    func webAppsLast() {
        var webApp = option("YT Music", installed: true)
        webApp.kind = .safariWebApp
        let options = [webApp, option("A", installed: false), option("B", installed: true)]
        #expect(options.offered.map(\.name) == ["B", "A", "YT Music"])
        #expect(options.offered.webAppsStart == 2)
        #expect(options.offered.matching("yt").webAppsStart == 0)
        #expect(options.offered.matching("b").webAppsStart == nil)
        #expect(!PlayerOption.webAppsHeading.isEmpty)
        #expect(PlayerOption.experimentalBadge == "Experimental")
        #expect(PlayerOption.webAppsWarning.hasPrefix("Web apps are experimental."))
    }

    @Test("suggested web apps come after the web apps, marked with a download symbol, and can be clicked though not installed")
    func suggestions() {
        let catalog = MusicPlayerCatalog(
            players: [MockMusicPlayer(bundleID: "com.example.first", name: "First")],
            found: { [MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.A", name: "YT Music", status: .learned)] },
            suggested: { [WebAppSuggestion(name: "Deezer", address: "deezer.com")] }
        )
        let options = PlayerOption.list(catalog) { $0.hasPrefix("com.") ? URL(fileURLWithPath: "/Applications/\($0).app") : nil }
        #expect(options.offered.map(\.name) == ["First", "YT Music", "Deezer"])
        #expect(options.offered.webAppsStart == 1)
        let deezer = options[2]
        #expect(deezer.bundleID == PlayerOption.suggestionID("deezer.com"))
        #expect(deezer.webAddress == "deezer.com")
        #expect(deezer.kind == .safariWebApp)
        #expect(!deezer.isInstalled && deezer.isClickable)
        #expect(deezer.icon(size: 16).isTemplate)
        #expect(options.map(\.isClickable) == [true, true, true])
        #expect(!PlayerOption(bundleID: "com.example.gone", name: "Gone", appURL: nil).isClickable)
        #expect(options.onlyInstalled == nil) // two installed
    }

    @Test("the welcome window's note names only the apps that aren't installed, not suggested web apps")
    func onlyInstalledNoteSkipsSuggestions() {
        let options = [option("Spotify", installed: true), option("VLC", installed: false),
                       .suggestion(WebAppSuggestion(name: "Deezer", address: "deezer.com"))]
        let note = PlayerOption.onlyInstalledNote(among: options)
        #expect(note?.contains("VLC") == true)
        #expect(note?.contains("Deezer") == false)
    }

    @Test("from eight players on, they can be searched by name, ignoring case and accents")
    func search() {
        let names = ["Spotify", "Apple Music", "VLC", "Apple Podcasts", "TIDAL", "Qobuz", "Música"]
        let seven = names.map { option($0, installed: true) }
        #expect(!seven.isSearchable)
        #expect((seven + [option("Deezer", installed: false)]).isSearchable)
        #expect(PlayerOption.searchThreshold == 8)

        #expect(seven.matching("").map(\.name) == names)
        #expect(seven.matching("  ").map(\.name) == names)
        #expect(seven.matching(" musi ").map(\.name) == ["Apple Music", "Música"])
        #expect(seven.matching("APPLE P").map(\.name) == ["Apple Podcasts"])
        #expect(seven.matching("zz").isEmpty)
        #expect(PlayerOption.noMatchNote("zz") == "No players match “zz”.")
    }

    private func option(_ name: String, installed: Bool) -> PlayerOption {
        PlayerOption(bundleID: "com.example.\(name.lowercased())", name: name,
                     appURL: installed ? URL(fileURLWithPath: "/Applications/\(name).app") : nil)
    }

    @Test("with one player installed and others supported, the welcome window names them")
    func onlyInstalledWithOthers() {
        let options = [option("First", installed: true), option("Second", installed: false), option("Third", installed: false)]
        #expect(options.onlyInstalled?.name == "First")
        #expect(PlayerOption.onlyInstalledNote(among: options)
            == "First is the only supported music player on this Mac. AutoHush also works with Second and Third.")
    }

    @Test("with the only supported player installed, it's picked but there's nothing to add")
    func onlySupportedPlayer() {
        let options = [option("First", installed: true)]
        #expect(options.onlyInstalled?.name == "First")
        #expect(PlayerOption.onlyInstalledNote(among: options) == nil)
    }

    @Test("with two players installed, or none, nothing is picked and there's no note", arguments: [
        [true, true, false], [false, false, false],
    ])
    func noOnlyInstalled(installed: [Bool]) {
        let options = zip(["First", "Second", "Third"], installed).map { option($0, installed: $1) }
        #expect(options.onlyInstalled == nil)
        #expect(PlayerOption.onlyInstalledNote(among: options) == nil)
    }

    @Test("apps count as installed only in /Applications, the user's Applications folder and /System/Applications")
    func applicationFolders() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(PlayerOption.applicationFolders.map(\.path) == ["/Applications", "\(home)/Applications", "/System/Applications"])

        let anywhere: (URL) -> Bool = { _ in true }
        func installed(_ path: String) -> Bool {
            PlayerOption.firstInstalled([URL(fileURLWithPath: path)], exists: anywhere) != nil
        }
        #expect(installed("/Applications/Player.app"))
        #expect(installed("/Applications/Music Apps/Player.app"))
        #expect(installed("\(home)/Applications/Player.app"))
        #expect(installed("/System/Applications/Player.app"))

        #expect(!installed("\(home)/.Trash/Player.app"))
        #expect(!installed("/Volumes/Player/Player.app")) // the disk image it came from
        #expect(!installed("/Users/someone-else/Applications/Player.app"))
        #expect(!installed("\(home)/Downloads/Player.app"))
        #expect(!installed("/Applications Old/Player.app"))
    }

    @Test("the first copy in an Applications folder is the one found")
    func firstInApplicationFolders() {
        let trashed = URL(fileURLWithPath: "/Users/someone/.Trash/Player.app")
        let installed = URL(fileURLWithPath: "/Applications/Player.app")
        #expect(PlayerOption.firstInstalled([trashed, installed], exists: { _ in true }) == installed)
        #expect(PlayerOption.firstInstalled([trashed], exists: { _ in true }) == nil)
        #expect(PlayerOption.firstInstalled([], exists: { _ in true }) == nil)
    }

    @Test("an app macOS still lists but that's gone from disk doesn't count as installed")
    func deletedIsNotInstalled() {
        let deleted = URL(fileURLWithPath: "/Applications/Player.app")
        let installed = URL(fileURLWithPath: "/System/Applications/Player.app")
        #expect(PlayerOption.firstInstalled([deleted, installed]) { $0 == installed } == installed)
        #expect(PlayerOption.firstInstalled([deleted]) { _ in false } == nil)
        // The real check, against an app that is on every Mac.
        #expect(PlayerOption.firstInstalled([URL(fileURLWithPath: "/System/Applications/Music.app")]) != nil)
    }
}
