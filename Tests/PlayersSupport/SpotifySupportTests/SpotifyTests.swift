import Foundation
import Testing
import AutoHushKit
import ScriptablePlayers
@testable import SpotifySupport

@Suite("Spotify")
struct SpotifyTests {
    @Test("Spotify is named, identified, scripted through its own suite and fades along a cube law")
    func profile() {
        let spotify = ScriptablePlayerProfile.spotify
        #expect(spotify.name == "Spotify")
        #expect(spotify.bundleID == "com.spotify.client")
        #expect(spotify.suite == fourCharCode("spfy"))
        #expect(spotify.stateNotification.rawValue == "com.spotify.client.PlaybackStateChanged")
        #expect(spotify.volumeCurve == .cubic)
    }

    @Test("Spotify's volume reading is corrected for its off-by-one", arguments: [
        (49, 50), (0, 0), (1, 2), (99, 100), (100, 100),
    ])
    func volumeReading(reported: Int, volume: Int) {
        #expect(ScriptablePlayerProfile.spotify.readVolume(reported) == volume)
    }
}
