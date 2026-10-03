import Foundation

/// How AutoHush decides whether another app is playing: audio levels,
/// or one of AntiDot mode's choices (Settings → General).
enum DetectionMethod: String, CaseIterable, Sendable {
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

    var title: String {
        switch self {
        case .audioLevels:     return "Measure audio levels"
        case .playbackSignals: return "What apps tell macOS"
        case .openStreams:     return "Open audio streams only"
        }
    }

    var summary: String {
        switch self {
        case .audioLevels:
            return "Most accurate: a paused video stops counting as soon as it goes silent. macOS shows its purple recording indicator while AutoHush measures."
        case .playbackSignals:
            return "An app counts as playing while it tells macOS it is playing, and as paused once it stops, even with its audio still open. Apps that never tell macOS count while their audio is open."
        case .openStreams:
            return "Any app with its audio open counts as playing, even when paused."
        }
    }
}
