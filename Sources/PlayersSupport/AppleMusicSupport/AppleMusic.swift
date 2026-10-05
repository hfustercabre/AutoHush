import Foundation
import AutoHushKit
import ScriptablePlayers

extension ScriptablePlayerProfile {
    /// Apple Music, the Music app that comes with macOS. Codes from
    /// `Music.app/Contents/Resources/com.apple.Music.sdef`.
    package static let appleMusic = ScriptablePlayerProfile(
        bundleID: "com.apple.Music",
        name: "Apple Music",
        suite: fourCharCode("hook"),
        // Posted twice per change: the previous state, then the new one
        // (see `PlaybackArbiter.handlePlayerStateChange`).
        stateNotification: Notification.Name("com.apple.Music.playerInfo"),
        // Measured on Music 1.7 (`swift run measure-volume-curve com.apple.Music`):
        // linear within 0.8 dB from 5 to 90 (50 → −6 dB); 1 is silent. The
        // volume reads back as it was set.
        volumeCurve: .linear,
        iconPlaceholder: .appleMusic
    )
}
