import Foundation
import AutoHushKit

/// Everything the menu bar shows, as plain values. `StatusMenuController`
/// renders it; keeping the rules here makes them testable without AppKit.
struct AppStatus: Equatable {
    /// Whether AutoHush pauses the music, as the menu and Settings show it.
    enum AutoPause: Equatable {
        case on
        case off
        /// Off until the described moment, e.g. "15:30" or "tomorrow 8:00".
        case snoozed(until: String)

        init(_ setting: AutoPauseSetting, now: Date) {
            if !setting.isEnabled {
                self = .off
            } else if let end = setting.snoozedUntil {
                self = .snoozed(until: AutoPauseSnooze.describeEnd(end, now: now))
            } else {
                self = .on
            }
        }

        /// The note under the switch in Settings, e.g. "Turned off until 15:30."
        var settingsNote: String? {
            guard case .snoozed(let until) = self else { return nil }
            return "Turned off until \(until)."
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
        case .off:                     return "Auto-pause is off"
        case .snoozed(let until):      return "Auto-pause is off until \(until)"
        case .on:
            guard playback == .pausedByMonitor, !pausingSources.isEmpty else { return presentation.line }
            return "Music paused — \(Self.describePlaying(pausingSources.map(\.name)))"
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
        case 0:  return "another app is playing"
        case 1:  return "\(names[0]) is playing"
        case 2:  return "\(names[0]) and \(names[1]) are playing"
        default: return "\(names[0]) and \(names.count - 1) other apps are playing"
        }
    }
}
