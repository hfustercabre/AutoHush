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

    /// Under the AntiDot mode switch while it's off and dimmed: as the menu
    /// says why the player couldn't be controlled in AntiDot mode.
    static func unavailableNote(_ player: String, mutes: Bool = true) -> String {
        mutes ? AntiDotText.onlyMuted(player) : AntiDotText.onlyHeard(player)
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
            return String(localized: "Open audio streams only",
                          comment: "Settings, AntiDot mode: a way to detect playing apps")
        }
    }

    var summary: String {
        switch self {
        case .audioLevels:
            return String(localized: "Most accurate: a paused video stops counting once it’s silent. macOS shows its purple recording indicator while AutoHush measures.",
                          comment: "Settings → Fine-Tuning, Detection, under the ways of detecting playing apps: what measuring audio levels does")
        case .playbackSignals:
            return String(localized: "Apps count as playing while they tell macOS so; apps that never do, while their audio is open. Sounds without video under 3 seconds don’t pause your player.",
                          comment: "Settings → Fine-Tuning, Detection, under the ways of detecting playing apps: how “What apps tell macOS” works")
        case .openStreams:
            return String(localized: "Any app with its audio open counts as playing, even when paused. It must stay open 2 seconds before your player pauses, so notification sounds don’t interrupt it.",
                          comment: "Settings → Fine-Tuning, Detection, under the ways of detecting playing apps: how “Open audio streams only” works")
        }
    }
}
