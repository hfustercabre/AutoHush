import Foundation

/// The detection timings users can tune in Settings → Advanced.
struct TimingSettings: Equatable, Sendable {
    /// Seconds another app must be audible before the music pauses.
    var startConfirmation: TimeInterval = 0.5
    /// Seconds another app must be silent before it counts as stopped.
    var stopGrace: TimeInterval = 2.0
    /// Seconds to wait after all other apps stopped before resuming the music.
    var resumeDelay: TimeInterval = 0.2
    /// Peak level (dBFS) below which an app counts as silent.
    var silenceThresholdDB: Double = -60

    static let defaults = TimingSettings()

    static let startConfirmationRange: ClosedRange<TimeInterval> = 0...5
    static let stopGraceRange: ClosedRange<TimeInterval> = 0...10
    static let resumeDelayRange: ClosedRange<TimeInterval> = 0...5
    static let silenceThresholdRange: ClosedRange<Double> = -90 ... -30

    /// The same settings with every value clamped to its allowed range.
    var clamped: TimingSettings {
        TimingSettings(
            startConfirmation: startConfirmation.clamped(to: Self.startConfirmationRange),
            stopGrace: stopGrace.clamped(to: Self.stopGraceRange),
            resumeDelay: resumeDelay.clamped(to: Self.resumeDelayRange),
            silenceThresholdDB: silenceThresholdDB.clamped(to: Self.silenceThresholdRange)
        )
    }
}

extension AppConfiguration {
    /// The default configuration with the user's timings applied.
    init(timings: TimingSettings) {
        self.init()
        let timings = timings.clamped
        sourceStartConfirmation = timings.startConfirmation
        sourceStopGrace = timings.stopGrace
        debounceSeconds = timings.resumeDelay
        audibleThreshold = Float(pow(10, timings.silenceThresholdDB / 20))
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
