import Foundation
import AutoHushKit

/// Everything the menu and the windows show, as plain values, kept in
/// `AppState`. `StatusMenuController` renders it, and `SettingsModel` reads
/// it for the windows; keeping the rules here makes them testable without
/// AppKit.
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
    /// The media player AutoHush controls, e.g. "Spotify"; empty while none
    /// is chosen.
    var playerName: String { chosenPlayer?.name ?? "" }
    /// How far AutoHush has come learning to control the chosen player;
    /// `nil` for a player it controls without learning. The menu's card
    /// says whether it's learned; the steps show only in a window.
    var learning: LearningStatus?
    /// Where the pause stands while it learns, for the windows that show
    /// the steps.
    var learningPause = LearningPause()
    /// The chosen player learns its controls (a web app): they can be learned
    /// afresh, once learned (they may have been learned wrong) or before
    /// (the learning window was closed halfway).
    var canLearnControlsAgain: Bool { chosenPlayer != nil && learning != nil }
    private(set) var health: AppHealthState = .starting
    var playback: PlaybackState = .unknown
    var detection: DetectionMode = .pending
    var autoPause: AutoPause = .on
    /// Sources playing right now, ignored ones included.
    private(set) var activeSources: [AudioSource] = []
    /// The sources that stopped playing, the most recent first, each with
    /// when: the menu's "Recently Played" (`recentSources(at:)`).
    private(set) var stoppedSources: [StoppedSource] = []
    struct StoppedSource: Equatable {
        let source: AudioSource
        let stoppedAt: Date
    }
    /// How long an app that stopped playing stays under "Recently Played"
    /// (the user, 2026-10-16; 30 minutes from 2026-10-17, was 5).
    static let recentlyPlayedFor: TimeInterval = 30 * 60
    /// The apps that played sound, the most recent first, and the ones the
    /// user ignores; never the chosen player, which doesn't pause itself.
    var seenApps: [AudioSource] = []
    var ignoredApps: [AudioSource] = []
    /// A newer release found by the update check, and how far along it is.
    var updateOffer: UpdateOffer?
    /// Why the player couldn't be controlled, while that's what the menu
    /// says: a start that failed with an error, or a pause that failed.
    var controlError: ControlError?
    /// Why the last resume was given up (no answer, or its play failed):
    /// the card says "Couldn't resume" with Try Again (the user, 2026-10-25).
    var resumeError: ControlError?
    /// The card says the resume was given up: nothing else about the
    /// player is more pressing (no pause under way or failed, no reopening).
    var showsResumeFailure: Bool {
        resumeError != nil && isReady && !playerNeedsReopen && playback != .pausedByMonitor && playback != .pauseFailed
    }
    /// The alert the info button after the card's line opens: what failed
    /// as its title, the cause in words, then, unless AutoHush speaks
    /// English, as the log has it, for a bug report (E1, the user's pick,
    /// 2026-10-26: in English it said the same twice).
    func controlErrorAlert(inEnglish: Bool = AppStatus.speaksEnglish) -> (title: String, message: String)? {
        func message(_ error: ControlError) -> String { inEnglish ? error.text : "\(error.text)\n\n\(error.detail)" }
        if showsResumeFailure, let resumeError {
            return (String(localized: "Couldn’t Resume \(playerName)",
                           comment: "Title of the alert that says why AutoHush couldn't resume the media player (it didn't answer, or its play failed); %@ is the player"),
                    message(resumeError))
        }
        guard let controlError else { return nil }
        let title = playback == .pauseFailed && isReady
            ? String(localized: "Couldn’t Pause \(playerName)",
                     comment: "Title of the alert that says why the media player refused to pause or failed to; %@ is the player")
            : String(localized: "Can’t Control \(playerName)",
                     comment: "Title of the alert that says why the media player can't be controlled; %@ is the player")
        return (title, message(controlError))
    }

    /// AutoHush runs in English, the language of its log.
    nonisolated static var speaksEnglish: Bool {
        (Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("en")
    }
    /// What the info button's alert is about: the given-up resume while the
    /// card says so, else why the player couldn't be controlled.
    var alertError: ControlError? { showsResumeFailure ? resumeError : controlError }
    /// The user went to allow System Audio Recording during this launch.
    /// macOS applies it only from the next launch, so the menu then offers to
    /// reopen AutoHush instead of asking again.
    var awaitsReopenForAudioRecording = false
    /// The chosen player runs without what it needs to be controlled
    /// wherever its window is (`MusicPlayer.needsReopen`): the card says so,
    /// with a button that reopens it.
    var playerNeedsReopen = false
    /// The chosen player is muted instead of paused (`PlayerOption.pausesByMuting`):
    /// the card says "Muted", with Unmute.
    var playerMutes: Bool { chosenPlayer?.pausesByMuting ?? false }
    /// Add an App's check runs: AutoHush keeps the player it paused paused
    /// until the check ends (`AppDelegate.holdsPlayerForCheck`).
    var playerHeldForCheck = false
    /// The player is muted in place of AutoHush's pause (one that didn't
    /// take, a start by itself, or a refused one): shown as muted, as an app
    /// that's only muted is.
    var playerMutedInstead = false
    /// The player is muted now rather than paused: one that can only be
    /// muted, or one muted in place of AutoHush's pause while it holds it.
    /// The apps that interrupt it then say "Mutes your player" (the menu's
    /// Playing Now, Settings → Sound Sources), as the card says "Muted".
    var mutesNow: Bool { playerMutes || (playerMutedInstead && playback == .pausedByMonitor) }
    /// Only the player's sound tells how it is (`PlayerOption.needsAudioLevels`).
    var playerNeedsLevels: Bool { chosenPlayer?.needsAudioLevels ?? false }

    /// Leaving `.ready` clears the active sources: nothing is monitored then.
    /// They join the stopped ones, as when they stop (another player chosen,
    /// the player quit), so Recently Played lists them.
    mutating func setHealth(_ health: AppHealthState, now: Date = Date()) {
        self.health = health
        if health != .ready { setActiveSources([], now: now) }
    }

    /// An app that leaves them joins the stopped ones; one playing again
    /// leaves those.
    mutating func setActiveSources(_ sources: [AudioSource], now: Date = Date()) {
        let playing = Set(sources.map(\.id))
        let stopped = activeSources.filter { !playing.contains($0.id) }
        let leaving = playing.union(stopped.map(\.id))
        stoppedSources = stopped.map { StoppedSource(source: $0, stoppedAt: now) }
            + stoppedSources.filter { !leaving.contains($0.source.id) && now.timeIntervalSince($0.stoppedAt) < Self.recentlyPlayedFor }
        activeSources = sources.sortedByName()
    }

    /// The apps that played in the last 30 minutes and play no more, the
    /// most recent first, four at most (the user, 2026-10-18: a busy day
    /// made the menu long); never the chosen player, which doesn't pause
    /// itself (as `seenApps`): its switch would only store it as ignored.
    func recentSources(at now: Date = Date()) -> [AudioSource] {
        Array(stoppedSources.filter { $0.source.id != chosenPlayerID && now.timeIntervalSince($0.stoppedAt) < Self.recentlyPlayedFor }
            .map(\.source)
            .prefix(Self.recentlyPlayedMax))
    }

    /// How many apps Recently Played lists at most.
    static let recentlyPlayedMax = 4

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
        health.presentation ?? (playerNeedsReopen ? .needingAttention(Self.needsReopenLine(playerName))
            : showsResumeFailure ? .needingAttention(Self.resumeFailedLine(playerName))
            : mutesNow && playback == .pausedByMonitor ? .muted(playing: pausingSources.map(\.name), microphone: onlyMicrophone)
            : playerHeldForCheck && playback == .pausedByMonitor ? .heldForCheck
            : playback.presentation(playing: pausingSources.map(\.name), microphone: onlyMicrophone))
    }

    /// The one app that pauses the music counts only for its microphone.
    private var onlyMicrophone: Bool {
        pausingSources.count == 1 && pausingSources[0].isMicrophoneOnly
    }

    /// The card offers Unmute: the player is muted for other apps (one that
    /// can only be muted, or one muted in place of its pause: the user,
    /// 2026-10-25).
    var offersUnmute: Bool { isReady && mutesNow && playback == .pausedByMonitor }

    /// The status line once a resume was given up.
    static func resumeFailedLine(_ player: String) -> String {
        String(localized: "Couldn’t resume — \(player) didn’t answer",
               comment: "Status line at the top of the menu (orange, with an info button and Try Again under it) and on Settings → General's player card: AutoHush tried to resume the media player once the other apps stopped, and it didn't answer (or its play failed); %@ is the player")
    }

    /// The status line while the player needs reopening.
    static func needsReopenLine(_ player: String) -> String {
        String(localized: "\(player) needs reopening",
               comment: "Status line: the media player (an app added through a check) was opened without an option it needs, so AutoHush can pause it only while its window can be seen; a button under it reopens it; %@ is the player")
    }

    /// The chip under `needsReopenLine` in the menu's card and on Settings →
    /// General's player card: the line names the player, so it doesn't.
    static var reopenPlayerTitle: String {
        String(localized: "Reopen",
               comment: "Button in the menu's card and on Settings → General's player card, under the status line that says the media player needs reopening (“Deezer needs reopening”): quits it (an app added with Add an App) and opens it again with the option it needs")
    }

    /// The chip under the status line in the menu's card and on Settings →
    /// General's player card while the player is muted (`offersUnmute`).
    static var unmuteTitle: String {
        String(localized: "Unmute",
               comment: "Button in the menu's card and on Settings → General's player card, under the status line, while the media player (one that can only be muted) is muted for another app: it's heard again until the other apps stop")
    }

    /// The card's title at the top of the menu: the chosen player, or
    /// AutoHush while none is chosen.
    var cardTitle: String { chosenPlayer?.name ?? "AutoHush" }

    /// Whether something keeps AutoHush from working: the status line says
    /// what, and the card shows it.
    var needsAttention: Bool {
        switch health {
        case .starting, .playerClosed:                           return false
        case .ready:                                             return playerNeedsReopen || (playback == .pauseFailed && autoPause == .on)
                                                                    || showsResumeFailure
        case .needsPlayer, .degraded, .retrying, .needsPermission, .failed: return true
        }
    }

    var icon: MenuBarIcon { presentation.icon }
    /// The icon shows the update badge while an update waits: from when it's
    /// found until it's installed, as long as the menu offers it.
    var iconShowsUpdate: Bool { updateOffer != nil }
    /// While Auto-Pause is off, the icon is dimmed: VoiceOver says the
    /// status line, which says so ("AutoHush: Auto-Pause is off"). The
    /// update badge adds that an update is available.
    var iconAccessibilityLabel: String {
        let label = isReady && autoPause != .on ? StatePresentation.iconLabel(statusLine) : presentation.label
        guard iconShowsUpdate else { return label }
        return Self.withUpdate(label)
    }

    /// `label` with "update available" after it, for VoiceOver: the menu bar
    /// icon's and the menu's Updates button while an update waits.
    static func withUpdate(_ label: String) -> String {
        String(localized: "\(label), update available",
               comment: "VoiceOver label of the menu bar icon, and of the menu's Updates button, while an update waits; %@ is its usual label, e.g. “AutoHush: Spotify isn’t running” or “Updates”")
    }

    /// The menu bar icon is dimmed while auto-pause is off.
    var dimsIcon: Bool { isReady && autoPause != .on }

    /// The line under the card's title: what's happening.
    var statusLine: String {
        guard isReady, !playerNeedsReopen else { return presentation.line }
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

    /// The permission the player needs, said on the card's line with Allow…
    /// (or Reopen AutoHush) under it, never in a row too.
    var missingPermission: Permission? {
        if case .needsPermission(let permission) = health { return permission }
        return nil
    }

    /// A missing permission the user can grant: the card's (`missingPermission`),
    /// or Audio Recording while monitoring runs, a row under Media Player.
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

    /// Whether the menu offers Try Again: only after a failed start that nothing
    /// announces the end of. AutoHush tries again by itself then too, but
    /// waits up to a minute between tries.
    var canRetry: Bool {
        switch health {
        case .retrying, .failed:                                  return true
        case .starting, .ready, .needsPlayer, .degraded, .playerClosed, .needsPermission: return false
        }
    }
}
