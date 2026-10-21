import Foundation

/// The timings users can tune in Settings → Detection and → Fades, and the
/// switches of Settings → Calls and → Advanced.
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
    /// Whether the music resumes with the Mac's volume lowered to the level
    /// of the quieter apps it was paused for (calls aside), until its next
    /// pause.
    package var levelsMusic: Bool
    /// Whether an app turning on its microphone pauses the music, before it
    /// plays any sound (a call starting silent).
    package var pausesForMicrophone: Bool
    /// Whether the music stays paused when the apps stop after a call came
    /// during AutoHush's pause.
    package var staysPausedAfterCalls: Bool

    init(
        startConfirmation: TimeInterval = 0.5,
        stopGrace: TimeInterval = 2.0,
        silenceThresholdDB: Double = -60,
        fadeOutDuration: TimeInterval = 1,
        fadeInDuration: TimeInterval = 2,
        fadesEnabled: Bool = true,
        levelsMusic: Bool = false,
        pausesForMicrophone: Bool = false,
        staysPausedAfterCalls: Bool = false
    ) {
        self.startConfirmation = startConfirmation
        self.stopGrace = stopGrace
        self.silenceThresholdDB = silenceThresholdDB
        self.fadeOutDuration = fadeOutDuration
        self.fadeInDuration = fadeInDuration
        self.fadesEnabled = fadesEnabled
        self.levelsMusic = levelsMusic
        self.pausesForMicrophone = pausesForMicrophone
        self.staysPausedAfterCalls = staysPausedAfterCalls
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
            fadesEnabled: fadesEnabled,
            levelsMusic: levelsMusic,
            pausesForMicrophone: pausesForMicrophone,
            staysPausedAfterCalls: staysPausedAfterCalls
        )
    }
}
