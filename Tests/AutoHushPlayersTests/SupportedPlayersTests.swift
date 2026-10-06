import CoreGraphics
import Testing
import AutoHushKit
import AutoHushPlayers
import ScriptablePlayers
import SpotifySupport
import AppleMusicSupport
import MenuPlayers
import VLCSupport

@Suite("SupportedPlayers")
struct SupportedPlayersTests {
    @Test("Spotify, Apple Music, TIDAL, Apple Podcasts and VLC are offered, in that order")
    func players() {
        let catalog = SupportedPlayers.catalog
        #expect(catalog.players.map(\.bundleID)
            == ["com.spotify.client", "com.apple.Music", "com.tidal.desktop", "com.apple.podcasts", "org.videolan.vlc"])
        #expect(catalog.players.map(\.name) == ["Spotify", "Apple Music", "TIDAL", "Apple Podcasts", "VLC"])
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

    @Test("people updating from before the choice keep Spotify")
    func formerDefault() {
        #expect(SupportedPlayers.catalog.formerDefault == "com.spotify.client")
    }
}
