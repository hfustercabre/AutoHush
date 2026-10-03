import Foundation

// MARK: - Configuration

package struct AppConfiguration: Sendable {

    /// Seconds to wait after all foreign audio stops before resuming the music.
    package var debounceSeconds: TimeInterval = 0.2

    /// Seconds the music takes to fade out before pausing; 0 pauses at once.
    package var fadeOutDuration: TimeInterval = 1
    /// Seconds the music takes to fade back in after resuming; 0 resumes at
    /// full volume.
    package var fadeInDuration: TimeInterval = 2

    /// Peak sample value (linear, 0…1) above which a metered process counts as
    /// audible. 0.001 ≈ -60 dBFS: paused players emit digital silence (0).
    package var audibleThreshold: Float = 0.001

    /// A source must stay audible this long before it counts as playing.
    /// Filters out short sounds apps play themselves (chat tones and the like);
    /// system notification and alert sounds are excluded by process instead.
    package var sourceStartConfirmation: TimeInterval = 0.5

    /// Inaudible gaps shorter than this do not restart the start confirmation.
    package var audibleGapTolerance: TimeInterval = 0.5

    /// A playing source must stay inaudible this long before it counts as
    /// stopped. Bridges gaps between tracks, videos and ads.
    package var sourceStopGrace: TimeInterval = 2.0

    /// Monitor tick while any audio stream is open or a source is tracked.
    package var activeSampleInterval: TimeInterval = 0.25

    /// Monitor tick (and full process-list resync period) while idle.
    package var idleSampleInterval: TimeInterval = 1.0

    /// The music players' own apps: their audio is the music being protected.
    /// Set by the app from its supported players.
    package var musicPlayerBundleIDs: Set<String> = []

    /// System processes that must NEVER trigger a pause.
    package let excludedBundleIDs: Set<String> = [
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
    package let excludedBundleIDPrefixes: [String] = [
        "com.apple.audio.",
        "com.apple.CoreAudio",
    ]

    /// Returns true if the bundle ID should trigger pause/resume logic.
    package func isMediaSource(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        guard !musicPlayerBundleIDs.contains(bundleID), !excludedBundleIDs.contains(bundleID) else { return false }
        return !excludedBundleIDPrefixes.contains(where: { bundleID.hasPrefix($0) })
    }
}
