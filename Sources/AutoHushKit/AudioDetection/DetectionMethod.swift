import Foundation

/// How AutoHush decides whether another app is playing: audio levels,
/// or one of AntiDot mode's choices (Settings → General, which has their text).
package enum DetectionMethod: String, CaseIterable, Sendable {
    /// Measures the other apps' audio levels. The most accurate; macOS shows
    /// its recording indicator while measuring.
    case audioLevels
    /// Judges every app by what it tells macOS: a "don't sleep" power
    /// assertion while it plays. Apps that never hold one count as playing
    /// while their audio output is open. Nothing is captured or asked, so no
    /// recording indicator. The raw value predates the rename and is kept so
    /// saved settings still load.
    case playbackSignals = "askApps"
    /// Any open audio output counts as playing. Nothing is captured or asked.
    case openStreams
}
