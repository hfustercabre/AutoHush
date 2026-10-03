import Testing
@testable import AutoHush

@Suite("MusicPlayer")
struct MusicPlayerTests {
    @Test("Spotify is a supported player")
    func spotifyIsSupported() {
        let spotify = SpotifyPlayer()
        #expect(spotify.name == "Spotify")
        #expect(spotify.bundleID == "com.spotify.client")
        #expect(SupportedPlayers.bundleIDs.contains(spotify.bundleID))
    }

    @Test("a player's own audio never counts as another app playing")
    func playerAudioIsExcluded() {
        #expect(!AppConfiguration().isMediaSource(SpotifyPlayer.appBundleID))

        var configuration = AppConfiguration()
        configuration.musicPlayerBundleIDs = ["com.apple.Music"]
        #expect(!configuration.isMediaSource("com.apple.Music"))
        #expect(configuration.isMediaSource(SpotifyPlayer.appBundleID)) // not the player in use
    }

    @MainActor
    @Test("Spotify watches its state through its own observer")
    func spotifyObserver() {
        let observer = SpotifyPlayer().makeStateObserver { _ in }
        #expect(observer is SpotifyPlaybackObserver)
    }
}
