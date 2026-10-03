import Foundation
import AutoHushKit

/// The text of the Diagnostics alert (menu → hold ⌥ → Diagnostics…): every app
/// with its sound on and how AutoHush judges it, the detection in effect, and
/// the auto-pause and ignore settings.
enum DiagnosticsReport {
    static func text(activeAudio: [ActiveAudioReport.Entry], status: AppStatus, detectionMethod: DetectionMethod) -> String {
        [
            activeAudio.isEmpty
                ? String(localized: "No foreign audio output currently detected.", comment: "Diagnostics")
                : activeAudio.map(line(for:)).joined(separator: "\n"),
            detectionMethod == .audioLevels
                ? status.detection.statusLine
                : String(localized: "\(status.detection.statusLine) — AntiDot mode",
                         comment: "Diagnostics: the detection in effect, then that AntiDot mode is on"),
            describe(status.autoPause),
            describe(ignoredApps: status.ignoredApps.map(\.name)),
        ].joined(separator: "\n\n")
    }

    /// One app's line, e.g. "Google Chrome (com.google.Chrome) — playing (-23 dBFS)".
    static func line(for entry: ActiveAudioReport.Entry) -> String {
        let app = entry.name.map {
            String(localized: "\($0) (\(entry.id))", comment: "Diagnostics: an app's name, then its bundle ID")
        } ?? entry.id
        let state = describe(entry.state, isIgnored: entry.isIgnored)
        guard let evidence = entry.evidence.map(describe) else {
            return String(localized: "\(app) — \(state)", comment: "Diagnostics: an app, then how AutoHush judges it")
        }
        return String(localized: "\(app) — \(state) (\(evidence))",
                      comment: "Diagnostics: an app, how AutoHush judges it, and what that rests on")
    }

    /// How AutoHush judges an app.
    private static func describe(_ state: ActiveAudioReport.Entry.State, isIgnored: Bool) -> String {
        switch (state, isIgnored) {
        case (.playing, false):
            return String(localized: "playing", comment: "Diagnostics: how AutoHush judges an app")
        case (.playing, true):
            return String(localized: "playing, ignored", comment: "Diagnostics: how AutoHush judges an app")
        case (.starting, false):
            return String(localized: "starting", comment: "Diagnostics: an app audible too briefly to count yet")
        case (.starting, true):
            return String(localized: "starting, ignored", comment: "Diagnostics: an app audible too briefly to count yet")
        case (.silent, false):
            return String(localized: "output open, silent", comment: "Diagnostics: how AutoHush judges an app")
        case (.silent, true):
            return String(localized: "output open, silent, ignored", comment: "Diagnostics: how AutoHush judges an app")
        }
    }

    /// What the judgement rests on.
    private static func describe(_ evidence: ActiveAudioReport.Entry.Evidence) -> String {
        switch evidence {
        case .announcing:
            return String(localized: "tells macOS it is playing",
                          comment: "Diagnostics, AntiDot mode: why an app counts as playing")
        case .notAnnouncing:
            return String(localized: "not telling macOS it is playing",
                          comment: "Diagnostics, AntiDot mode: why an app counts as paused")
        case .level(let peak) where peak > 0:
            return String(localized: "\(Int((20 * log10(peak)).rounded())) dBFS",
                          comment: "Diagnostics: an app's loudest level, in decibels")
        case .level:
            return String(localized: "silence", comment: "Diagnostics: the level of an app that makes no sound")
        }
    }

    private static func describe(_ autoPause: AppStatus.AutoPause) -> String {
        switch autoPause {
        case .on:
            return String(localized: "Auto-pause: on", comment: "Diagnostics")
        case .off:
            return String(localized: "Auto-pause: off", comment: "Diagnostics")
        case .snoozed(let until):
            return String(localized: "Auto-pause: off \(until)",
                          comment: "Diagnostics; %@ says until when, e.g. “until 15:30”")
        }
    }

    private static func describe(ignoredApps names: [String]) -> String {
        guard !names.isEmpty else { return String(localized: "Ignored apps: none", comment: "Diagnostics") }
        return String(localized: "Ignored apps: \(names.formatted(.list(type: .and, width: .narrow)))",
                      comment: "Diagnostics; %@ lists app names")
    }
}
