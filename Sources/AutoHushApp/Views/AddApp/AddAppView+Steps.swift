import AppKit
import SwiftUI
import AutoHushKit
import CheckedPlayers
import PlayerCheckKit

extension AddAppView {
    // MARK: - Each step's lines and buttons

    /// Change…: once the check has run, it asks first, in a sheet on this window.
    private func changeApp() {
        guard model.changeAppForgetsCheck else { return model.changeApp() }
        let alert = PlayerAlerts.changeApp(appName ?? "")
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { [model] in if $0 == .alertFirstButtonReturn { model.changeApp() } }
        } else if InfoAlert.runInFront(alert) == .alertFirstButtonReturn {
            model.changeApp()
        }
    }

    @ViewBuilder func chooseStep(_ state: StepState, busy: Bool) -> some View {
        switch state {
        case .done:
            StepNote(AddAppText.chosen(appName ?? "", traits: model.traits, browser: model.chosen?.browserName))
            if model.canChangeApp {
                Button { changeApp() } label: { Text(verbatim: ChooseText.change) }
                    .buttonStyle(.chip)
                    .padding(.top, 2)
                    .focused($focused, equals: .choose)
            }
        case .current where busy:
            StepNote(AddAppText.opening(appName ?? ""))
        default:
            StepNote(AddAppText.chooseNote)
            if model.openFailed, let app = appName { NoteLabel(AddAppText.couldNotOpen(app)).padding(.top, 2) }
            MainButton(AddAppText.chooseApp, inStep: true) { model.openChooser() }
                .focused($focused, equals: .choose)
        }
    }

    @ViewBuilder func allowStep(_ state: StepState) -> some View {
        switch state {
        case .todo:
            StepNote(AddAppText.allowNote)
        case .done:
            StepNote(AddAppText.allowedSummary(model.permissions, antiDot: model.antiDot))
        default:
            if let app = appName {
                if model.traits?.scriptable == false { StepNote(AddAppText.notScriptable(app)) }
                if model.accessibilityNeedsReopen {
                    // Allowed as AutoHush reads it, missing for the check: AutoHush reads it again once reopened.
                    NoteLabel(AddAppText.accessibilityChanged).padding(.top, 2)
                    MainButton(PermissionText.reopen, inStep: true) { model.reopenForAccessibility() }
                        .focused($focused, equals: .allow)
                } else if model.permissionMissingInCheck {
                    NoteLabel(AddAppText.neededInCheck).padding(.top, 2)
                }
                CheckPermissionRows(model: model, app: app, focused: $focused).padding(.top, 4)
                // Some not allowed: what the check does without them, then
                // Continue once what's needed is (all allowed goes on by itself).
                let missing = model.permissions.missingOptional(antiDot: model.antiDot)
                if !model.permissions.neededAllowed {
                    NoteLabel(AddAppText.accessibilityNeeded(app)).padding(.top, 4)
                } else if !missing.isEmpty, !model.accessibilityNeedsReopen {
                    NoteLabel(AddAppText.withoutWarning(missing, app: app, macMuted: model.checkMuting == .mac)).padding(.top, 4)
                    MainButton(ButtonText.continue, inStep: true) { model.continueWithoutAll() }
                        .focused($focused, equals: .allow)
                }
            }
        }
    }

    @ViewBuilder func reopenStep(_ state: StepState, busy: Bool) -> some View {
        switch state {
        case .done:
            StepNote(model.reopenOutcome == .skipped ? AddAppText.notReopened : AddAppText.reopened)
        case .current where busy:
            StepNote(AddAppText.reopening(appName ?? ""))
        case .current:
            NoteLabel(ReopenText.alertMessage(appName ?? "")).padding(.top, 2)
            if model.reopenFailed { NoteLabel(AddAppText.didNotQuit(appName ?? "")).padding(.top, 2) }
            FlowingButtons {
                MainButton(ReopenText.title(appName ?? ""), inStep: true) { model.reopen() }
                    .focused($focused, equals: .reopen)
                MainButton(AddAppText.skip, secondary: true, inStep: true) { model.skipReopen() }
            }
        default:
            StepNote(AddAppText.reopenPending)
        }
    }

    @ViewBuilder func playStep(_ state: StepState, busy: Bool) -> some View {
        switch (state, model.stage) {
        case (.done, _):
            StepNote(AddAppText.playingNote)
        case (.current, .waitingToPlay(let since)):
            StepNote(AddAppText.playNow(appName ?? ""))
            if model.windowMissing { StepNote(AddAppText.waitsForWindow(appName ?? "")) }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                CountdownBanner(text: AddAppText.timeToPlay(AddAppModel.playWait - context.date.timeIntervalSince(since)))
            }
            .padding(.top, 2)
            // The step's only button then: the focus goes there, not to Change… above.
            if model.canGoBackToResult { backToResultButton.focused($focused, equals: .play) }
        case (.current, _) where busy:
            StepNote(AddAppText.opening(appName ?? ""))
        case (.failed, _) where model.appNotFound:
            // Moved or deleted: Open can't find it, another app is chosen instead.
            NoteLabel(AddAppText.appNotFound(appName ?? "")).padding(.top, 2)
            MainButton(ChooseText.change, inStep: true) { changeApp() }
                .focused($focused, equals: .play)
        case (.failed, _) where model.appQuit:
            NoteLabel(AddAppText.appQuit(appName ?? "")).padding(.top, 2)
            FlowingButtons {
                MainButton(ButtonText.open(appName ?? ""), inStep: true) { model.openAppAgain() }
                    .focused($focused, equals: .play)
                if model.canGoBackToResult { backToResultButton }
            }
        case (.failed, _):
            StepNote(model.windowMissing ? AddAppText.noWindowOpened(appName ?? "") : AddAppText.didNotPlay(appName ?? ""))
            FlowingButtons {
                MainButton(AddAppText.tryAgain, inStep: true) { model.waitForPlaying() }
                    .focused($focused, equals: .play)
                if model.canGoBackToResult { backToResultButton }
            }
        default:
            StepNote(AddAppText.playWaits)
        }
    }

    @ViewBuilder func checkStep(_ state: StepState, busy: Bool) -> some View {
        switch (state, model.stage) {
        case (.done, _):
            StepNote(AddAppText.putBackNote)
        case (.current, _) where busy:
            StepNote(model.isStopping ? AddAppText.stopping
                     : model.isEndingLastCheck ? AddAppText.lastCheckEnding : AddAppText.stage(model.progress.stage))
            StepNote(AddAppText.stopHint)
            MainButton(AddAppText.stop, secondary: true, cancels: true, inStep: true) { model.stopCheck() }
                .disabled(model.isStopping)
                .focused($focused, equals: .check)
        case (.failed, .stopped):
            StepNote(AddAppText.stoppedNote)
            MainButton(AddAppText.checkAgain, inStep: true) { model.checkAgain() }
                .focused($focused, equals: .check)
        case (.failed, _):
            StepNote(AddAppText.checkFailed(model.failureReason, app: appName ?? ""))
            FlowingButtons {
                if model.failureReason == .appNotFound {
                    // Moved or deleted: checked again, it would fail again.
                    MainButton(ChooseText.change, inStep: true) { changeApp() }
                        .focused($focused, equals: .check)
                } else {
                    MainButton(AddAppText.checkAgain, inStep: true) { model.checkAgain() }
                        .focused($focused, equals: .check)
                }
                if model.failureReason == .other {
                    MainButton(AddAppText.showLog, secondary: true, inStep: true) { model.showLog() }
                        .disabled(!model.canShowLog)
                }
            }
        default:
            switch (appName, model.checkMuting) {
            case (let app?, .mac): StepNote(AddAppText.checkNoteMacMuted(app))
            case (let app?, .none): StepNote(AddAppText.checkNoteHeard(app))
            default: StepNote(AddAppText.checkNote(appName))
            }
            if model.traits?.framework != nil { StepNote(AddAppText.switchNote) }
            if state == .current {
                FlowingButtons {
                    MainButton(AddAppText.continueToCheck, inStep: true) { model.continueToCheck() }
                        .focused($focused, equals: .check)
                    if model.canGoBackToResult { backToResultButton }
                }
            }
        }
    }

    /// After Check Again, until the new check starts: the last result again
    /// (A1, 2026-10-29). No key: Escape stays the window's Cancel, which
    /// keeps the result too.
    private var backToResultButton: some View {
        MainButton(AddAppText.backToResult, secondary: true, inStep: true) { model.backToResult() }
    }

    /// Why no way can be used: none worked, or only one AntiDot mode can't
    /// hear (the panel, its row showing no state).
    func nothingNote(_ result: CheckResult, app: String) -> String {
        result.setup == nil ? AddAppText.nothingWorked(app) : AddAppText.nothingInAntiDot(app)
    }

    @ViewBuilder func useStep() -> some View {
        if let result = model.result, let app = appName {
            if model.choosableWays.isEmpty {
                StepNote(nothingNote(result, app: app))
                WaysList(result: result, app: app, panelNeedsSound: model.panelNeedsSound).padding(.top, 4)
            } else {
                StepNote(AddAppText.chooseWay(app))
                WayChoices(model: model, result: result, app: app).padding(.top, 4)
            }
            if model.nowPlayingHidden {
                // Shown there, the panel can be tried with Check Again (2026-10-16).
                Button { model.openMenuBarSettings() } label: { Text(verbatim: ControlFailure.openMenuBarSettings) }
                    .buttonStyle(.chip)
                    .padding(.top, 2)
            }
            if model.choosableWays.isEmpty {
                // No way it can use pauses it: it can be muted instead (the
                // user, 2026-10-15); in AntiDot mode neither (2026-10-16).
                StepNote(AddAppText.muteInstead(app)).padding(.top, 4)
                if model.antiDot {
                    NoteLabel(ControlFailure.muteUnavailable.text(player: app)).padding(.top, 2)
                    Button { model.turnOffAntiDot() } label: { Text(verbatim: AddAppText.turnOffAntiDot) }
                        .buttonStyle(.chip)
                } else if !model.canMute {
                    if model.audioAwaitsReopen {
                        NoteLabel(AddAppText.audioAfterReopen).padding(.top, 2)
                        Button { model.reopenAutoHush() } label: { Text(verbatim: PermissionText.reopen) }
                            .buttonStyle(.chip)
                    } else {
                        NoteLabel(AddAppText.muteNeedsAudio).padding(.top, 2)
                        Button { model.allowMuting() } label: { Text(verbatim: ButtonText.allow) }
                            .buttonStyle(.chip)
                            .accessibilityLabel(Text(verbatim: AddAppText.allowLabel(PermissionText.audioTitle)))
                    }
                }
            }
            // Checked with its windows closed: with one open, the ways that
            // didn't work may.
            if model.closedWaysMayWork { StepNote(AddAppText.openWindowFirst(app)).padding(.top, 4) }
            FlowingButtons {
                if model.choosableWays.isEmpty {
                    // The focus goes to Check Again while Mute It Instead can't be pressed.
                    let mute = MainButton(AddAppText.muteItInstead, inStep: true) { model.useMuting() }.disabled(!model.canMute)
                    let again = MainButton(AddAppText.checkAgain, secondary: true, inStep: true) { model.checkAgain() }
                    if model.canMute {
                        mute.focused($focused, equals: .use)
                        again
                    } else {
                        mute
                        again.focused($focused, equals: .use)
                    }
                } else {
                    MainButton(AddAppText.use(app), inStep: true) { model.use() }
                        .focused($focused, equals: .use)
                    if model.offersCheckAgain {
                        MainButton(AddAppText.checkAgain, secondary: true, inStep: true) { model.checkAgain() }
                    }
                }
            }
        } else {
            StepNote(AddAppText.useWaits)
        }
    }
}

/// A grey line under a step's title.
private struct StepNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(verbatim: text).captionStyle()
    }
}
