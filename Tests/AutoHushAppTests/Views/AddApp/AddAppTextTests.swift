import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import CheckedPlayers

/// The texts that pick their words by what they're given: Add an App's
/// (`AddAppText`) and the permissions' notes (`PermissionText`). Every case
/// gives a text of its own, so a case mapped to the wrong words shows.
private func traits(_ framework: CheckedAppTraits.Framework?) -> CheckedAppTraits {
    CheckedAppTraits(scriptable: false, framework: framework, needsLaunchOption: false)
}

/// The Allow step's summary, Accessibility allowed.
private func summary(audio: PermissionAccess, automation: PermissionAccess? = nil, antiDot: Bool = false) -> String {
    AddAppText.allowedSummary(CheckPermissions(accessibility: true, audio: audio, automation: automation), antiDot: antiDot)
}

@Suite("AddAppText")
struct AddAppTextTests {
    static let app = "Jukebox"

    /// One case of a text, or several that say the same on purpose.
    struct Row {
        let input: String
        let texts: [String]
        let namesApp: Bool
        var text: String { texts[0] }

        init(_ input: String, _ texts: String..., namesApp: Bool = false) {
            self.input = input
            self.texts = texts
            self.namesApp = namesApp
        }
    }

    /// The texts that pick between cases.
    enum Choice: String, CaseIterable {
        case chosen, otherAppProblem, withoutWarning, allowedSummary, timeLeft, playTitle, checkNote,
             wayTitle, wayNote, stateInSentence, stateLabel, stage, activity, request, checkFailed,
             controlNote, audioNote

        var rows: [Row] {
            let app = AddAppTextTests.app
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
                    Row("Automation", AddAppText.withoutWarning([.automation], app: app), namesApp: true),
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
                return [Row("no app yet", AddAppText.checkNote(nil)), Row("the app", AddAppText.checkNote(app), namesApp: true)]
            case .wayTitle:
                return CheckResult.WayKind.allCases.map { Row("\($0)", AddAppText.wayTitle($0)) }
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
            }
        }
    }

    @Test("every case gives words of its own, naming the app where it takes one", arguments: Choice.allCases)
    func everyCase(_ choice: Choice) {
        let rows = choice.rows
        for row in rows {
            #expect(!row.text.isEmpty, "\(row.input)")
            #expect(Set(row.texts).count == 1, "\(row.input) says the same on purpose: \(row.texts)")
            if row.namesApp { #expect(row.text.contains(Self.app), "\(row.input): \(row.text)") }
        }
        let shared = Dictionary(grouping: rows, by: \.text).values.filter { $0.count > 1 }.map { $0.map(\.input) }
        #expect(shared.isEmpty, "these cases say the same: \(shared)")
    }

    @Test("the cases whose words matter say them: AppleScript that only toggles, a permission missing, Now Playing hidden, AntiDot, the countdown")
    func wordsThatMatter() {
        let app = Self.app
        func note(_ kind: CheckResult.WayKind, _ mark: CheckResult.Mark, failed: [CheckResult.WindowState] = []) -> String {
            AddAppText.wayNote(.init(kind: kind, mark: mark, failedStates: failed), app: app)
        }
        #expect(note(.script, .toggleOnly) == "Only toggles: AutoHush can’t tell when to send it")
        #expect(note(.script, .noAutomation) == "Not checked: Automation isn’t allowed")
        #expect(note(.menu, .noAccessibility) == "Not checked: Accessibility isn’t allowed")
        #expect(note(.panel, .menuBarHidden)
            == "Not tried: hidden in the menu bar; show it in \(ControlFailure.nowPlayingSettings), then check again")
        #expect(note(.page, .some, failed: [.covered, .otherDesktop]) == "Not with its window covered or on another desktop")
        // Nothing the check can go without is missing: no warning at all.
        #expect(AddAppText.withoutWarning([], app: app) == "")
        #expect(AddAppText.withoutWarning([.accessibility], app: app) == "")
        #expect(AddAppText.chosen(app, traits: nil) == app)
        #expect(AddAppText.chosen(app, traits: traits(.browserWebApp(browserID: "com.brave.Browser")), browser: "Brave Browser")
            == "Jukebox, a web app of Brave Browser")
        // In AntiDot mode Audio Recording is neither allowed nor gone without.
        #expect(summary(audio: .denied, antiDot: true) == "Accessibility allowed")
        #expect(summary(audio: .denied) == "Accessibility allowed; the check goes on without Audio Recording")
        #expect(summary(audio: .allowed, automation: .denied)
            == "Accessibility and Audio Recording allowed; the check goes on without Automation")
        // The countdown rounds up, and never goes below zero.
        #expect(AddAppText.timeLeft(104.2, for: .play(minutes: 2)) == "You have 1:45 to start it playing.")
        #expect(AddAppText.timeLeft(-3, for: .pause(minutes: 2)) == "You have 0:00 to pause it.")
    }
}
