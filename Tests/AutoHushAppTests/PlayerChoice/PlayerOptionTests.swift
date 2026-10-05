import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("PlayerOption")
@MainActor
struct PlayerOptionTests {
    @Test("every player in the catalog is offered, in its order, with where it's installed")
    func list() {
        let catalog = MusicPlayerCatalog(players: [
            MockMusicPlayer(bundleID: "com.example.first", name: "First"),
            MockMusicPlayer(bundleID: "com.example.second", name: "Second"),
        ])
        let url = URL(fileURLWithPath: "/Applications/Second.app")
        let options = PlayerOption.list(catalog) { $0 == "com.example.second" ? url : nil }

        #expect(options == [
            PlayerOption(bundleID: "com.example.first", name: "First", appURL: nil),
            PlayerOption(bundleID: "com.example.second", name: "Second", appURL: url),
        ])
        #expect(options.map(\.isInstalled) == [false, true])
        #expect(!options.noneInstalled)
        #expect([options[0]].noneInstalled)
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
