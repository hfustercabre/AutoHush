import Foundation
import AutoHushKit

/// Everything the menu bar shows, as plain values. `StatusMenuController`
/// renders it; keeping the rules here makes them testable without AppKit.
struct AppStatus: Equatable {
    /// Whether AutoHush pauses the music, as the menu and Settings show it.
    enum AutoPause: Equatable {
        case on
        case off
        /// Off until a moment, described with its preposition so that each
        /// language can place it: "until 15:30", "until tomorrow 8:00".
        case snoozed(String)

        init(_ setting: AutoPauseSetting, now: Date) {
            if !setting.isEnabled {
                self = .off
            } else if let end = setting.snoozedUntil {
                self = .snoozed(AutoPauseSnooze.describeEnd(end, now: now))
            } else {
                self = .on
            }
        }

        /// When the description of a snooze ending at `end` next changes: at
        /// the end, or at midnight before it ("until tomorrow 8:00" becomes
        /// "until 8:00").
        static func nextChange(snoozedUntil end: Date, now: Date, calendar: Calendar = .current) -> Date {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return end }
            return min(end, calendar.startOfDay(for: tomorrow))
        }

        /// The note under the switch in Settings, e.g. "Turned off until 15:30."
        var settingsNote: String? {
            guard case .snoozed(let until) = self else { return nil }
            return String(localized: "Turned off \(until).",
                          comment: "Settings, under Auto-Pause Music; %@ says until when, e.g. “until 15:30”")
        }
    }

    /// The music player AutoHush controls, e.g. "Spotify".
    var playerName = ""
    private(set) var health: AppHealthState = .starting
    var playback: PlaybackState = .unknown
    var detection: DetectionMode = .pending
    var autoPause: AutoPause = .on
    /// Sources playing right now, ignored ones included.
    private(set) var activeSources: [AudioSource] = []
    var ignoredApps: [AudioSource] = []
    /// A newer release found by the update check.
    var availableUpdate: AppRelease?

    /// Leaving `.ready` clears the active sources: nothing is monitored then.
    mutating func setHealth(_ health: AppHealthState) {
        self.health = health
        if health != .ready { activeSources = [] }
    }

    mutating func setActiveSources(_ sources: [AudioSource]) {
        activeSources = sources.sortedByName()
    }

    func isIgnored(_ id: String) -> Bool {
        ignoredApps.contains { $0.id == id }
    }

    /// Playing sources that pause the music.
    var pausingSources: [AudioSource] {
        activeSources.filter { !isIgnored($0.id) }
    }

    // MARK: - Presentation

    var isReady: Bool { health == .ready }

    /// The playback state's look once ready, the health's until then.
    private var presentation: StatePresentation {
        isReady ? playback.presentation : health.presentation
    }

    var icon: MenuBarIcon { presentation.icon }
    var iconAccessibilityLabel: String { presentation.label }

    /// The menu bar icon is dimmed while auto-pause is off.
    var dimsIcon: Bool { isReady && autoPause != .on }

    var statusLine: String {
        guard isReady else { return presentation.line }
        switch autoPause {
        case .off:
            return String(localized: "Auto-pause is off", comment: "Status line at the top of the menu")
        case .snoozed(let until):
            return String(localized: "Auto-pause is off \(until)",
                          comment: "Status line at the top of the menu; %@ says until when, e.g. “until 15:30”")
        case .on:
            guard playback == .pausedByMonitor, !pausingSources.isEmpty else { return presentation.line }
            return String(localized: "Music paused — \(Self.describePlaying(pausingSources.map(\.name)))",
                          comment: "Status line at the top of the menu; %@ says which apps play, e.g. “VLC is playing”")
        }
    }

    /// A missing permission the user can grant; shown as a single menu item.
    var warning: Permission? {
        if case .needsPermission = health { return .automation(player: playerName) }
        if isReady, detection == .unavailable { return .systemAudioRecording }
        return nil
    }

    var showsRetry: Bool {
        switch health {
        case .starting, .ready:                     return false
        case .degraded, .needsPermission, .failed:  return true
        }
    }

    /// "VLC is playing", "VLC and Safari are playing", "VLC and 2 other apps are playing".
    static func describePlaying(_ names: [String]) -> String {
        switch names.count {
        case 0:
            return String(localized: "another app is playing", comment: "Completes “Music paused — %@”")
        case 1:
            return String(localized: "\(names[0]) is playing", comment: "Completes “Music paused — %@”; %@ is an app")
        case 2:
            return String(localized: "\(names[0]) and \(names[1]) are playing",
                          comment: "Completes “Music paused — %@”; two apps")
        default:
            return String(localized: "\(names[0]) and \(names.count - 1) other apps are playing",
                          comment: "Completes “Music paused — %@”; an app, then how many others (2 or more)")
        }
    }
}
