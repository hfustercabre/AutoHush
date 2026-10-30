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
    @FocusState var focused: AddAppModel.Step?

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

    var appName: String? { model.chosen?.name }

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
            // After Check Again: the wait for a window too, said as it shows.
            if state == .current, isWaitingToPlay, model.windowMissing { return AddAppText.waitsForWindow(app) }
            guard state == .failed else { return nil }
            return model.appNotFound ? AddAppText.appNotFound(app) : model.appQuit ? AddAppText.appQuit(app)
                : model.windowMissing ? AddAppText.noWindowOpened(app) : AddAppText.didNotPlay(app)
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
}
