import Foundation

/// A macOS permission AutoHush needs, and where the user grants it. (The
/// app has the menu text that leads there.)
///
/// - Automation: control the music player (pause, play, volume). Each player
///   checks it in `MusicPlayer.verifyControlAccess()`.
/// - System Audio Recording: measure how loud other apps are (not used in
///   AntiDot mode). Checked by `AudioCapturePermissionChecking`.
package enum Permission: Equatable, Sendable {
    case automation(player: String)
    case systemAudioRecording

    /// Where in System Settings it is granted.
    package var settingsPane: SystemSettingsPane {
        switch self {
        case .automation:           return .automation
        case .systemAudioRecording: return .audioCapture
        }
    }
}
