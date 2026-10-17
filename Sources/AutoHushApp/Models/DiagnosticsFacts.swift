import Foundation
import AutoHushKit

/// What the app knows besides the apps with sound, for Diagnostics: the
/// player, the permissions, AutoHush's settings and the Mac. The app
/// delegate gathers it; the report only words it.
struct DiagnosticsFacts: Equatable {
    /// The chosen player's version, when it's installed.
    var playerVersion: String?
    var playerCanFade: Bool
    /// What controlling the chosen player needs, and whether it's allowed
    /// (`nil`: not known until AutoHush has tried).
    var playerPermission: Permission?
    var playerPermissionGranted: Bool?
    /// Whether AutoHush has learned the chosen player's Play/Pause button;
    /// `nil` for a player it doesn't have to learn.
    var playerLearned: Bool?
    /// Whether the chosen player's windows on other Spaces can be reached
    /// (a private function); `nil` for a player that has no need to.
    var reachesOtherSpaces: Bool?
    /// Whether the chosen player's own words for Play and Pause could be
    /// read from its app; `nil` for a player that doesn't need them.
    var playerWordsRead: Bool?
    /// `nil` when macOS can't be asked.
    var audioRecording: AudioCapturePermission?
    var notificationsOff: Bool
    var detectionMethod: DetectionMethod
    var timings: TimingSettings = .defaults
    /// E.g. "0.6.1 (19)".
    var appVersion: String
    var launchAtLogin: Bool
    var checksForUpdates: Bool
    var automaticUpdates: AutomaticUpdates
    var lastUpdateCheck: Date?
    /// E.g. "27.0.1 (26A434)".
    var macOS: String
    /// "Apple silicon" or "Intel".
    var processor: String
    var now = Date()
}
