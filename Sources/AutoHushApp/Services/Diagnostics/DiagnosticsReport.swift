import Foundation
import AutoHushKit
import CheckedPlayers

/// What Settings → Diagnostics shows: how AutoHush is doing, every app with
/// its sound on and how AutoHush judges it, then a section each for the
/// media player, the detection, the permissions, AutoHush and the Mac; and
/// all of it as text, for Copy Report.
enum DiagnosticsReport {
    /// `bundlePath` finds an app's bundle, for its icon; `ways`, the ways an
    /// app added with Add an App is controlled by (its player's setup).
    static func snapshot(
        activeAudio: [ActiveAudioReport.Entry],
        status: AppStatus,
        facts: DiagnosticsFacts,
        bundlePath: (String) -> String? = { _ in nil },
        ways: (String) -> [PlayerSetup.Way]? = { _ in nil }
    ) -> DiagnosticsSnapshot {
        let apps = activeAudio.map { entry in
            DiagnosticsSnapshot.App(
                id: entry.id,
                name: entry.name ?? entry.id,
                bundlePath: bundlePath(entry.id),
                judgement: sentenceCase(describe(entry.state, isIgnored: entry.isIgnored)),
                evidence: entry.evidence.map(describe)
            )
        }
        let overview = overview(status: status)
        let sections = sections(status: status, facts: facts, ways: ways)
        let appsSummary = apps.isEmpty
            ? MenuIgnoredAppsView.noneTitle
            : apps.map(\.name).formatted(.list(type: .and, width: .narrow))
        return DiagnosticsSnapshot(
            overview: overview,
            apps: apps,
            appsSummary: appsSummary,
            sections: sections,
            text: text(overview: overview, activeAudio: activeAudio, sections: sections)
        )
    }

    /// Said when no app has its sound on.
    static var noAudio: String {
        String(localized: "No other app is playing sound right now.", comment: "Diagnostics")
    }

    static var appsTitle: String {
        String(localized: "Apps with Sound", comment: "Settings → Diagnostics: heading of the apps that have their sound on")
    }

    // MARK: - How AutoHush is doing

    private static func overview(status: AppStatus) -> DiagnosticsSnapshot.Overview {
        // Ready, but the player's state not known yet: still starting.
        if status.health == .starting || status.isReady && status.playback == .unknown {
            return .init(kind: .starting,
                         title: String(localized: "Starting…", comment: "Diagnostics: AutoHush is starting"),
                         detail: status.statusLine)
        }
        if status.needsAttention {
            return .init(kind: .attention,
                         title: String(localized: "Needs your attention", comment: "Diagnostics: something keeps AutoHush from working"),
                         detail: status.statusLine)
        }
        if status.autoPause != .on {
            return .init(kind: .off, title: status.statusLine,
                         detail: String(localized: "Turn Auto-Pause back on in the menu or in Settings.",
                                        comment: "Diagnostics, while auto-pause is off"))
        }
        return .init(kind: .working,
                     title: String(localized: "Working normally", comment: "Diagnostics: AutoHush is working"),
                     detail: "\(status.cardTitle) · \(status.statusLine)")
    }

    // MARK: - Sections

    private typealias Row = DiagnosticsSnapshot.Row

    private static func sections(status: AppStatus, facts: DiagnosticsFacts,
                                 ways: (String) -> [PlayerSetup.Way]?) -> [DiagnosticsSnapshot.Section] {
        [player(status: status, facts: facts, ways: ways), behavior(status: status, facts: facts),
         detection(status: status, facts: facts), permissions(facts: facts), autoHush(status: status, facts: facts),
         mac(facts: facts)]
    }

    private static func player(status: AppStatus, facts: DiagnosticsFacts,
                               ways: (String) -> [PlayerSetup.Way]?) -> DiagnosticsSnapshot.Section {
        let title = PlayerOption.mediaPlayerHeading
        guard let player = status.chosenPlayer else {
            let none = PlayerOption.noneChosenLabel
            return .init(kind: .player, title: title, summary: none,
                         rows: [Row(label: playerLabel, value: none, mark: .problem, fix: .choosePlayer)])
        }
        let name = player.isInstalled
            ? [player.name, facts.playerVersion].compactMap { $0 }.joined(separator: " ")
            : "\(player.name) · \(PlayerOption.notInstalledLabel)"
        let state = describe(status.playback, mutes: player.pausesByMuting || status.playerMutedInstead)
        var rows = [
            Row(label: playerLabel, value: name, mark: player.isInstalled ? nil : .problem, fix: player.isInstalled ? nil : .choosePlayer),
            Row(label: String(localized: "State", comment: "Diagnostics: the media player's state"), value: state),
            // Yes, Off (turned off in Settings → Behavior), or No (the player can't fade).
            Row(label: BehaviorSettingsView.fadesTitle,
                value: !facts.playerCanFade ? no : facts.timings.fadesEnabled ? yes : off),
        ]
        // An app added with Add an App: its ways, the first tried first.
        if player.kind == .checkedApp, let ways = ways(player.bundleID), !ways.isEmpty {
            rows.append(Row(label: String(localized: "Controlled by",
                                          comment: "Diagnostics: how AutoHush pauses and plays the media player, an app added with Add an App: the ways its check found, one a line, the first tried first (AppleScript, Its playback menu…), or “Muted instead of paused”"),
                            value: ways.map(describe).joined(separator: "\n")))
        }
        if let learned = facts.playerLearned {
            rows.append(Row(label: String(localized: "Play/Pause button learned",
                                          comment: "Diagnostics: whether AutoHush knows which button of the web app plays and pauses it"),
                            value: learned ? yes : no, mark: learned ? .ok : .problem, fix: learned ? nil : .learnControls))
        }
        if let reaches = facts.reachesOtherSpaces {
            rows.append(Row(label: String(localized: "Reaches windows on other Spaces",
                                          comment: "Diagnostics: whether AutoHush can control the web app while its window is on another desktop"),
                            value: reaches ? yes : no, mark: reaches ? .ok : .problem))
        }
        if let read = facts.playerWordsRead {
            rows.append(Row(label: String(localized: "Play/Pause words read",
                                          comment: "Diagnostics: whether AutoHush could read, from the media player's app, its own words for Play and Pause (TIDAL, Apple Podcasts), which tell its state apart"),
                            value: read ? yes : no, mark: read ? .ok : .problem))
        }
        if let error = status.controlError {
            // In the user's language, then as the log has it, for a bug report.
            rows.append(Row(label: String(localized: "Last error", comment: "Diagnostics: why the media player couldn't be controlled, the last time it couldn't"),
                            value: "\(error.text)\n\(error.detail)", mark: .problem))
        }
        return .init(kind: .player, title: title, summary: "\(player.name) · \(state)", rows: rows)
    }

    private static var playerLabel: String {
        String(localized: "Player", comment: "Diagnostics: the media player's name and version")
    }

    /// Settings → Behavior's settings, card by card (the user, 2026-10-21): a
    /// timing or a length only while it's used.
    private static func behavior(status: AppStatus, facts: DiagnosticsFacts) -> DiagnosticsSnapshot.Section {
        let timings = facts.timings
        let antiDot = facts.detectionMethod.isAntiDot
        // Nothing measured with AntiDot mode off (no Audio Recording access,
        // or before the first level): apps wait AntiDot mode's minimums.
        let unmeasured = !antiDot && [.pending, .unavailable].contains(status.detection)
        // With open streams only, every app waits at least 2 s.
        let pauseAfter = facts.detectionMethod == .openStreams || unmeasured
            ? AppConfiguration(timings: timings).startConfirmationWithOpenStreams.secondsText
            : timings.startConfirmation.secondsText
        // Off in AntiDot mode, which measures no sound, and while nothing
        // resumes, whatever the switch.
        let levels = timings.levelsMusic && !antiDot && timings.resumesPlayback
        let fades = timings.fadesEnabled && facts.playerCanFade
        var rows = [
            Row(label: SettingsTiming.pauseAfter.name, value: pauseAfter),
        ]
        if facts.detectionMethod == .playbackSignals || unmeasured {
            rows.append(Row(label: String(localized: "Pause playback after, without video",
                                          comment: "Diagnostics, AntiDot mode: how long an app showing no video must play before your player pauses"),
                            value: AppConfiguration(timings: timings).startConfirmationWithoutVideo.secondsText))
        }
        rows += [
            Row(label: SettingsSwitch.pausesForMicrophone.name, value: timings.pausesForMicrophone ? on : off),
            Row(label: SettingsSwitch.pausesOnDisconnect.name, value: timings.pausesOnOutputDisconnect ? on : off),
            Row(label: SettingsSwitch.resumesPlayback.name, value: timings.resumesPlayback ? on : off),
        ]
        if timings.resumesPlayback {
            rows.append(Row(label: SettingsTiming.resumeAfter.name, value: timings.stopGrace.secondsText))
        }
        rows.append(Row(label: SettingsSwitch.staysPausedAfterCalls.name, value: timings.staysPausedAfterCalls ? on : off))
        if fades {
            rows.append(Row(label: SettingsTiming.fadeOut.name, value: timings.fadeOutDuration.secondsText))
            if timings.resumesPlayback {
                rows.append(Row(label: SettingsTiming.fadeIn.name, value: timings.fadeInDuration.secondsText))
            }
        }
        rows.append(Row(label: SettingsSwitch.levelsMusic.name, value: levels ? on : off))
        if levels {
            rows.append(Row(label: SettingsTiming.levelingMaxCut.name, value: SettingsTiming.decibels(timings.levelingMaxCutDB)))
            rows.append(Row(label: SettingsTiming.levelingMinCut.name, value: SettingsTiming.decibels(timings.levelingMinCutDB)))
        }
        let summary = timings.resumesPlayback
            ? String(localized: "Pauses after \(pauseAfter), resumes after \(timings.stopGrace.secondsText)",
                     comment: "Diagnostics: the summary beside the Behavior heading; the first %@ is how long another app must play before your player pauses, the second how long other apps must be quiet before it resumes, e.g. “Pauses after 0.5 s, resumes after 2 s”")
            : String(localized: "Pauses after \(pauseAfter), never resumes",
                     comment: "Diagnostics: the summary beside the Behavior heading while Resume playback is off; %@ is how long another app must play before your player pauses, e.g. “0.5 s”")
        return .init(kind: .behavior, title: SettingsWindowController.Page.behavior.title, summary: summary, rows: rows)
    }

    private static func detection(status: AppStatus, facts: DiagnosticsFacts) -> DiagnosticsSnapshot.Section {
        let method = describe(status.detection)
        let antiDot = facts.detectionMethod.isAntiDot
        var rows = [
            Row(label: String(localized: "Detecting by", comment: "Diagnostics: how AutoHush tells that apps play"), value: method),
            Row(label: SettingsSwitch.antiDot.name, value: antiDot ? on : off),
        ]
        if !antiDot {
            rows.append(Row(label: SettingsTiming.silenceThreshold.name, value: SettingsTiming.decibels(facts.timings.silenceThresholdDB)))
        }
        return .init(kind: .detection, title: DetectionText.title, summary: method, rows: rows)
    }

    private static func permissions(facts: DiagnosticsFacts) -> DiagnosticsSnapshot.Section {
        var rows: [Row] = []
        let antiDot = facts.detectionMethod.isAntiDot
        let audio = PermissionText.audioTitle
        switch facts.audioRecording {
        case .granted?:
            rows.append(Row(label: audio, value: allowed, mark: .ok))
        case _ where antiDot:
            rows.append(Row(label: audio, value: AntiDotText.notNeeded, mark: .neutral))
        case .denied?:
            rows.append(Row(label: audio, value: notAllowed, mark: .problem, fix: .allow(.systemAudioRecording)))
        case .notDetermined?:
            rows.append(Row(label: audio, value: String(localized: "Not asked yet", comment: "Diagnostics: a permission macOS hasn't asked about"),
                            mark: .problem, fix: .allow(.systemAudioRecording)))
        case nil:
            rows.append(Row(label: audio, value: unknown, mark: .neutral))
        }
        // One muted instead of paused needs only Audio Recording: its row above.
        let control: String? = switch facts.playerPermission {
        case .automation(let player)?:
            String(localized: "Automation for \(player)", comment: "Diagnostics: the permission to control the media player, e.g. “Automation for Spotify”")
        case .accessibility(let player)?:
            String(localized: "Accessibility for \(player)", comment: "Diagnostics: the permission to control the media player, e.g. “Accessibility for TIDAL”")
        case .systemAudioRecording?, nil:
            nil
        }
        if let label = control {
            switch facts.playerPermissionGranted {
            case true?:  rows.append(Row(label: label, value: allowed, mark: .ok))
            case false?: rows.append(Row(label: label, value: notAllowed, mark: .problem, fix: facts.playerPermission.map { .allow($0) }))
            case nil:
                rows.append(Row(label: label, value: String(localized: "Not checked yet",
                                                            comment: "Diagnostics: a permission AutoHush hasn't needed yet"),
                                mark: .neutral))
            }
        }
        rows.append(Row(label: String(localized: "Notifications", comment: "Diagnostics: the notifications permission"),
                        value: facts.notificationsOff ? off : allowed, mark: facts.notificationsOff ? .neutral : .ok))
        let summary = rows.contains { $0.mark == .problem }
            ? String(localized: "Something’s missing", comment: "Diagnostics: a permission isn't granted")
            : String(localized: "All allowed", comment: "Diagnostics: every permission AutoHush needs is granted")
        return .init(kind: .permissions, title: String(localized: "Permissions", comment: "Settings → Diagnostics and the welcome window: the heading over the permissions AutoHush needs"),
                     summary: summary, rows: rows)
    }

    private static func autoHush(status: AppStatus, facts: DiagnosticsFacts) -> DiagnosticsSnapshot.Section {
        let autoPause = switch status.autoPause {
        case .on: on
        case .off: off
        case .snoozed(let until):
            String(localized: "Off \(until)", comment: "Diagnostics: auto-pause; %@ says until when, e.g. “until 15:30”")
        }
        let ignored = status.ignoredApps.isEmpty
            ? MenuIgnoredAppsView.noneTitle
            : status.ignoredApps.map(\.name).formatted(.list(type: .and, width: .narrow))
        let updates = facts.checksForUpdates
            ? facts.automaticUpdates.title
            : String(localized: "Automatic checks off", comment: "Diagnostics: updates aren't checked automatically")
        let lastCheck = facts.lastUpdateCheck.map {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: $0, relativeTo: facts.now)
        } ?? String(localized: "Never", comment: "Diagnostics: updates were never checked")
        return .init(kind: .autoHush, title: "AutoHush",
                     summary: String(localized: "Version \(facts.appVersion)", comment: "Settings → About, Settings' sidebar and Diagnostics; %@ is AutoHush's version"),
                     rows: [
                        Row(label: String(localized: "Version", comment: "Diagnostics: AutoHush's version"), value: facts.appVersion),
                        Row(label: AutoPauseText.title, value: autoPause),
                        Row(label: String(localized: "Ignored apps", comment: "Diagnostics: apps that never pause your player"), value: ignored),
                        Row(label: String(localized: "Launch at login", comment: "Settings → General and Diagnostics: whether AutoHush opens when you log in"), value: facts.launchAtLogin ? on : off),
                        Row(label: MenuBarIconPlace.title, value: facts.keepsMenuBarIconNearSystemIcons ? on : off),
                        Row(label: UpdateOffer.updatesTitle, value: updates),
                        Row(label: String(localized: "Last checked", comment: "Diagnostics: when updates were last checked"), value: lastCheck),
                     ])
    }

    private static func mac(facts: DiagnosticsFacts) -> DiagnosticsSnapshot.Section {
        .init(kind: .mac, title: String(localized: "This Mac", comment: "Settings → Diagnostics: heading"),
              summary: "macOS \(facts.macOS)", rows: [
                Row(label: "macOS", value: facts.macOS),
                Row(label: String(localized: "Processor", comment: "Diagnostics: the Mac's processor"), value: facts.processor),
              ])
    }

    // MARK: - Text, for Copy Report

    private static func text(overview: DiagnosticsSnapshot.Overview, activeAudio: [ActiveAudioReport.Entry],
                             sections: [DiagnosticsSnapshot.Section]) -> String {
        let apps = activeAudio.isEmpty ? noAudio : activeAudio.map(line(for:)).joined(separator: "\n")
        let blocks = ["\(overview.title) — \(overview.detail)", "\(appsTitle)\n\(apps)"]
            + sections.map { section in
                ([section.title] + section.rows.map { "\($0.label): \($0.value)" }).joined(separator: "\n")
            }
        return blocks.joined(separator: "\n\n")
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

    // MARK: - Words

    private static var on: String { String(localized: "On", comment: "A setting that is on: in Diagnostics, and the choice that turns Auto-Pause on in Shortcuts (it reads “Turn Auto-Pause On”) and in the Focus filter") }
    private static var off: String { String(localized: "Off", comment: "A setting that is off: in Diagnostics, and the choice that turns Auto-Pause off in Shortcuts (it reads “Turn Auto-Pause Off”) and in the Focus filter") }
    private static var yes: String { String(localized: "Yes", comment: "Diagnostics: yes") }
    private static var no: String { String(localized: "No", comment: "Diagnostics: no") }
    private static var allowed: String { PermissionText.allowed }
    private static var notAllowed: String { String(localized: "Not allowed", comment: "Diagnostics: a permission that isn't granted") }
    private static var unknown: String { String(localized: "Unknown", comment: "Diagnostics: something AutoHush can't tell") }

    /// "playing, ignored" as a row's subtitle: "Playing, ignored".
    private static func sentenceCase(_ text: String) -> String {
        text.prefix(1).localizedUppercase + text.dropFirst()
    }

    /// The media player's state, as Diagnostics shows it; `mutes`: muted
    /// instead of paused.
    private static func describe(_ playback: PlaybackState, mutes: Bool) -> String {
        switch playback {
        case .musicPlaying:     return String(localized: "Playing", comment: "At the top of the menu, in Settings → General's status line and in Diagnostics, under the media player: it's playing; and under an app that plays now in the Add an App window's list")
        case .pausedByMonitor where mutes:
            return String(localized: "Muted by AutoHush", comment: "Diagnostics: the media player's state while AutoHush mutes it for another app (an app added with Add an App that can only be muted, or a player muted in place of a pause that didn't take)")
        case .pausedByMonitor:  return String(localized: "Paused by AutoHush", comment: "Diagnostics: the media player's state")
        case .musicIdle:        return String(localized: "Not playing", comment: "At the top of the menu, in Settings → General's status line and in Diagnostics, under the media player: nothing plays")
        case .playingElsewhere: return String(localized: "Playing on another device", comment: "At the top of the menu, in Settings → General's status line and in Diagnostics, under the media player, e.g. through Spotify Connect")
        case .playingSilently:  return String(localized: "Playing silently", comment: "At the top of the menu, in Settings → General's status line and in Diagnostics, under the media player: it says it plays, but nothing of it is heard (a muted trailer or preview), so AutoHush doesn't pause it")
        case .pauseFailed:      return String(localized: "Playing: couldn’t pause it", comment: "Diagnostics: the media player's state when it refused to pause or failed to, while another app plays")
        case .unknown:          return unknown
        }
    }

    /// A way an app added with Add an App is controlled by, as its check
    /// names it.
    private static func describe(_ way: PlayerSetup.Way) -> String {
        switch way {
        case .script: AddAppText.wayTitle(.script)
        case .menu: AddAppText.wayTitle(.menu)
        case .page: AddAppText.wayTitle(.page)
        case .panel: AddAppText.wayTitle(.panel)
        case .mute: PlayerOption.mutedInsteadLabel
        }
    }

    /// How AutoHush tells that apps play, right now.
    private static func describe(_ detection: DetectionMode) -> String {
        switch detection {
        case .audioLevel:      return String(localized: "Audio levels", comment: "Diagnostics: a way to detect playing apps")
        case .pending:
            return String(localized: "Audio levels (starting)", comment: "Diagnostics: audio levels, before the first is measured")
        case .unavailable:
            return String(localized: "Open audio streams (no Audio Recording access)",
                          comment: "Diagnostics: the detection used while the audio recording permission is missing")
        case .playbackSignals: return DetectionMethod.playbackSignals.title
        case .disabled:        return DetectionMethod.openStreams.title
        }
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
            return String(localized: "tells macOS it’s playing",
                          comment: "Diagnostics: why an app counts as playing, in AntiDot mode or while levels aren't measured")
        case .notAnnouncing:
            return String(localized: "not telling macOS it’s playing",
                          comment: "Diagnostics: why an app counts as paused, in AntiDot mode or while levels aren't measured")
        case .level(let peak) where peak > 0:
            return String(localized: "\(Int((20 * log10(peak)).rounded())) dBFS",
                          comment: "Diagnostics: an app's loudest level, in decibels")
        case .level:
            return String(localized: "silence", comment: "Diagnostics: the level of an app that makes no sound")
        }
    }
}
