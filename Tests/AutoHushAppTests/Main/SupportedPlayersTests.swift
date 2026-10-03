import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushPlayers
import SpotifySupport
import AutoHushTestSupport

@Suite("SupportedPlayers")
struct SupportedPlayersTests {
    @Test("Spotify is the player AutoHush controls, and a supported one")
    func spotifyIsSupported() {
        let player = SupportedPlayers.makeDefault()
        #expect(player is SpotifyPlayer)
        #expect(SupportedPlayers.bundleIDs.contains(player.bundleID))
        #expect(SupportedPlayers.player(bundleID: "com.spotify.client") is SpotifyPlayer)
        #expect(SupportedPlayers.player(bundleID: "com.example.unknown") == nil)
    }

    @Test("the supported players' own audio never counts as another app playing")
    func playerAudioIsExcluded() {
        var configuration = AppConfiguration(timings: .defaults)
        configuration.musicPlayerBundleIDs = SupportedPlayers.bundleIDs
        #expect(!configuration.isMediaSource(SpotifyPlayer.appBundleID))
        #expect(configuration.isMediaSource("org.videolan.vlc"))
    }
}
