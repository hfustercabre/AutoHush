import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit
import CheckedPlayers
import PlayerCheckKit

/// The texts that pick their words by what they're given, wherever they
/// are: Add an App's (`AddAppText`), the permissions' notes and button,
/// Settings' choices, the logs window's filters, why a player couldn't be
/// controlled, the update notices, Add a Web App's problems, and learning's
/// buttons and notes. Every case gives a text of its own, so a case mapped
/// to the wrong words shows.
private func traits(_ framework: CheckedAppTraits.Framework?) -> CheckedAppTraits {
    CheckedAppTraits(scriptable: false, framework: framework, needsLaunchOption: false)
}

/// The Allow step's summary, Accessibility allowed.
private func summary(audio: PermissionAccess, automation: PermissionAccess? = nil, antiDot: Bool = false) -> String {
    AddAppText.allowedSummary(CheckPermissions(accessibility: true, audio: audio, automation: automation), antiDot: antiDot)
}

@Suite("Texts by case")
@MainActor
struct TextChoiceTests {
    nonisolated static let app = "Jukebox"

    /// One case of a text, or several that say the same on purpose.
    struct Row {
        let input: String
        let texts: [String]
        /// What it names, when it takes one: the app, a site, a version.
        let names: String?
        var text: String { texts[0] }

        init(_ input: String, _ texts: String..., namesApp: Bool = false, names: String? = nil) {
            self.input = input
            self.texts = texts
            self.names = names ?? (namesApp ? TextChoiceTests.app : nil)
        }
    }

    /// The texts that pick between cases.
    enum Choice: String, CaseIterable {
        case chosen, otherAppProblem, withoutWarning, allowedSummary, timeLeft, playTitle, checkNote,
             wayTitle, wayNote, stateInSentence, stateLabel, stage, activity, request, checkFailed,
             controlNote, audioNote, permissionButton, detectionTitle, detectionSummary, unavailableNote,
             updateTitle, updateExplanation, noticeBody, stepButton, learningNote, controlFailure, controlError,
             webAppProblem, logsFilter, sortDirection

        @MainActor var rows: [Row] {
            let app = TextChoiceTests.app
            switch self {
            case .chosen:
                return [
                    Row("native", AddAppText.chosen(app, traits: nil), AddAppText.chosen(app, traits: traits(nil)), namesApp: true),
                    Row("Electron", AddAppText.chosen(app, traits: traits(.electron)), namesApp: true),
                    Row("Chromium", AddAppText.chosen(app, traits: traits(.chromium)), namesApp: true),
                    Row("Flutter", AddAppText.chosen(app, traits: traits(.flutter)), namesApp: true),
                    Row("a browser's web app", AddAppText.chosen(app, traits: traits(.browserWebApp(browserID: "com.brave.Browser")), browser: "Brave Browser"),
                        namesApp: true),
                    Row("a web app of an unknown browser", AddAppText.chosen(app, traits: traits(.browserWebApp(browserID: "com.brave.Browser"))),
                        namesApp: true),
                ]
            case .otherAppProblem:
                return [
                    Row("not an app", AddAppText.otherAppProblem(.notAnApp)),
                    Row("supported", AddAppText.otherAppProblem(.supported(app)), namesApp: true),
                    Row("AutoHush", AddAppText.otherAppProblem(.autoHush)),
                ]
            case .withoutWarning:
                return [
                    Row("both", AddAppText.withoutWarning([.audioRecording, .automation], app: app),
                        AddAppText.withoutWarning([.automation, .audioRecording, .accessibility], app: app), namesApp: true),
                    Row("Audio Recording", AddAppText.withoutWarning([.audioRecording], app: app), namesApp: true),
                    Row("Automation", AddAppText.withoutWarning([.automation], app: app),
                        AddAppText.withoutWarning([.automation], app: app, macMuted: true), namesApp: true),
                    Row("both, the Mac muted", AddAppText.withoutWarning([.audioRecording, .automation], app: app, macMuted: true), namesApp: true),
                    Row("Audio Recording, the Mac muted", AddAppText.withoutWarning([.audioRecording], app: app, macMuted: true), namesApp: true),
                ]
            case .allowedSummary:
                return [
                    Row("Audio Recording", summary(audio: .allowed), summary(audio: .allowed, automation: .playerNotRunning)),
                    Row("without Audio Recording", summary(audio: .denied)),
                    Row("AntiDot", summary(audio: .allowed, antiDot: true), summary(audio: .denied, antiDot: true)),
                    Row("Audio Recording and Automation", summary(audio: .allowed, automation: .allowed)),
                    Row("AntiDot, without Automation", summary(audio: .allowed, automation: .denied, antiDot: true),
                        summary(audio: .denied, automation: .notAsked, antiDot: true)),
                    Row("without either", summary(audio: .denied, automation: .denied)),
                ]
            case .timeLeft:
                return [
                    Row("play", AddAppText.timeLeft(105, for: .play(minutes: 2)), AddAppText.timeToPlay(105)),
                    Row("pause", AddAppText.timeLeft(105, for: .pause(minutes: 2))),
                    Row("allow Accessibility", AddAppText.timeLeft(105, for: .allowAccessibility(minutes: 2))),
                ]
            case .playTitle:
                return [Row("no app yet", AddAppText.playTitle(nil)), Row("the app", AddAppText.playTitle(app), namesApp: true)]
            case .checkNote:
                return [Row("no app yet", AddAppText.checkNote(nil)), Row("the app", AddAppText.checkNote(app), namesApp: true),
                        Row("the Mac muted", AddAppText.checkNoteMacMuted(app), namesApp: true),
                        Row("nothing muted", AddAppText.checkNoteHeard(app), namesApp: true)]
            case .wayTitle:
                return CheckResult.WayKind.allCases.map { Row("\($0)", WayText.title($0)) }
            case .wayNote:
                func note(_ kind: CheckResult.WayKind, _ mark: CheckResult.Mark, failed: [CheckResult.WindowState] = []) -> String {
                    AddAppText.wayNote(.init(kind: kind, mark: mark, failedStates: failed), app: app)
                }
                return [
                    Row("works", note(.menu, .works), note(.script, .works)),
                    Row("works, the panel", note(.panel, .works)),
                    Row("some", note(.page, .some, failed: [.covered, .otherDesktop])),
                    Row("none", note(.menu, .none), namesApp: true),
                    Row("no script", note(.script, .notThere), namesApp: true),
                    Row("no menu", note(.menu, .notThere), namesApp: true),
                    Row("no page", note(.page, .notThere)),
                    Row("not in Now Playing", note(.panel, .notThere), namesApp: true),
                    Row("Now Playing hidden", note(.panel, .menuBarHidden)),
                    Row("toggles only", note(.script, .toggleOnly)),
                    Row("not tried", note(.page, .notTried)),
                    Row("no Automation", note(.script, .noAutomation)),
                    Row("no Accessibility", note(.menu, .noAccessibility)),
                    Row("not checked", note(.menu, .notChecked)),
                ]
            case .stateInSentence:
                return CheckResult.WindowState.allCases.map { Row("\($0)", AddAppText.stateInSentence($0)) }
            case .stateLabel:
                return CheckResult.WindowState.allCases.map { Row("\($0)", AddAppText.stateLabel($0)) }
            case .stage:
                let stages: [CheckProgress.Stage] = [.reading, .permissions, .playing, .movingWindow, .readingPage, .testing, .finishing]
                return stages.map { Row("\($0)", AddAppText.stage($0)) }
            case .activity:
                let activities: [CheckProgress.Activity] = [.moving, .untested]
                    + CheckResult.WayKind.allCases.flatMap { way -> [CheckProgress.Activity] in [.pausing(way), .playingAgain(way)] }
                return activities.map { Row("\($0)", AddAppText.activity($0)) }
            case .request:
                return [
                    Row("play", AddAppText.request(.play(minutes: 2), app: app), namesApp: true),
                    Row("pause", AddAppText.request(.pause(minutes: 2), app: app), namesApp: true),
                    Row("allow Accessibility", AddAppText.request(.allowAccessibility(minutes: 2), app: app)),
                ]
            case .checkFailed:
                return [
                    Row("the app quit", AddAppText.checkFailed(.appQuit, app: app), namesApp: true),
                    Row("the app not found", AddAppText.checkFailed(.appNotFound, app: app), namesApp: true),
                    Row("another reason", AddAppText.checkFailed(.other, app: app), AddAppText.checkFailed(nil, app: app)),
                ]
            case .controlNote:
                return [
                    Row("allowed", PermissionText.controlNote(app, .allowed), PermissionText.controlNote(app, .notNeeded),
                        PermissionText.controlNote(app, .needsReopen)),
                    Row("player not running", PermissionText.controlNote(app, .playerNotRunning), namesApp: true),
                    Row("not asked", PermissionText.controlNote(app, .notAsked)),
                    Row("denied", PermissionText.controlNote(app, .denied)),
                ]
            case .audioNote:
                return [
                    Row("what it's for", PermissionText.audioNote(.allowed), PermissionText.audioNote(.notAsked),
                        PermissionText.audioNote(.playerNotRunning)),
                    Row("denied", PermissionText.audioNote(.denied)),
                    Row("needs reopening", PermissionText.audioNote(.needsReopen)),
                    Row("AntiDot", PermissionText.audioNote(.notNeeded)),
                ]
            case .permissionButton:
                func title(_ access: PermissionAccess, _ permission: Permission = .systemAudioRecording, long: Bool = false) -> String {
                    PermissionButton.title(for: access, permission: permission, long: long, player: app) ?? ""
                }
                return [
                    Row("the player not running", title(.playerNotRunning, .automation(player: app)), namesApp: true),
                    Row("needs reopening", title(.needsReopen)),
                    Row("to allow", title(.notAsked), title(.denied)),
                    Row("to allow, long", title(.notAsked, .automation(player: app), long: true),
                        title(.denied, .automation(player: app), long: true), namesApp: true),
                ]
            case .detectionTitle:
                return Self.detectionMethods.map { Row("\($0)", $0.title) }
            case .detectionSummary:
                return Self.detectionMethods.map { Row("\($0)", $0.summary) }
            case .unavailableNote:
                return [
                    Row("muted only", DetectionText.unavailableNote(app, mutes: true), namesApp: true),
                    Row("only its sound tells", DetectionText.unavailableNote(app, mutes: false), namesApp: true),
                ]
            case .updateTitle:
                return AutomaticUpdates.allCases.map { Row("\($0)", $0.title) }
            case .updateExplanation:
                return AutomaticUpdates.allCases.map { Row("\($0)", $0.explanation) }
            case .noticeBody:
                let version = AppVersion("0.3.8")!
                return [
                    Row("available", UpdateNotice.available(version, running: AppVersion("0.3.7")!).body, names: "0.3.7"),
                    Row("downloaded", UpdateNotice.downloaded(version).body),
                    Row("installed", UpdateNotice.installed(version).body),
                    Row("install failed", UpdateNotice.installFailed(version).body),
                ]
            case .stepButton:
                let buttons: [StepButton] = [.itsPlaying, .itsPaused, .tryAgain, .pauseManually, .addToDock]
                return buttons.map { Row("\($0)", $0.title) }
            case .learningNote:
                let notes: [LearningNote] = [.notHeard, .nothingChanged, .timedOut, .cantSeePage]
                return notes.map { Row("\($0)", $0.text(app), namesApp: $0 != .timedOut) }
            case .controlFailure:
                let failures: [ControlFailure] = [.menuItemNotFound, .stateUnknown, .nothingToPlay, .buttonDisabled, .pressFailed,
                                                  .pressIgnored, .muteUnavailable, .hearingUnavailable, .nowPlayingHidden,
                                                  .appleEventError(-1708)]
                return failures.map { Row("\($0)", $0.text(player: app), namesApp: true) }
            case .controlError:
                func text(_ error: MusicPlayerError) -> String { ControlError(error, player: app).text }
                return [
                    Row("no longer allowed", text(.automationPermissionDenied), text(.accessibilityPermissionDenied), namesApp: true),
                    Row("not running", text(.playerNotRunning), namesApp: true),
                    Row("not responding", text(.playerNotResponding), namesApp: true),
                    Row("a command failed, in its failure's words", text(.playerCommandFailed(.pressIgnored)), namesApp: true),
                ]
            case .webAppProblem:
                func problem(_ error: WebAppMakingError, example: String? = nil) -> String {
                    let model = AddWebAppModel()
                    model.exampleAddress = example
                    model.fail(error)
                    return model.problemText ?? ""
                }
                let site = "music.example.com"
                return [
                    Row("not a web address", problem(.notAWebAddress)),
                    Row("not a web address, with an example", problem(.notAWebAddress, example: site), names: site),
                    Row("no answer", problem(.noAnswer(host: site)), names: site),
                    Row("no such page", problem(.pageNotFound(host: site)), names: site),
                    Row("no Accessibility", problem(.accessibilityDenied)),
                    Row("Safari didn't add it", problem(.browserFailed("no dialog"))),
                    Row("not found yet", problem(.notFound(name: app)), namesApp: true),
                ]
            case .logsFilter:
                return LogsModel.Range.allCases.map { Row("\($0)", $0.title) } + LogsModel.Levels.allCases.map { Row("\($0)", $0.title) }
            case .sortDirection:
                return AppListOrder.Criterion.allCases.flatMap { criterion in
                    [false, true].map { Row("\(criterion), reversed: \($0)", AppListOrder(criterion: criterion, isReversed: $0).directionTitle) }
                }
            }
        }

        static let detectionMethods: [DetectionMethod] = [.audioLevels, .playbackSignals, .openStreams]
    }

    @Test("every case gives words of its own, naming the app, the site or the version where it takes one", arguments: Choice.allCases)
    func everyCase(_ choice: Choice) {
        let rows = choice.rows
        for row in rows {
            #expect(!row.text.isEmpty, "\(row.input)")
            #expect(Set(row.texts).count == 1, "\(row.input) says the same on purpose: \(row.texts)")
            if let names = row.names { #expect(row.text.contains(names), "\(row.input): \(row.text)") }
        }
        let shared = Dictionary(grouping: rows, by: \.text).values.filter { $0.count > 1 }.map { $0.map(\.input) }
        #expect(shared.isEmpty, "these cases say the same: \(shared)")
    }

    /// What Add an App's last step says of a way the check tried.
    private func wayNote(_ kind: CheckResult.WayKind, _ mark: CheckResult.Mark, failed: [CheckResult.WindowState] = []) -> String {
        AddAppText.wayNote(.init(kind: kind, mark: mark, failedStates: failed), app: Self.app)
    }

    @Test("the check's notes say when AppleScript only toggles, a permission is missing, Now Playing is hidden, or which window states failed")
    func wordsThatMatter() {
        #expect(wayNote(.script, .toggleOnly) == "Only toggles: AutoHush can’t tell when to send it")
        #expect(wayNote(.script, .noAutomation) == "Not checked: Automation isn’t allowed")
        #expect(wayNote(.menu, .noAccessibility) == "Not checked: Accessibility isn’t allowed")
        #expect(wayNote(.panel, .menuBarHidden)
            == "Not tried: hidden in the menu bar; show it in \(ControlFailure.nowPlayingSettings), then check again")
        #expect(wayNote(.page, .some, failed: [.covered, .otherDesktop]) == "Not with its window covered or on another desktop")
    }

    @Test("with nothing missing that the check can go without, Add an App warns of nothing")
    func noWarning() {
        #expect(AddAppText.withoutWarning([], app: Self.app) == "")
        #expect(AddAppText.withoutWarning([.accessibility], app: Self.app) == "")
    }

    @Test("Add an App names the app chosen, and a browser's web app as its browser's")
    func chosenApp() {
        #expect(AddAppText.chosen(Self.app, traits: nil) == Self.app)
        #expect(AddAppText.chosen(Self.app, traits: traits(.browserWebApp(browserID: "com.brave.Browser")), browser: "Brave Browser")
            == "Jukebox, a web app of Brave Browser")
    }

    @Test("the permissions' summary says what the check goes on without; in AntiDot mode Audio Recording is neither allowed nor gone without")
    func permissionsSummary() {
        #expect(summary(audio: .denied, antiDot: true) == "Accessibility allowed")
        #expect(summary(audio: .denied) == "Accessibility allowed; the check goes on without Audio Recording")
        #expect(summary(audio: .allowed, automation: .denied)
            == "Accessibility and Audio Recording allowed; the check goes on without Automation")
    }

    @Test("Add an App's countdown rounds up, and never goes below zero")
    func countdown() {
        #expect(AddAppText.timeLeft(104.2, for: .play(minutes: 2)) == "You have 1:45 to start it playing.")
        #expect(AddAppText.timeLeft(-3, for: .pause(minutes: 2)) == "You have 0:00 to pause it.")
    }

    @Test("a permission allowed, or not needed, has no button, as titled and as drawn")
    func noPermissionButtonOnceAllowed() {
        for access: PermissionAccess in [.allowed, .notNeeded] {
            #expect(PermissionButton.title(for: access, permission: .automation(player: Self.app), long: true, player: Self.app) == nil)
        }
        // As drawn: a button with its words, none once allowed.
        let model = SettingsModel(settings: .inMemory(), updates: FakeUpdateCommands(), actions: FakeAppActions(),
                                  launchAtLoginController: MockLaunchAtLoginController(isEnabled: false))
        func drawnWidth(_ access: PermissionAccess) -> CGFloat {
            NSHostingView(rootView: PermissionButton(model: model, permission: .systemAudioRecording, access: access)).fittingSize.width
        }
        #expect(drawnWidth(.denied) > 0 && drawnWidth(.allowed) == 0)
    }

    @Test("the check's warning shows a symbol this macOS has for each window state")
    func windowStateSymbols() {
        // One this macOS lacks would draw nothing.
        for state in CheckResult.WindowState.allCases {
            #expect(NSImage(systemSymbolName: CheckWarningView.symbol(state), accessibilityDescription: nil) != nil, "\(state)")
        }
    }
}
