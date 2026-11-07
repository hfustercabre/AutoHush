import CoreGraphics
import Foundation
import Testing
import AutoHushKit
@testable import AutoHushPlayers
@testable import CheckedPlayers
import ScriptablePlayers
import SpotifySupport
import AppleMusicSupport
import MenuPlayers
import VLCSupport
@testable import QuickTimeSupport
@testable import WebAppPlayers
import AutoHushTestSupport

@Suite("SupportedPlayers")
struct SupportedPlayersTests {
    @Test("Spotify, Apple Music, VLC, Apple Podcasts, TIDAL and QuickTime Player are offered, the most used first")
    func players() {
        let catalog = SupportedPlayers.catalog
        #expect(catalog.players.map(\.bundleID) == [
            "com.spotify.client", "com.apple.Music", "org.videolan.vlc", "com.apple.podcasts", "com.tidal.desktop",
            "com.apple.QuickTimePlayerX",
        ])
        #expect(catalog.players.map(\.name) == ["Spotify", "Apple Music", "VLC", "Apple Podcasts", "TIDAL", "QuickTime Player"])
    }

    @Test("each built-in player is controlled its own way, is tested, and is found by macOS from its bundle ID")
    func builtInKinds() {
        let catalog = SupportedPlayers.catalog
        // The built-in players only: `player(bundleID:)` would also look for
        // the Safari web apps in this Mac's Applications folders.
        let player = { (id: String) in catalog.players.first { $0.bundleID == id } }
        #expect(player("com.apple.Music") is BackedUpPlayer<ScriptablePlayer>)
        #expect(player("com.tidal.desktop") is BackedUpPlayer<MenuPlayer>)
        #expect(player("com.apple.podcasts") is BackedUpPlayer<MenuPlayer>)
        #expect(player("org.videolan.vlc") is BackedUpPlayer<VLCPlayer>)
        #expect(player("com.apple.QuickTimePlayerX") is BackedUpPlayer<ScriptedAppPlayer>)
        #expect(catalog.players.allSatisfy { !$0.isUntested && $0.installedURL == nil })
    }

    @Test("QuickTime Player added with Add an App before it was built in is offered once, as the built-in player")
    func addedBuiltInPlayer() {
        // Its own store, never the preferences other test runs share.
        let store = DefaultsPlayerSetupStore(defaults: MemoryDefaults())
        let added = CheckedPlayers(store: store)
        store.save(PlayerSetup(bundleID: QuickTime.bundleID, name: QuickTime.name,
                               appURL: URL(fileURLWithPath: "/System/Applications/QuickTime Player.app"), ways: [.script(QuickTime.setup)]))
        #expect(added.current().map(\.bundleID).contains(QuickTime.bundleID))
        let quickTimes = SupportedPlayers.makeCatalog(added: added).all.filter { $0.bundleID == QuickTime.bundleID }
        #expect(quickTimes.count == 1 && quickTimes.first is BackedUpPlayer<ScriptedAppPlayer>)
    }

    @Test("each built-in player is backed up by the ways measured for it, then the Play/Pause key and the panel; Spotify's page learned by itself")
    func builtInBackups() {
        func kinds(_ id: String) -> [WayOrder.Kind]? {
            let player = SupportedPlayers.catalog.players.first { $0.bundleID == id }
            return (player as? BackedUpPlayer<ScriptablePlayer>)?.backups.map(\.kind)
                ?? (player as? BackedUpPlayer<MenuPlayer>)?.backups.map(\.kind)
                ?? (player as? BackedUpPlayer<VLCPlayer>)?.backups.map(\.kind)
                ?? (player as? BackedUpPlayer<ScriptedAppPlayer>)?.backups.map(\.kind)
        }
        #expect(kinds("com.spotify.client") == [.menu, .page, .mediaKey, .panel])
        #expect(kinds("com.apple.Music") == [.menu, .mediaKey, .panel])
        #expect(kinds("org.videolan.vlc") == [.menu, .mediaKey, .panel])
        for id in ["com.apple.podcasts", "com.tidal.desktop", "com.apple.QuickTimePlayerX"] { #expect(kinds(id) == [.mediaKey, .panel]) }
        let spotify = SupportedPlayers.catalog.players.first { $0.bundleID == "com.spotify.client" } as? BackedUpPlayer<ScriptablePlayer>
        #expect(spotify?.learningPage != nil && spotify?.inner.bundleID == "com.spotify.client")
    }

    @Test("Add an App never offers the 14 Apple apps that are no players, and none of them is a supported player, nor among this Mac's web apps and added apps")
    func notPlayers() {
        #expect(SupportedPlayers.notPlayers.count == 14)
        #expect(SupportedPlayers.notPlayers.allSatisfy { $0.hasPrefix("com.apple.") })
        #expect(SupportedPlayers.catalog.all.allSatisfy { !SupportedPlayers.notPlayers.contains($0.bundleID) })
    }

    @Test("every player has a placeholder icon, its mark on its tile")
    func iconPlaceholders() throws {
        let tile = CGRect(x: 0, y: 0, width: PlayerIconPlaceholder.tileSide, height: PlayerIconPlaceholder.tileSide)
        for player in SupportedPlayers.catalog.players {
            let placeholder = try #require(player.iconPlaceholder, "\(player.name) has no placeholder")
            let mark = placeholder.markShape().boundingBoxOfPath
            #expect(!mark.isEmpty && tile.contains(mark), "\(player.name)'s mark is off its tile")
        }
    }

    @Test("Spotify, YouTube Music, Amazon Music, Deezer and SoundCloud are the tested web apps, suggested until added; Amazon Music on the Mac's country's site")
    func suggestedWebApps() {
        #expect(SupportedPlayers.testedWebApps.map(\.name) == ["Spotify", "YouTube Music", "Amazon Music", "Deezer", "SoundCloud"])
        #expect(SupportedPlayers.testedWebApps.map(\.address).allSatisfy { WebAddress.url(from: $0) != nil })
        let sites = SupportedPlayers.amazonMusicSites
        #expect(sites.site(region: "ES") == "music.amazon.es")
        #expect(sites.site(region: "GB") == "music.amazon.co.uk")
        #expect(sites.site(region: "IE") == "music.amazon.co.uk")
        #expect(sites.site(region: "AT") == "music.amazon.de")
        #expect(sites.site(region: "US") == "music.amazon.com")
        #expect(sites.site(region: "NL") == "music.amazon.com")
        #expect(sites.site(region: nil) == "music.amazon.com")
        let amazon = SupportedPlayers.testedWebApps[2]
        #expect(amazon.countrySites == sites)
        #expect(!amazon.otherHosts.contains(amazon.address)) // its address once among its hosts
        #expect(SupportedPlayers.testedWebApps.filter { $0.countrySites != nil }.map(\.name) == ["Amazon Music"])
        #expect(SupportedPlayers.catalog.countrySites == [sites]) // offered by country in Add a Web App
        // Suggested: the tested ones this Mac has no web app for yet. A process that isn't a web app is none.
        let tested = Set(SupportedPlayers.testedWebApps.map(\.name))
        #expect(SupportedPlayers.catalog.webAppSuggestions.allSatisfy { tested.contains($0.name) })
        #expect(SupportedPlayers.hostedApp(pid: getpid()) == nil) // this test's own process
        let made = SafariWebApp(bundleID: SafariWebApp.bundleIDPrefix + "A", name: "Amazon Music",
                                url: URL(fileURLWithPath: "/Applications/A.app"), startURL: URL(string: "https://music.amazon.de/"))
        #expect(amazon.isAdded(as: made)) // whatever site the Mac's country gets
        let irish = SafariWebApp(bundleID: SafariWebApp.bundleIDPrefix + "B", name: "Amazon Music",
                                 url: URL(fileURLWithPath: "/Applications/B.app"), startURL: URL(string: "https://music.amazon.co.uk/"))
        #expect(amazon.isAdded(as: irish))
    }

    @Test("people updating from before the choice keep Spotify")
    func formerDefault() {
        #expect(SupportedPlayers.catalog.formerDefault == "com.spotify.client")
    }
}
