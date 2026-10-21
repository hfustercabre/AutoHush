import Foundation

// MARK: - Configuration

/// Everything the engine works with. The values users can tune come from
/// `TimingSettings` (their defaults live there); the rest are fixed.
package struct AppConfiguration: Sendable {

    /// Seconds the music takes to fade out before pausing; 0 pauses at once.
    var fadeOutDuration: TimeInterval
    /// Seconds the music takes to fade back in after resuming; 0 resumes at
    /// full volume.
    var fadeInDuration: TimeInterval

    /// Peak sample value (linear, 0…1) above which a metered process counts as
    /// audible. Paused players emit digital silence (0).
    var audibleThreshold: Float

    /// A source must stay audible this long before it counts as playing.
    /// Filters out short sounds apps play themselves (chat tones and the like);
    /// system notification and alert sounds are excluded by process instead.
    var sourceStartConfirmation: TimeInterval

    /// AntiDot mode ("What apps tell macOS"): the least an app showing no
    /// video must play before it counts as playing. Chromium-based apps tell
    /// macOS they play for about 2.5 s after even a short sound (measured), so
    /// their notification sounds would otherwise pause the music.
    var minimumStartWithoutVideo: TimeInterval = 3

    /// How long an app showing no video must play in AntiDot mode: the user's
    /// start confirmation, but at least `minimumStartWithoutVideo`.
    package var startConfirmationWithoutVideo: TimeInterval {
        max(sourceStartConfirmation, minimumStartWithoutVideo)
    }

    /// "Open audio streams only": the least any app must keep its audio open
    /// before it counts as playing. That method can't tell video, and an
    /// app's chat tone keeps its stream open about a second (measured on
    /// macOS 14.4).
    var minimumStartWithOpenStreams: TimeInterval = 2

    /// How long any app must keep its audio open with open streams only: the
    /// user's start confirmation, but at least `minimumStartWithOpenStreams`.
    package var startConfirmationWithOpenStreams: TimeInterval {
        max(sourceStartConfirmation, minimumStartWithOpenStreams)
    }

    /// Whether the music resumes with the Mac's volume lowered to the
    /// quieter apps' level (Settings → Advanced; `ResumeLevel`).
    var levelsMusic: Bool
    /// The most the volume is lowered, in dB, and the least worth doing
    /// (Settings → Advanced's sliders).
    var levelingMaxCutDB: Float
    var levelingMinCutDB: Float
    /// Whether an app turning on its microphone pauses the music, sound or
    /// not (Settings → Calls): it counts as playing once its microphone
    /// has been on for `microphoneStartConfirmation`, which apps that only
    /// touch it as they open (or test it) don't reach, and as in a call.
    var pausesForMicrophone: Bool
    var microphoneStartConfirmation: TimeInterval = 1
    /// Whether the music stays paused after a call during AutoHush's pause
    /// (Settings → Calls).
    var staysPausedAfterCalls: Bool

    /// Inaudible gaps shorter than this do not restart the start confirmation.
    var audibleGapTolerance: TimeInterval = 0.5

    /// A playing source must stay inaudible this long before it counts as
    /// stopped. Bridges gaps between tracks, videos and ads.
    var sourceStopGrace: TimeInterval

    /// Monitor tick while another app has its audio running or a source is tracked.
    package var activeSampleInterval: TimeInterval = 0.25

    /// Monitor tick (and full process-list resync period) otherwise, also
    /// while the media player alone plays.
    package var idleSampleInterval: TimeInterval = 1.0

    /// The chosen media player's app: its audio is the music being protected.
    /// Set by the app; `nil` while no player is chosen.
    package var musicPlayerBundleID: String?

    /// System processes that must NEVER trigger a pause.
    static let excludedBundleIDs: Set<String> = [
        "com.apple.coreaudiod",
        "com.apple.systemsound",
        // Plays notification banner sounds, alert beeps and system sound
        // effects on behalf of every app (measured on macOS 27); it reports
        // this bare name as its bundle ID.
        "systemsoundserverd",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.springboard",
    ]

    /// Bundle ID prefixes that indicate system/infrastructure processes to exclude.
    static let excludedBundleIDPrefixes: [String] = [
        "com.apple.audio.",
        "com.apple.CoreAudio",
    ]

    /// The fixed values, with the user's timings (clamped to their ranges).
    /// With fades off, both fades last 0 s: the music pauses and resumes at once.
    package init(timings: TimingSettings = .defaults) {
        let timings = timings.clamped
        sourceStartConfirmation = timings.startConfirmation
        sourceStopGrace = timings.stopGrace
        audibleThreshold = Float(pow(10, timings.silenceThresholdDB / 20))
        fadeOutDuration = timings.fadesEnabled ? timings.fadeOutDuration : 0
        fadeInDuration = timings.fadesEnabled ? timings.fadeInDuration : 0
        levelsMusic = timings.levelsMusic
        levelingMaxCutDB = Float(timings.levelingMaxCutDB)
        levelingMinCutDB = Float(timings.levelingMinCutDB)
        pausesForMicrophone = timings.pausesForMicrophone
        staysPausedAfterCalls = timings.staysPausedAfterCalls
    }

    /// True for the chosen media player's own app, or one of its helpers
    /// (e.g. `<its bundle ID>.helper`, which plays some players' sound). Other
    /// media players count like any other app.
    func isMusicPlayer(_ bundleID: String) -> Bool {
        guard let musicPlayerBundleID else { return false }
        return bundleID == musicPlayerBundleID || bundleID.hasPrefix(musicPlayerBundleID + ".")
    }

    /// Returns true if the bundle ID should trigger pause/resume logic.
    func isMediaSource(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        guard !isMusicPlayer(bundleID), !Self.excludedBundleIDs.contains(bundleID) else { return false }
        return !Self.excludedBundleIDPrefixes.contains(where: { bundleID.hasPrefix($0) })
    }
}
