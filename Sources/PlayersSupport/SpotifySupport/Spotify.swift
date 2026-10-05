import Foundation
import AutoHushKit
import ScriptablePlayers

extension ScriptablePlayerProfile {
    /// Spotify for macOS. Codes from `Spotify.app/Contents/Resources/Spotify.sdef`.
    package static let spotify = ScriptablePlayerProfile(
        bundleID: "com.spotify.client",
        name: "Spotify",
        suite: fourCharCode("spfy"),
        stateNotification: Notification.Name("com.spotify.client.PlaybackStateChanged"),
        // Measured on Spotify 1.3.3 (`swift run measure-volume-curve`): within
        // 2 dB of a cube law from 15 to 90 (50 → −18 dB, 20 → −40 dB); 11 is
        // about −54 dB and 10 or less is silent.
        volumeCurve: .cubic,
        // Spotify reports one less than the volume it was set to (set 50,
        // read 49; measured for 1–99).
        readVolume: { (1...99).contains($0) ? $0 + 1 : $0 },
        iconPlaceholder: .spotify
    )
}
