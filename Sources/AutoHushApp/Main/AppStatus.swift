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
                          comment: "Settings → General, under the Auto-Pause switch; %@ says until when, e.g. “until 15:30”")
        }
    }

    /// The players to choose from, for the menu's players under its card.
    var playerOptions: [PlayerOption] = []
    /// The bundle ID of the chosen player; `nil` while none is chosen.
    var chosenPlayerID: String?
    /// The chosen player as the menu offers it; `nil` while none is chosen.
    var chosenPlayer: PlayerOption? {
        playerOptions.first { $0.bundleID == chosenPlayerID }
    }
    /// The music player AutoHush controls, e.g. "Spotify"; empty while none
    /// is chosen.
    var playerName: String { chosenPlayer?.name ?? "" }
    /// How far AutoHush has come learning to control the chosen player;
    /// `nil` for a player it controls without learning. The menu's card
    /// says whether it's learned; the steps show only in a window.
    var learning: LearningStatus?
    /// The chosen player learns its controls (a web app): they can be learned
    /// afresh, once learned (they may have been learned wrong) or before
    /// (the learning window was closed halfway).
    var canLearnControlsAgain: Bool { chosenPlayer != nil && learning != nil }
    /// A permission the chosen player needs is missing: the menu asks for it.
    var needsPermission: Bool {
        if case .needsPermission = health { return true }
        return false
    }
    private(set) var health: AppHealthState = .starting
    var playback: PlaybackState = .unknown
    var detection: DetectionMode = .pending
    var autoPause: AutoPause = .on
    /// Sources playing right now, ignored ones included.
    private(set) var activeSources: [AudioSource] = []
    var ignoredApps: [AudioSource] = []
    /// A newer release found by the update check, and how far along it is.
    var updateOffer: UpdateOffer?
    /// Why the player couldn't be controlled, while that's what the menu
    /// says: a start that failed with an error, or a pause that failed.
    var controlError: ControlError?
    /// The alert the info button after the card's line opens: what failed
    /// as its title, the cause in words, then as the log has it.
    var controlErrorAlert: (title: String, message: String)? {
        guard let controlError else { return nil }
        let title = playback == .pauseFailed && isReady
            ? String(localized: "Couldn't Pause \(playerName)",
                     comment: "Title of the alert that says why the media player refused to pause or failed to; %@ is the player")
            : String(localized: "Can't Control \(playerName)",
                     comment: "Title of the alert that says why the media player can't be controlled; %@ is the player")
        return (title, "\(controlError.text)\n\n\(controlError.detail)")
    }
    /// The user went to allow System Audio Recording during this launch.
    /// macOS applies it only from the next launch, so the menu then offers to
    /// reopen AutoHush instead of asking again.
    var awaitsReopenForAudioRecording = false

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

    /// The health's look until ready, the playback state's once ready.
    private var presentation: StatePresentation {
        health.presentation ?? playback.presentation(playing: pausingSources.map(\.name))
    }

    /// The card's title at the top of the menu: the chosen player, or
    /// AutoHush while none is chosen.
    var cardTitle: String { chosenPlayer?.name ?? "AutoHush" }

    /// Whether something keeps AutoHush from working: the status line says
    /// what, and the card shows it.
    var needsAttention: Bool {
        switch health {
        case .starting:                                          return false
        case .ready:                                             return playback == .pauseFailed && autoPause == .on
        case .needsPlayer, .degraded, .retrying, .needsPermission, .failed: return true
        }
    }

    var icon: MenuBarIcon { presentation.icon }
    var iconAccessibilityLabel: String { presentation.label }

    /// The menu bar icon is dimmed while auto-pause is off.
    var dimsIcon: Bool { isReady && autoPause != .on }

    /// The line under the card's title: what's happening.
    var statusLine: String {
        guard isReady else { return presentation.line }
        switch autoPause {
        case .off:
            return String(localized: "Auto-Pause is off", comment: "Status line at the top of the menu")
        case .snoozed(let until):
            return String(localized: "Auto-Pause is off \(until)",
                          comment: "Status line at the top of the menu; %@ says until when, e.g. “until 15:30”")
        case .on:
            return presentation.line
        }
    }

    /// A missing permission the user can grant; shown as a single menu item.
    var warning: Permission? {
        if case .needsPermission(let permission) = health { return permission }
        if isReady, detection == .unavailable { return .systemAudioRecording }
        return nil
    }

    /// Whether the warning's menu item reopens AutoHush rather than asking
    /// for the permission: see `awaitsReopenForAudioRecording`.
    var offersReopen: Bool {
        warning == .systemAudioRecording && awaitsReopenForAudioRecording
    }

    /// Whether the menu offers Retry: only after a failed start that nothing
    /// announces the end of. AutoHush tries again by itself then too, but
    /// waits up to a minute between tries.
    var canRetry: Bool {
        switch health {
        case .retrying, .failed:                                  return true
        case .starting, .ready, .needsPlayer, .degraded, .needsPermission: return false
        }
    }
}
