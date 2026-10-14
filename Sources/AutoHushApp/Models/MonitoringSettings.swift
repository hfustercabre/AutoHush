import Foundation
import OSLog
import AutoHushKit

/// What the chosen player's monitoring follows from the user's settings.
struct MonitoringSettings: Equatable {
    /// Auto-Pause is on now: neither turned off nor snoozed.
    var autoPause: Bool
    /// The bundle IDs of the apps the user ignores.
    var ignored: Set<String>
    var timings: TimingSettings
    var detection: DetectionMethod
}
