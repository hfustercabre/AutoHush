import Foundation
import AutoHushKit

/// The text of the Diagnostics alert (menu → hold ⌥ → Diagnostics…): every app
/// with its sound on and how AutoHush judges it, the detection in effect, and
/// the auto-pause and ignore settings.
enum DiagnosticsReport {
    static func text(activeAudio: [String], status: AppStatus, detectionMethod: DetectionMethod) -> String {
        [
            activeAudio.isEmpty ? "No foreign audio output currently detected." : activeAudio.joined(separator: "\n"),
            status.detection.statusLine + (detectionMethod == .audioLevels ? "" : " — AntiDot mode"),
            "Auto-pause: \(describe(status.autoPause))",
            "Ignored apps: \(status.ignoredApps.isEmpty ? "none" : status.ignoredApps.map(\.name).joined(separator: ", "))",
        ].joined(separator: "\n\n")
    }

    private static func describe(_ autoPause: AppStatus.AutoPause) -> String {
        switch autoPause {
        case .on:                 return "on"
        case .off:                return "off"
        case .snoozed(let until): return "off until \(until)"
        }
    }
}
