import Foundation

/// The timings users can tune in Settings → Detection and → Fades.
package struct TimingSettings: Equatable, Sendable {
    /// Seconds another app must be audible before the music pauses.
    package var startConfirmation: TimeInterval
    /// Seconds another app must be silent before it counts as stopped. The
    /// music resumes as soon as no other app plays.
    package var stopGrace: TimeInterval
    /// Peak level (dBFS) below which an app counts as silent.
    package var silenceThresholdDB: Double
    /// Seconds the music fades out before pausing.
    package var fadeOutDuration: TimeInterval
    /// Seconds the music fades back in after resuming.
    package var fadeInDuration: TimeInterval
    /// Whether the music fades at all; off, it pauses and resumes at once,
    /// whatever the fade durations say.
    package var fadesEnabled: Bool

    package init(
        startConfirmation: TimeInterval = 0.5,
        stopGrace: TimeInterval = 2.0,
        silenceThresholdDB: Double = -60,
        fadeOutDuration: TimeInterval = 1,
        fadeInDuration: TimeInterval = 2,
        fadesEnabled: Bool = true
    ) {
        self.startConfirmation = startConfirmation
        self.stopGrace = stopGrace
        self.silenceThresholdDB = silenceThresholdDB
        self.fadeOutDuration = fadeOutDuration
        self.fadeInDuration = fadeInDuration
        self.fadesEnabled = fadesEnabled
    }

    package static let defaults = TimingSettings()

    package static let startConfirmationRange: ClosedRange<TimeInterval> = 0...5
    /// At least a second: shorter would resume the music in every pause
    /// between tracks or videos.
    package static let stopGraceRange: ClosedRange<TimeInterval> = 1...10
    package static let silenceThresholdRange: ClosedRange<Double> = -90 ... -30
    package static let fadeDurationRange: ClosedRange<TimeInterval> = 0...5

    /// The same settings with every value clamped to its allowed range.
    package var clamped: TimingSettings {
        TimingSettings(
            startConfirmation: startConfirmation.clamped(to: Self.startConfirmationRange),
            stopGrace: stopGrace.clamped(to: Self.stopGraceRange),
            silenceThresholdDB: silenceThresholdDB.clamped(to: Self.silenceThresholdRange),
            fadeOutDuration: fadeOutDuration.clamped(to: Self.fadeDurationRange),
            fadeInDuration: fadeInDuration.clamped(to: Self.fadeDurationRange),
            fadesEnabled: fadesEnabled
        )
    }
}
