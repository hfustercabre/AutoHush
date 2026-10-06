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
        #expect(catalog.player(bundleID: "com.apple.Music") is ScriptablePlayer)
        #expect(catalog.player(bundleID: "com.tidal.desktop") is MenuPlayer)
        #expect(catalog.player(bundleID: "com.apple.podcasts") is MenuPlayer)
        #expect(catalog.player(bundleID: "org.videolan.vlc") is VLCPlayer)
        #expect(catalog.player(bundleID: "com.example.unknown") == nil)
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

    @Test("Spotify, YouTube Music, Amazon Music and Deezer are suggested as web apps; Amazon Music on the Mac's country's site")
    func suggestedWebApps() {
        #expect(SupportedPlayers.suggestedWebApps.map(\.name) == ["Spotify", "YouTube Music", "Amazon Music", "Deezer"])
        #expect(SupportedPlayers.suggestedWebApps.map(\.address).allSatisfy { WebAddress.url(from: $0) != nil })
        #expect(SupportedPlayers.amazonMusicSite(region: "ES") == "music.amazon.es")
        #expect(SupportedPlayers.amazonMusicSite(region: "GB") == "music.amazon.co.uk")
        #expect(SupportedPlayers.amazonMusicSite(region: "US") == "music.amazon.com")
        #expect(SupportedPlayers.amazonMusicSite(region: "NL") == "music.amazon.com")
        #expect(SupportedPlayers.amazonMusicSite(region: nil) == "music.amazon.com")
        let amazon = SupportedPlayers.suggestedWebApps[2]
        let made = SafariWebApp(bundleID: SafariWebApp.bundleIDPrefix + "A", name: "Amazon Music",
                                url: URL(fileURLWithPath: "/Applications/A.app"), startURL: URL(string: "https://music.amazon.de/"))
        #expect(amazon.isAdded(as: made)) // whatever site the Mac's country gets
    }

    @Test("people updating from before the choice keep Spotify")
    func formerDefault() {
        #expect(SupportedPlayers.catalog.formerDefault == "com.spotify.client")
    }
}
