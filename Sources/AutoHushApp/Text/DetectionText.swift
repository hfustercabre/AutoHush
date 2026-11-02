import SwiftUI
import AutoHushKit

/// How AutoHush tells that other apps play, in words: Behavior's Modes
/// card, Fine-Tuning's Detection card, Diagnostics' heading, and why
/// AntiDot mode can't be turned on. Detection was a page of its own until W1
/// and Behavior's end until S5d + S5a (the user, 2026-10-25).
enum DetectionText {
    /// Over how AutoHush tells that other apps play: Fine-Tuning's card,
    /// Behavior's row to it, and Diagnostics' heading.
    static var title: String {
        String(localized: "Detection", comment: "Settings → Fine-Tuning's card and Behavior's row to it (under AntiDot mode), and Diagnostics' heading: how AutoHush tells that other apps play (AntiDot mode's ways and the silence threshold)")
    }

    /// Over AntiDot mode, in Settings → Behavior.
    static var modesTitle: Text {
        Text("Modes", comment: "Settings → Behavior: heading over AntiDot mode")
    }

    /// The title over AntiDot mode's ways, which VoiceOver hears with them.
    static var detectByTitle: String {
        String(localized: "Detect playing apps by", comment: "Settings → Fine-Tuning, Detection: lead-in to AntiDot mode's ways of detecting playing apps")
    }
}

/// The detection choices as Settings and Diagnostics describe them.
extension DetectionMethod {
    /// AntiDot mode's ways, in the order Settings offers them.
    static let antiDotWays: [DetectionMethod] = [.playbackSignals, .openStreams]

    var title: String {
        switch self {
        case .audioLevels:
            return String(localized: "Measure audio levels", comment: "Settings: a way to detect playing apps")
        case .playbackSignals:
            return String(localized: "What apps tell macOS", comment: "Settings, AntiDot mode: a way to detect playing apps")
        case .openStreams:
            return String(localized: "Any app with sound on",
                          comment: "Settings, AntiDot mode, and Diagnostics' “Detecting by”: a way to detect playing apps, where any app whose sound output is on counts as playing, even when paused")
        }
    }

    /// One sentence under the ways in Settings → Fine-Tuning (T10b, the
    /// user's pick, 2026-11-02).
    var summary: String {
        switch self {
        case .audioLevels:
            return String(localized: "Most accurate; macOS shows its purple dot.",
                          comment: "Settings → Fine-Tuning, Detection, under the ways of detecting playing apps: what measuring audio levels does (AntiDot mode off); the purple dot is macOS's recording indicator")
        case .playbackSignals:
            return String(localized: "Apps count while they tell macOS they play.",
                          comment: "Settings → Fine-Tuning, Detection, under the ways of detecting playing apps: how “What apps tell macOS” works")
        case .openStreams:
            return String(localized: "Paused apps count too; short sounds don’t.",
                          comment: "Settings → Fine-Tuning, Detection, under the ways of detecting playing apps: how “Any app with sound on” works (an app with its sound on counts even when paused; a sound shorter than 2 seconds doesn't pause the player)")
        }
    }
}
