import Testing
@testable import SpotifySupport
import AutoHushKit
import AutoHushTestSupport

@Suite("SpotifyPlayer identity")
struct SpotifyPlayerIdentityTests {
    @Test("Spotify is named, identified and fades along a cube law")
    func identity() {
        let spotify = SpotifyPlayer()
        #expect(spotify.name == "Spotify")
        #expect(spotify.bundleID == "com.spotify.client")
        #expect(spotify.volumeCurve == .cubic)
    }

    @MainActor
    @Test("Spotify watches its state through its own observer")
    func observer() {
        let observer = SpotifyPlayer().makeStateObserver { _ in }
        #expect(observer is SpotifyPlaybackObserver)
    }
}
