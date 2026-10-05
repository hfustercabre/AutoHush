import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushPlayers
import SpotifySupport
import AutoHushTestSupport

@Suite("SupportedPlayers")
struct SupportedPlayersTests {
    @Test("Spotify is offered, and people updating from before the choice keep it")
    func spotifyIsSupported() {
        let catalog = SupportedPlayers.catalog
        #expect(catalog.player(bundleID: "com.spotify.client") is SpotifyPlayer)
        #expect(catalog.formerDefault == SpotifyPlayer.appBundleID)
        #expect(catalog.player(bundleID: "com.example.unknown") == nil)
    }

    @Test("every supported player is offered once")
    func playersAreUnique() {
        let bundleIDs = SupportedPlayers.catalog.players.map(\.bundleID)
        #expect(Set(bundleIDs).count == bundleIDs.count)
    }
}
