import Foundation

/// How AutoHush decides whether another app is playing: audio levels,
/// or one of AntiDot mode's choices (Settings → Behavior and Fine-Tuning; the app has their text).
package enum DetectionMethod: String, Sendable {
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

    /// AntiDot mode: apps judged by what they tell macOS or by their open
    /// output, never by their sound (X13, the full check, 2026-10-19: decided
    /// here only).
    package var isAntiDot: Bool { self != .audioLevels }

    /// AntiDot mode's way until the user picks one, and when its card's
    /// defaults are restored: what apps tell macOS.
    package static let defaultAntiDot = DetectionMethod.playbackSignals
}
