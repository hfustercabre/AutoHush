import CoreGraphics
import Foundation
import Testing
import AutoHushKit
import AutoHushPlayers
import ScriptablePlayers
import SpotifySupport
import AppleMusicSupport
import MenuPlayers
import VLCSupport
import WebAppPlayers

@Suite("SupportedPlayers")
struct SupportedPlayersTests {
    @Test("Spotify, Apple Music, VLC, Apple Podcasts and TIDAL are offered, the most used first")
    func players() {
        let catalog = SupportedPlayers.catalog
        #expect(catalog.players.map(\.bundleID)
            == ["com.spotify.client", "com.apple.Music", "org.videolan.vlc", "com.apple.podcasts", "com.tidal.desktop"])
        #expect(catalog.players.map(\.name) == ["Spotify", "Apple Music", "VLC", "Apple Podcasts", "TIDAL"])
        // The built-in players only: `player(bundleID:)` would also look for
        // the Safari web apps in this Mac's Applications folders.
        let player = { (id: String) in catalog.players.first { $0.bundleID == id } }
        #expect(player("com.apple.Music") is ScriptablePlayer)
        #expect(player("com.tidal.desktop") is MenuPlayer)
        #expect(player("com.apple.podcasts") is MenuPlayer)
        #expect(player("org.videolan.vlc") is VLCPlayer)
        #expect(catalog.players.allSatisfy { !$0.isUntested && $0.installedURL == nil })
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

    @Test("Spotify, YouTube Music, Amazon Music, Deezer and SoundCloud are the tested web apps; Amazon Music on the Mac's country's site")
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
        #expect(SupportedPlayers.testedWebApps.filter { $0.countrySites != nil }.map(\.name) == ["Amazon Music"])
        #expect(SupportedPlayers.catalog.countrySites == [sites]) // offered by country in Add a Web App
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
