import Foundation

/// The detection timings users can tune in Settings → Advanced.
package struct TimingSettings: Equatable, Sendable {
    /// Seconds another app must be audible before the music pauses.
    package var startConfirmation: TimeInterval
    /// Seconds another app must be silent before it counts as stopped.
    package var stopGrace: TimeInterval
    /// Seconds to wait after all other apps stopped before resuming the music.
    package var resumeDelay: TimeInterval
    /// Peak level (dBFS) below which an app counts as silent.
    package var silenceThresholdDB: Double
    /// Seconds the music fades out before pausing.
    package var fadeOutDuration: TimeInterval
    /// Seconds the music fades back in after resuming.
    package var fadeInDuration: TimeInterval

    package init(
        startConfirmation: TimeInterval = 0.5,
        stopGrace: TimeInterval = 2.0,
        resumeDelay: TimeInterval = 0.2,
        silenceThresholdDB: Double = -60,
        fadeOutDuration: TimeInterval = 1,
        fadeInDuration: TimeInterval = 2
    ) {
        self.startConfirmation = startConfirmation
        self.stopGrace = stopGrace
        self.resumeDelay = resumeDelay
        self.silenceThresholdDB = silenceThresholdDB
        self.fadeOutDuration = fadeOutDuration
        self.fadeInDuration = fadeInDuration
    }

    package static let defaults = TimingSettings()

    package static let startConfirmationRange: ClosedRange<TimeInterval> = 0...5
    package static let stopGraceRange: ClosedRange<TimeInterval> = 0...10
    package static let resumeDelayRange: ClosedRange<TimeInterval> = 0...5
    package static let silenceThresholdRange: ClosedRange<Double> = -90 ... -30
    package static let fadeDurationRange: ClosedRange<TimeInterval> = 0...5

    /// The same settings with every value clamped to its allowed range.
    package var clamped: TimingSettings {
        TimingSettings(
            startConfirmation: startConfirmation.clamped(to: Self.startConfirmationRange),
            stopGrace: stopGrace.clamped(to: Self.stopGraceRange),
            resumeDelay: resumeDelay.clamped(to: Self.resumeDelayRange),
            silenceThresholdDB: silenceThresholdDB.clamped(to: Self.silenceThresholdRange),
            fadeOutDuration: fadeOutDuration.clamped(to: Self.fadeDurationRange),
            fadeInDuration: fadeInDuration.clamped(to: Self.fadeDurationRange)
        )
    }
}

extension AppConfiguration {
    /// The default configuration with the user's timings applied.
    package init(timings: TimingSettings) {
        self.init()
        let timings = timings.clamped
        sourceStartConfirmation = timings.startConfirmation
        sourceStopGrace = timings.stopGrace
        debounceSeconds = timings.resumeDelay
        audibleThreshold = Float(pow(10, timings.silenceThresholdDB / 20))
        fadeOutDuration = timings.fadeOutDuration
        fadeInDuration = timings.fadeInDuration
    }
}
