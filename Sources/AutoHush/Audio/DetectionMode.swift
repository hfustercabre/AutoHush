import Foundation

/// The detection AudioMonitor actually uses right now. It follows the
/// user's `DetectionMethod` and, for audio levels, whether the System Audio
/// Recording permission lets taps deliver real samples.
enum DetectionMode: Equatable, Sendable {
    /// No real audio sample seen yet; open output streams count as playing.
    case pending
    /// Process taps deliver real samples; sources are judged by loudness.
    case audioLevel
    /// Spotify played but its tap stayed silent: System Audio Recording
    /// permission is most likely missing. Open output streams count as playing.
    case unavailable
    /// AntiDot mode with "What apps tell macOS": apps are judged by their
    /// power assertions, or by their open output when they never hold one.
    /// No capture.
    case playbackSignals
    /// AntiDot mode with "Open audio streams only": open output streams count
    /// as playing. No capture.
    case disabled
}
