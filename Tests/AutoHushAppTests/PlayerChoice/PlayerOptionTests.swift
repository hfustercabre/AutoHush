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

    @Test("a copy of an app in the Trash doesn't count as installed")
    func trashIsNotInstalled() {
        let trashed = URL(fileURLWithPath: "/Users/someone/.Trash/Player.app")
        let otherVolume = URL(fileURLWithPath: "/Volumes/Disk/.Trashes/501/Player.app")
        let installed = URL(fileURLWithPath: "/Applications/Player.app")
        #expect(PlayerOption.firstOutsideTrash([trashed, otherVolume, installed]) == installed)
        #expect(PlayerOption.firstOutsideTrash([trashed, otherVolume]) == nil)
        #expect(PlayerOption.firstOutsideTrash([]) == nil)
    }
}
