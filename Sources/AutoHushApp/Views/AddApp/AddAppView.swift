import AppKit
import SwiftUI
import AutoHushKit
import CheckedPlayers
import PlayerCheckKit

// "Add an App…", under the menu's Other Apps and their tiles in Settings →
// General and the welcome window (E3): the user chooses an app that can
// play, AutoHush asks for what the check needs, waits for the app to play,
// shows what the check does (W6), runs it (its panel shows the progress),
// then what worked, and Use makes the app the player. One window, its
// numbered steps ticked in turn (W2, the user's pick, 2026-10-15).

/// The window's content: what it's for, then each step, and Cancel.
struct AddAppView: View {
    let model: AddAppModel
    let close: () -> Void
    /// While AutoHush waits for the app to play, the window floats above the
    /// app the user goes into (`true`), and is back at the normal level after
    /// (`false`).
    var floats: (Bool) -> Void = { _ in }
    /// The step whose main control has the keyboard focus (with keyboard
    /// navigation on): the current one's, so a done step's Change… doesn't
    /// keep it.
    @FocusState private var focused: AddAppModel.Step?

    /// Add an App's windows' width (this one, Choose an App, the warning),
    /// which their bottom bars' buttons fit in every language.
    static let width: CGFloat = 460

    var body: some View {
        WindowPage(icon: NSApp.applicationIconImage, description: Text(verbatim: AddAppText.description), width: Self.width) {
            if model.hasHelper {
                SectionHeading(Text(verbatim: AddAppText.stepsHeading)).padding(.top, 8)
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(model.steps.enumerated()), id: \.element) { index, step in
                            if index > 0 { CardDivider() }
                            row(step)
                        }
                    }
                }
            } else {
                NoteLabel(AddAppText.helperMissing).padding(.top, 8)
            }
        } bar: {
            // While a check runs, Escape is its Stop (in the check's step).
            // Once the check is done, closing cancels nothing: it's kept.
            Button { close() } label: { Text(verbatim: isDone ? LaterText.title : ButtonText.cancel) }
                .buttonStyle(.chip)
                .keyboardShortcut(model.stage == .checking ? nil : .cancelAction)
            Spacer()
        }
        .announcesCurrentStep(announcement)
        .onChange(of: isWaitingToPlay) { _, waiting in floats(waiting) }
        .defaultFocus($focused, model.currentStep)
        .onChange(of: model.stage, initial: true) { focusCurrentStep() }
        .onChange(of: model.permissions.neededAllowed) { focusCurrentStep() }
    }

    /// The focus leaves the control it's on, then goes to the current step's
    /// main control once it's in place (none while it waits for the app to
    /// play).
    private func focusCurrentStep() {
        focused = nil
        let step = model.currentStep
        Task { @MainActor in focused = step }
    }

    private var appName: String? { model.chosen?.name }

    /// The check is done: its result is kept, whatever closes the window.
    private var isDone: Bool {
        if case .done = model.stage { true } else { false }
    }

    private var isWaitingToPlay: Bool {
        if case .waitingToPlay = model.stage { true } else { false }
    }

    /// What VoiceOver says as the step to do changes, or fails, or warns:
    /// its title, then why.
    private var announcement: String? {
        let step = model.currentStep
        let state = model.state(of: step)
        guard !model.isBusy(step), state == .current || state == .failed else { return nil }
        let why = warning(step, state)
        return why.map { "\(title(step))\n\($0)" } ?? title(step)
    }

    /// The warning or failure a step shows, if any.
    private func warning(_ step: AddAppModel.Step, _ state: StepState) -> String? {
        let app = appName ?? ""
        switch step {
        case .choose: return model.openFailed ? AddAppText.couldNotOpen(app) : nil
        case .allow: return model.accessibilityNeedsReopen ? AddAppText.accessibilityChanged
            : model.permissionMissingInCheck ? AddAppText.neededInCheck : nil
        case .reopen: return model.reopenFailed ? AddAppText.didNotQuit(app) : nil
        case .play:
            guard state == .failed else { return nil }
            return model.appNotFound ? AddAppText.appNotFound(app) : model.appQuit ? AddAppText.appQuit(app) : AddAppText.didNotPlay(app)
        case .check:
            switch model.stage {
            case .stopped: return AddAppText.stoppedNote
            case .failed: return AddAppText.checkFailed(model.failureReason, app: app)
            default: return nil
            }
        case .use: return model.choosableWays.isEmpty ? model.result.map { nothingNote($0, app: app) } : nil
        }
    }

    private func title(_ step: AddAppModel.Step) -> String {
        switch step {
        case .choose: AddAppText.chooseTitle
        case .allow: AddAppText.allowTitle
        case .reopen: ReopenText.title(appName ?? "")
        case .play: AddAppText.playTitle(appName)
        case .check: AddAppText.checkTitle
        case .use: AddAppText.useTitle
        }
    }

    private func row(_ step: AddAppModel.Step) -> some View {
        let state = model.state(of: step), busy = model.isBusy(step)
        return NumberedStepRow(number: model.number(of: step), count: model.steps.count,
                               status: StepStatus(state: state, isBusy: busy), title: title(step)) {
            switch step {
            case .choose: chooseStep(state, busy: busy)
            case .allow: allowStep(state)
            case .reopen: reopenStep(state, busy: busy)
            case .play: playStep(state, busy: busy)
            case .check: checkStep(state, busy: busy)
            case .use: useStep()
            }
        }
    }

    // MARK: - Each step's lines and buttons

    /// Change…: once the check has run, it asks first, in a sheet on this window.
    private func changeApp() {
        guard model.changeAppForgetsCheck else { return model.changeApp() }
        let alert = PlayerAlerts.changeApp(appName ?? "")
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { [model] in if $0 == .alertFirstButtonReturn { model.changeApp() } }
        } else if alert.runModal() == .alertFirstButtonReturn {
            model.changeApp()
        }
    }

    @ViewBuilder private func chooseStep(_ state: StepState, busy: Bool) -> some View {
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

    @ViewBuilder private func allowStep(_ state: StepState) -> some View {
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

    @ViewBuilder private func reopenStep(_ state: StepState, busy: Bool) -> some View {
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

    @ViewBuilder private func playStep(_ state: StepState, busy: Bool) -> some View {
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
            MainButton(ButtonText.open(appName ?? ""), inStep: true) { model.openAppAgain() }
                .focused($focused, equals: .play)
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

    @ViewBuilder private func checkStep(_ state: StepState, busy: Bool) -> some View {
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
    private func nothingNote(_ result: CheckResult, app: String) -> String {
        result.setup == nil ? AddAppText.nothingWorked(app) : AddAppText.nothingInAntiDot(app)
    }

    @ViewBuilder private func useStep() -> some View {
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
                if model.closedWaysMayWork { StepNote(AddAppText.openWindowFirst(app)).padding(.top, 4) }
                FlowingButtons {
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
                }
            } else {
                // Now Playing hidden in the menu bar: once it's shown, its
                // panel can be tried (the user, 2026-10-16); checked with its
                // windows closed: with one open, the ways that didn't work may.
                if model.closedWaysMayWork { StepNote(AddAppText.openWindowFirst(app)).padding(.top, 4) }
                FlowingButtons {
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

// MARK: - The parts

/// A grey line under a step's title.
private struct StepNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(verbatim: text).captionStyle()
    }
}

/// Step 2's permissions: each one the chosen app's check needs, with what
/// it's for and Allow… until it's allowed. In AntiDot mode, Audio Recording
/// isn't used; allowed in System Settings, it waits for AutoHush to reopen.
private struct CheckPermissionRows: View {
    let model: AddAppModel
    let app: String
    /// Accessibility's Allow… is the step's main control while it's missing.
    var focused: FocusState<AddAppModel.Step?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(symbol: "accessibility", title: AddAppText.accessibilityTitle, note: AddAppText.accessibilityUse(app),
                allowed: model.permissions.accessibility, permission: .accessibility)
            if model.antiDot {
                row(symbol: "waveform", title: PermissionText.audioTitle, note: AntiDotText.notNeeded,
                    allowed: nil, permission: .audioRecording)
            } else {
                row(symbol: "waveform", title: PermissionText.audioTitle,
                    note: model.audioAwaitsReopen && model.permissions.audio != .allowed ? AddAppText.audioAllowedAwaitsReopen : AddAppText.audioUse(app),
                    allowed: model.permissions.audio == .allowed, permission: .audioRecording)
            }
            if let automation = model.permissions.automation {
                row(symbol: "music.note", title: AddAppText.automationTitle, note: AddAppText.automationUse,
                    allowed: automation == .allowed, permission: .automation)
            }
        }
    }

    /// `allowed` nil: not used now (no button, nothing to allow).
    private func row(symbol: String, title: String, note: String, allowed: Bool?, permission: CheckPermission) -> some View {
        PermissionRow(symbol: symbol, title: title, note: note, isAllowed: allowed == true) {
            // Accessibility is needed (said while it's missing); the check
            // goes on without the others.
            if permission == .accessibility {
                if allowed == false { HeadingBadge(text: AddAppText.neededBadge) }
            } else if allowed != nil {
                Text(verbatim: AddAppText.optionalLabel).font(.appCaption).foregroundStyle(.appSecondary)
            }
        } trailing: {
            if allowed == false {
                if permission == .audioRecording, model.audioAwaitsReopen {
                    Button { model.reopenAutoHush() } label: { Text(verbatim: PermissionText.reopen) }
                        .buttonStyle(.chip)
                        .fixedSize()
                } else {
                    let allow = Button { model.request(permission) } label: { Text(verbatim: ButtonText.allow) }
                        .buttonStyle(.chip)
                        .fixedSize()
                        .accessibilityLabel(Text(verbatim: AddAppText.allowLabel(title)))
                    if permission == .accessibility { allow.focused(focused, equals: .allow) } else { allow }
                }
            }
        }
    }
}

/// The ways the check tried, each with how it did (C5).
private struct WaysList: View {
    let result: CheckResult
    let app: String
    /// The panel's row shows no state: only its sound tells (in AntiDot
    /// mode, why nothing can be used).
    var panelNeedsSound = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(result.ways, id: \.kind) { way in
                WayRow(way: way, app: app, windowsClosed: result.windowsClosed, soundOnly: way.kind == .panel && way.worked && panelNeedsSound)
            }
        }
    }
}

/// A way the check tried: its mark, its name (with a badge), and how it did.
private struct WayRow: View {
    let way: CheckResult.WayResult
    let app: String
    /// The check found its windows closed (`CheckResult.windowsClosed`).
    var windowsClosed = false
    var recommended = false
    /// Its Now Playing row doesn't follow the app: only its sound tells.
    var soundOnly = false
    /// Inside a choice card, whose button says it (`WayChoices.card`): not
    /// an element of its own, so "Works" is said once (2026-10-29).
    var inCard = false

    var body: some View {
        if inCard {
            row
        } else {
            // Its own label, not its texts combined: combined, a value of its
            // own would replace their words (STYLE_GUIDE, as checklist steps).
            // Its mark isn't read: a way that worked says so as its value, one
            // that worked in some window states too (its note says where not).
            row.accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: accessibilityWords))
                .accessibilityValue(Text(verbatim: accessibilityValue))
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Self.symbol(way.mark).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                // On their shared baseline: centered, the badge left the row's
                // baseline (which the mark follows) undecided, and macOS 14
                // crashed laying the window out again and again (2026-10-16).
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: WayText.title(way.kind)).fixedSize(horizontal: false, vertical: true)
                    if recommended { HeadingBadge(text: AddAppText.recommendedBadge, accent: true) }
                }
                // A way's exception (it works, but not in every window state)
                // as a warning: the orange triangle, the words in the primary
                // color (O3, the user's pick, 2026-10-27: W4's orange words read
                // at 1.7:1 on the chosen card in light mode), on every such way,
                // chosen or not (N3b, the user's pick, 2026-10-27: the recommended
                // one alone before).
                if way.mark == .some {
                    NoteLabel(AddAppText.wayNote(way, app: app, windowsClosed: windowsClosed), font: .appCaption)
                } else {
                    Text(verbatim: AddAppText.wayNote(way, app: app, windowsClosed: windowsClosed)).captionStyle()
                }
                if soundOnly {
                    Text(verbatim: AddAppText.panelSoundOnly).captionStyle()
                }
            }
        }
    }

    /// What VoiceOver reads of it: its name, its badge, its note and the
    /// panel's caption, as they show.
    var accessibilityWords: String {
        [WayText.title(way.kind), recommended ? AddAppText.recommendedBadge : nil,
         AddAppText.wayNote(way, app: app, windowsClosed: windowsClosed), soundOnly ? AddAppText.panelSoundOnly : nil]
            .compactMap { $0 }.joined(separator: "\n")
    }

    /// Its value: "Works" for a way that worked, else none.
    var accessibilityValue: String { way.worked ? AddAppText.wayWorks : "" }

    @ViewBuilder static func symbol(_ mark: CheckResult.Mark) -> some View {
        switch mark {
        case .works: Image(systemName: "checkmark.circle.fill").foregroundStyle(.appSuccess)
        case .some: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.appWarning)
        case .none, .notThere: Image(systemName: "xmark.circle.fill").foregroundStyle(.appSecondary)
        case .notTried, .notChecked, .noWindow, .noAutomation, .noAccessibility, .menuBarHidden, .toggleOnly:
            Image(systemName: "minus.circle").foregroundStyle(.appSecondary)
        }
    }
}

/// The last step when ways worked (U2, the user's pick, 2026-10-15): each one
/// AutoHush can use as a card to choose, the recommended first and chosen
/// until another is, and under them, dimmed, those that didn't work or can't
/// be used (the panel only its sound tells, in AntiDot mode), with why.
private struct WayChoices: View {
    let model: AddAppModel
    let result: CheckResult
    let app: String

    var body: some View {
        let choosable = model.choosableWays
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(choosable.enumerated()), id: \.element) { index, kind in
                if let way = result.ways.first(where: { $0.kind == kind }) { card(way, recommended: index == 0) }
            }
            ForEach(result.ways.filter { !choosable.contains($0.kind) }, id: \.kind) { way in
                WayRow(way: way, app: app, windowsClosed: result.windowsClosed, soundOnly: soundOnly(way)).opacity(0.6).padding(.horizontal, 9).padding(.top, 2)
            }
        }
    }

    private func card(_ way: CheckResult.WayResult, recommended: Bool) -> some View {
        let isChosen = model.chosenWay == way.kind
        let row = WayRow(way: way, app: app, windowsClosed: result.windowsClosed, recommended: recommended, soundOnly: soundOnly(way), inCard: true)
        return Button { model.choose(way.kind) } label: {
            row
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .chosenOutline(isChosen, outlinedOtherwise: true)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        // The row's words and value, on the button alone: said once.
        .accessibilityLabel(Text(verbatim: row.accessibilityWords))
        .accessibilityValue(Text(verbatim: row.accessibilityValue))
    }

    /// The panel that worked, its row showing no state: only its sound tells.
    private func soundOnly(_ way: CheckResult.WayResult) -> Bool {
        way.kind == .panel && way.worked && model.panelNeedsSound
    }
}
