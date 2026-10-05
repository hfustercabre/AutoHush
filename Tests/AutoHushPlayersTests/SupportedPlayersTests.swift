import Testing
import AutoHushKit
import AutoHushPlayers
import ScriptablePlayers
import SpotifySupport
import AppleMusicSupport

@Suite("SupportedPlayers")
struct SupportedPlayersTests {
    @Test("Spotify and Apple Music are offered, in that order")
    func players() {
        let catalog = SupportedPlayers.catalog
        #expect(catalog.players.map(\.bundleID) == ["com.spotify.client", "com.apple.Music"])
        #expect(catalog.players.map(\.name) == ["Spotify", "Apple Music"])
        #expect(catalog.player(bundleID: "com.apple.Music") is ScriptablePlayer)
        #expect(catalog.player(bundleID: "com.example.unknown") == nil)
    }

    @Test("people updating from before the choice keep Spotify")
    func formerDefault() {
        #expect(SupportedPlayers.catalog.formerDefault == "com.spotify.client")
    }
}
