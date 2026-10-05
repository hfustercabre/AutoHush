import Testing
import AutoHushKit
import AutoHushPlayers
import ScriptablePlayers
import SpotifySupport
import AppleMusicSupport
import TidalSupport

@Suite("SupportedPlayers")
struct SupportedPlayersTests {
    @Test("Spotify, Apple Music and TIDAL are offered, in that order")
    func players() {
        let catalog = SupportedPlayers.catalog
        #expect(catalog.players.map(\.bundleID) == ["com.spotify.client", "com.apple.Music", "com.tidal.desktop"])
        #expect(catalog.players.map(\.name) == ["Spotify", "Apple Music", "TIDAL"])
        #expect(catalog.player(bundleID: "com.apple.Music") is ScriptablePlayer)
        #expect(catalog.player(bundleID: "com.tidal.desktop") is TidalPlayer)
        #expect(catalog.player(bundleID: "com.example.unknown") == nil)
    }

    @Test("people updating from before the choice keep Spotify")
    func formerDefault() {
        #expect(SupportedPlayers.catalog.formerDefault == "com.spotify.client")
    }
}
