import Foundation
import AutoHushKit

/// What the app knows besides the apps with sound, for Diagnostics: the
/// player, the permissions, AutoHush's settings and the Mac. The app
/// delegate gathers it; the report only words it.
struct DiagnosticsFacts: Equatable {
    /// The chosen player's version, when it's installed.
    var playerVersion: String?
    var playerCanFade = true
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
    /// `nil` when macOS can't be asked.
    var audioRecording: AudioCapturePermission?
    var notificationsOff = false
    var detectionMethod: DetectionMethod = .audioLevels
    var timings: TimingSettings = .defaults
    /// E.g. "0.6.1 (19)".
    var appVersion = ""
    var launchAtLogin = false
    var checksForUpdates = true
    var automaticUpdates: AutomaticUpdates = .install
    var lastUpdateCheck: Date?
    /// E.g. "27.0.1 (26A434)".
    var macOS = ""
    /// "Apple silicon" or "Intel".
    var processor = ""
    var now = Date()
}

/// What Settings → Diagnostics shows: how AutoHush is doing, every app with
/// its sound on and how AutoHush judges it, then a section each for the
/// music player, the detection, the permissions, AutoHush and the Mac; and
/// all of it as text, for Copy Report.
enum DiagnosticsReport {
    /// `bundlePath` finds an app's bundle, for its icon.
    static func snapshot(
        activeAudio: [ActiveAudioReport.Entry],
        status: AppStatus,
        facts: DiagnosticsFacts,
        bundlePath: (String) -> String? = { _ in nil }
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
        let sections = sections(status: status, facts: facts)
        let appsSummary = apps.isEmpty
            ? String(localized: "None", comment: "Diagnostics: no apps, or no ignored apps")
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
        String(localized: "No foreign audio output currently detected.", comment: "Diagnostics")
    }

    static var appsTitle: String {
        String(localized: "Apps with Sound", comment: "Settings → Diagnostics: heading of the apps that have their sound on")
    }

    // MARK: - How AutoHush is doing

    private static func overview(status: AppStatus) -> DiagnosticsSnapshot.Overview {
        if status.health == .starting {
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

    private static func sections(status: AppStatus, facts: DiagnosticsFacts) -> [DiagnosticsSnapshot.Section] {
        [player(status: status, facts: facts), detection(status: status, facts: facts),
         permissions(status: status, facts: facts), autoHush(status: status, facts: facts), mac(facts: facts)]
    }

    private static func player(status: AppStatus, facts: DiagnosticsFacts) -> DiagnosticsSnapshot.Section {
        let title = String(localized: "Music Player", comment: "Settings → Diagnostics: heading")
        guard let player = status.chosenPlayer else {
            let none = String(localized: "None chosen", comment: "Diagnostics: no music player chosen")
            return .init(kind: .player, title: title, summary: none,
                         rows: [Row(label: playerLabel, value: none, mark: .problem)])
        }
        let name = player.isInstalled
            ? [player.name, facts.playerVersion].compactMap { $0 }.joined(separator: " ")
            : "\(player.name) · \(PlayerOption.notInstalledLabel)"
        let state = describe(status.playback)
        var rows = [
            Row(label: playerLabel, value: name, mark: player.isInstalled ? nil : .problem),
            Row(label: String(localized: "State", comment: "Diagnostics: the music player's state"), value: state),
            // Yes, Off (turned off in Settings → Advanced), or No (the player can't fade).
            Row(label: String(localized: "Fades", comment: "Diagnostics: whether AutoHush can fade the music player"),
                value: !facts.playerCanFade ? no : facts.timings.fadesEnabled ? yes : off),
        ]
        if let learned = facts.playerLearned {
            rows.append(Row(label: String(localized: "Play/Pause button learned",
                                          comment: "Diagnostics: whether AutoHush knows which button of the web app plays and pauses it"),
                            value: learned ? yes : no, mark: learned ? .ok : .problem))
        }
        if let reaches = facts.reachesOtherSpaces {
            rows.append(Row(label: String(localized: "Reaches windows on other Spaces",
                                          comment: "Diagnostics: whether AutoHush can control the web app while its window is on another desktop"),
                            value: reaches ? yes : no, mark: reaches ? .ok : .problem))
        }
        return .init(kind: .player, title: title, summary: "\(player.name) · \(state)", rows: rows)
    }

    private static var playerLabel: String {
        String(localized: "Player", comment: "Diagnostics: the music player's name and version")
    }

    private static func detection(status: AppStatus, facts: DiagnosticsFacts) -> DiagnosticsSnapshot.Section {
        let method = describe(status.detection)
        let antiDot = facts.detectionMethod != .audioLevels
        var rows = [
            Row(label: String(localized: "Detecting by", comment: "Diagnostics: how AutoHush tells that apps play"), value: method),
            Row(label: String(localized: "AntiDot mode", comment: "Settings → General and Diagnostics: the switch for AntiDot mode, which hides the purple recording indicator"), value: antiDot ? on : off),
            Row(label: String(localized: "Pause music after", comment: "Settings → Advanced and Diagnostics: how long another app must play before the music pauses"), value: seconds(facts.timings.startConfirmation)),
        ]
        if facts.detectionMethod == .playbackSignals {
            rows.append(Row(label: String(localized: "Pause music after, without video",
                                          comment: "Diagnostics, AntiDot mode: how long an app showing no video must play before the music pauses"),
                            value: seconds(AppConfiguration(timings: facts.timings).startConfirmationWithoutVideo)))
        }
        rows.append(Row(label: String(localized: "Resume music after", comment: "Settings → Advanced and Diagnostics: how long other apps must be quiet before the music resumes"), value: seconds(facts.timings.stopGrace)))
        if !antiDot {
            rows.append(Row(label: String(localized: "Silence threshold", comment: "Settings → Advanced and Diagnostics: the sound level below which an app counts as silent"),
                            value: String(localized: "\(Int(facts.timings.silenceThresholdDB)) dB", comment: "A sound level in decibels")))
        }
        return .init(kind: .detection, title: String(localized: "Detection", comment: "Settings → Advanced: heading of when other apps count as playing or stopped"), summary: method, rows: rows)
    }

    private static func permissions(status: AppStatus, facts: DiagnosticsFacts) -> DiagnosticsSnapshot.Section {
        var rows: [Row] = []
        let antiDot = facts.detectionMethod != .audioLevels
        let audio = String(localized: "Audio recording", comment: "Diagnostics: the System Audio Recording permission")
        switch facts.audioRecording {
        case .granted?:
            rows.append(Row(label: audio, value: allowed, mark: .ok))
        case _ where antiDot:
            rows.append(Row(label: audio, value: String(localized: "Not needed in AntiDot mode",
                                                        comment: "Diagnostics: a permission AntiDot mode doesn't use"),
                            mark: .neutral))
        case .denied?:
            rows.append(Row(label: audio, value: notAllowed, mark: .problem))
        case .notDetermined?:
            rows.append(Row(label: audio, value: String(localized: "Not asked yet", comment: "Diagnostics: a permission macOS hasn't asked about"),
                            mark: .problem))
        case nil:
            rows.append(Row(label: audio, value: unknown, mark: .neutral))
        }
        if let permission = facts.playerPermission {
            let label = switch permission {
            case .automation(let player):
                String(localized: "Automation for \(player)", comment: "Diagnostics: the permission to control the music player, e.g. “Automation for Spotify”")
            case .accessibility(let player):
                String(localized: "Accessibility for \(player)", comment: "Diagnostics: the permission to control the music player, e.g. “Accessibility for TIDAL”")
            case .systemAudioRecording:
                audio
            }
            switch facts.playerPermissionGranted {
            case true?:  rows.append(Row(label: label, value: allowed, mark: .ok))
            case false?: rows.append(Row(label: label, value: notAllowed, mark: .problem))
            case nil:
                rows.append(Row(label: label, value: String(localized: "Not checked yet",
                                                            comment: "Diagnostics: a permission AutoHush hasn't needed yet"),
                                mark: .neutral))
            }
        }
        rows.append(Row(label: String(localized: "Notifications", comment: "Diagnostics: the notifications permission"),
                        value: facts.notificationsOff ? off : allowed, mark: facts.notificationsOff ? .neutral : .ok))
        let summary = rows.contains { $0.mark == .problem }
            ? String(localized: "Something's missing", comment: "Diagnostics: a permission isn't granted")
            : String(localized: "All allowed", comment: "Diagnostics: every permission AutoHush needs is granted")
        return .init(kind: .permissions, title: String(localized: "Permissions", comment: "Settings → Diagnostics: heading"),
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
            ? String(localized: "None", comment: "Diagnostics: no apps, or no ignored apps")
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
                     summary: String(localized: "Version \(facts.appVersion)", comment: "Settings → About and Diagnostics; %@ is AutoHush's version"),
                     rows: [
                        Row(label: String(localized: "Version", comment: "Diagnostics: AutoHush's version"), value: facts.appVersion),
                        Row(label: String(localized: "Auto-Pause", comment: "Diagnostics: whether Auto-Pause is on"), value: autoPause),
                        Row(label: String(localized: "Ignored apps", comment: "Diagnostics: apps that never pause the music"), value: ignored),
                        Row(label: String(localized: "Launch at login", comment: "Settings → General and Diagnostics: whether AutoHush opens when you log in"), value: facts.launchAtLogin ? on : off),
                        Row(label: String(localized: "Updates", comment: "Menu toolbar button, Settings → General heading and Diagnostics row: AutoHush's updates"), value: updates),
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

    private static var on: String { String(localized: "On", comment: "Diagnostics: a setting that is on") }
    private static var off: String { String(localized: "Off", comment: "Diagnostics: a setting that is off") }
    private static var yes: String { String(localized: "Yes", comment: "Diagnostics: yes") }
    private static var no: String { String(localized: "No", comment: "Diagnostics: no") }
    private static var allowed: String { String(localized: "Allowed", comment: "Diagnostics: a permission that is granted") }
    private static var notAllowed: String { String(localized: "Not allowed", comment: "Diagnostics: a permission that isn't granted") }
    private static var unknown: String { String(localized: "Unknown", comment: "Diagnostics: something AutoHush can't tell") }

    /// "playing, ignored" as a row's subtitle: "Playing, ignored".
    private static func sentenceCase(_ text: String) -> String {
        text.prefix(1).localizedUppercase + text.dropFirst()
    }

    private static func seconds(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return String(localized: "\(number) s", comment: "A duration in seconds")
    }

    /// The music player's state, as Diagnostics shows it.
    private static func describe(_ playback: PlaybackState) -> String {
        switch playback {
        case .musicPlaying:     return String(localized: "Playing", comment: "At the top of the menu, under the music player: it's playing")
        case .pausedByMonitor:  return String(localized: "Paused by AutoHush", comment: "Diagnostics: the music player's state")
        case .musicIdle:        return String(localized: "Not playing", comment: "At the top of the menu, under the music player: nothing plays")
        case .playingElsewhere: return String(localized: "Playing on another device", comment: "At the top of the menu, under the music player, e.g. through Spotify Connect")
        case .unknown:          return unknown
        }
    }

    /// How AutoHush tells that apps play, right now.
    private static func describe(_ detection: DetectionMode) -> String {
        switch detection {
        case .audioLevel:      return String(localized: "Audio levels", comment: "Diagnostics: a way to detect playing apps")
        case .pending:
            return String(localized: "Audio levels (starting)", comment: "Diagnostics: audio levels, before the first is measured")
        case .unavailable:
            return String(localized: "Open audio streams (no audio recording access)",
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
            return String(localized: "tells macOS it's playing",
                          comment: "Diagnostics: why an app counts as playing, in AntiDot mode or while levels aren't measured")
        case .notAnnouncing:
            return String(localized: "not telling macOS it's playing",
                          comment: "Diagnostics: why an app counts as paused, in AntiDot mode or while levels aren't measured")
        case .level(let peak) where peak > 0:
            return String(localized: "\(Int((20 * log10(peak)).rounded())) dBFS",
                          comment: "Diagnostics: an app's loudest level, in decibels")
        case .level:
            return String(localized: "silence", comment: "Diagnostics: the level of an app that makes no sound")
        }
    }
}

/// Settings → Diagnostics, as it is now.
struct DiagnosticsSnapshot: Equatable {
    /// How AutoHush is doing, at the top.
    struct Overview: Equatable {
        enum Kind: Equatable { case working, attention, off, starting }
        let kind: Kind
        let title: String
        let detail: String
    }

    /// An app with its sound on.
    struct App: Equatable, Identifiable {
        let id: String
        let name: String
        let bundlePath: String?
        /// How AutoHush judges it, e.g. "Playing, ignored".
        let judgement: String
        /// What the judgement rests on, e.g. "-20 dBFS".
        let evidence: String?
    }

    /// A label and its value, with a mark for permissions and problems.
    struct Row: Equatable {
        enum Mark: Equatable { case ok, problem, neutral }
        let label: String
        let value: String
        var mark: Mark?
    }

    /// A section below the apps; folded, it shows `summary`.
    struct Section: Equatable, Identifiable {
        enum Kind: Hashable { case player, detection, permissions, autoHush, mac }
        let kind: Kind
        let title: String
        let summary: String
        let rows: [Row]
        var id: Kind { kind }
    }

    /// A part that folds away under its heading: the apps, or a section.
    enum Part: Hashable {
        case apps
        case section(Section.Kind)
    }

    let overview: Overview
    let apps: [App]
    /// The apps' names, shown while their section is folded.
    let appsSummary: String
    let sections: [Section]
    /// The whole report, for Copy Report.
    let text: String
}
