import Foundation

// MARK: - Configuration

/// Everything the engine works with. The values users can tune come from
/// `TimingSettings` (their defaults live there); the rest are fixed.
package struct AppConfiguration: Sendable {

    /// Seconds the music takes to fade out before pausing; 0 pauses at once.
    package var fadeOutDuration: TimeInterval
    /// Seconds the music takes to fade back in after resuming; 0 resumes at
    /// full volume.
    package var fadeInDuration: TimeInterval

    /// Peak sample value (linear, 0…1) above which a metered process counts as
    /// audible. Paused players emit digital silence (0).
    package var audibleThreshold: Float

    /// A source must stay audible this long before it counts as playing.
    /// Filters out short sounds apps play themselves (chat tones and the like);
    /// system notification and alert sounds are excluded by process instead.
    package var sourceStartConfirmation: TimeInterval

    /// Inaudible gaps shorter than this do not restart the start confirmation.
    package var audibleGapTolerance: TimeInterval = 0.5

    /// A playing source must stay inaudible this long before it counts as
    /// stopped. Bridges gaps between tracks, videos and ads.
    package var sourceStopGrace: TimeInterval

    /// Monitor tick while another app has its audio running or a source is tracked.
    package var activeSampleInterval: TimeInterval = 0.25

    /// Monitor tick (and full process-list resync period) otherwise, also
    /// while the music player alone plays.
    package var idleSampleInterval: TimeInterval = 1.0

    /// The chosen music player's app: its audio is the music being protected.
    /// Set by the app; `nil` while no player is chosen.
    package var musicPlayerBundleID: String?

    /// System processes that must NEVER trigger a pause.
    package static let excludedBundleIDs: Set<String> = [
        "com.apple.coreaudiod",
        "com.apple.audio.SandboxHelper",
        "com.apple.audio.AudioComponentRegistrar",
        "com.apple.audio.UISoundsServer",
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
    package static let excludedBundleIDPrefixes: [String] = [
        "com.apple.audio.",
        "com.apple.CoreAudio",
    ]

    /// The fixed values, with the user's timings (clamped to their ranges).
    package init(timings: TimingSettings = .defaults) {
        let timings = timings.clamped
        sourceStartConfirmation = timings.startConfirmation
        sourceStopGrace = timings.stopGrace
        audibleThreshold = Float(pow(10, timings.silenceThresholdDB / 20))
        fadeOutDuration = timings.fadeOutDuration
        fadeInDuration = timings.fadeInDuration
    }

    /// True for the chosen music player's own app, or one of its helpers
    /// (e.g. `com.tidal.desktop.helper`, which plays TIDAL's sound). Other
    /// music players count like any other app.
    package func isMusicPlayer(_ bundleID: String) -> Bool {
        guard let musicPlayerBundleID else { return false }
        return bundleID == musicPlayerBundleID || bundleID.hasPrefix(musicPlayerBundleID + ".")
    }

    /// Returns true if the bundle ID should trigger pause/resume logic.
    package func isMediaSource(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        guard !isMusicPlayer(bundleID), !Self.excludedBundleIDs.contains(bundleID) else { return false }
        return !Self.excludedBundleIDPrefixes.contains(where: { bundleID.hasPrefix($0) })
    }
}
