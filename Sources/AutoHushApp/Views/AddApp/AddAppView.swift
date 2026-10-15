import AppKit
import SwiftUI
import AutoHushKit
import CheckedPlayers

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
    /// While AutoHush waits for the app to play, the window floats in the
    /// top-right corner, above the app the user goes into (`true`), and
    /// stays where it is after (`false`).
    var floats: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                WindowHeader(icon: NSApp.applicationIconImage, description: Text(verbatim: AddAppText.description))
                if model.services.hasHelper {
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
            }
            .windowMargins()
            BottomBar(margin: HostedWindowController.margin) {
                // While a check runs, Escape is its Stop (in the check's step).
                Button { close() } label: { Text(verbatim: AddAppText.cancel) }
                    .buttonStyle(.chip)
                    .keyboardShortcut(model.stage == .checking ? nil : .cancelAction)
                Spacer()
            }
        }
        .frame(width: 460)
        .font(.appBody)
        .announcesCurrentStep(announcement)
        .onChange(of: isWaitingToPlay) { _, waiting in floats(waiting) }
    }

    private var appName: String? { model.chosen?.name }

    private var isWaitingToPlay: Bool {
        if case .waitingToPlay = model.stage { true } else { false }
    }

    /// What VoiceOver says as the step to do changes, or fails, or warns:
    /// its title, then why.
    private var announcement: String? {
        let step = model.currentStep
        let mark = model.mark(of: step)
        guard mark == .current || mark == .failed else { return nil }
        let why = warning(step, mark)
        return why.map { "\(title(step))\n\($0)" } ?? title(step)
    }

    /// The warning or failure a step shows, if any.
    private func warning(_ step: AddAppModel.Step, _ mark: AddAppModel.Mark) -> String? {
        let app = appName ?? ""
        switch step {
        case .choose: return model.openFailed ? AddAppText.couldNotOpen(app) : nil
        case .allow: return model.permissionMissingInCheck ? AddAppText.neededInCheck : nil
        case .reopen: return model.reopenFailed ? AddAppText.didNotQuit(app) : nil
        case .play: return mark == .failed ? (model.appQuit ? AddAppText.appQuit(app) : AddAppText.didNotPlay(app)) : nil
        case .check:
            switch model.stage {
            case .stopped: return AddAppText.stoppedNote
            case .failed: return AddAppText.checkFailed(model.failureReason, app: app)
            default: return nil
            }
        case .use: return model.result?.setup == nil ? model.result.map { _ in AddAppText.nothingWorked(app) } : nil
        }
    }

    private func title(_ step: AddAppModel.Step) -> String {
        switch step {
        case .choose: AddAppText.chooseTitle
        case .allow: AddAppText.allowTitle
        case .reopen: AddAppText.reopenTitle(appName ?? "")
        case .play: AddAppText.playTitle(appName)
        case .check: AddAppText.checkTitle
        case .use: AddAppText.useTitle
        }
    }

    private func row(_ step: AddAppModel.Step) -> some View {
        let mark = model.mark(of: step)
        return NumberedStepRow(number: model.number(of: step), count: model.steps.count, mark: mark, title: title(step)) {
            switch step {
            case .choose: chooseStep(mark)
            case .allow: allowStep(mark)
            case .reopen: reopenStep(mark)
            case .play: playStep(mark)
            case .check: checkStep(mark)
            case .use: useStep()
            }
        }
    }

    // MARK: - Each step's lines and buttons

    @ViewBuilder private func chooseStep(_ mark: AddAppModel.Mark) -> some View {
        switch mark {
        case .done:
            StepNote(AddAppText.chosen(appName ?? "", traits: model.traits, browser: model.chosen?.browserName))
            if model.canChangeApp {
                Button { model.changeApp() } label: { Text(verbatim: AddAppText.changeApp) }
                    .buttonStyle(.chip)
                    .padding(.top, 2)
            }
        case .busy:
            StepNote(AddAppText.opening(appName ?? ""))
        default:
            StepNote(AddAppText.chooseNote)
            if model.openFailed, let app = appName { NoteLabel(AddAppText.couldNotOpen(app)).padding(.top, 2) }
            AddAppStepButton(AddAppText.chooseApp) { model.openChooser() }
        }
    }

    @ViewBuilder private func allowStep(_ mark: AddAppModel.Mark) -> some View {
        switch mark {
        case .todo:
            StepNote(AddAppText.allowNote)
        case .done:
            StepNote(AddAppText.allowedSummary(model.permissions, antiDot: model.antiDot))
        default:
            if let app = appName {
                if model.traits?.scriptable == false { StepNote(AddAppText.notScriptable(app)) }
                if model.permissionMissingInCheck { NoteLabel(AddAppText.neededInCheck).padding(.top, 2) }
                CheckPermissionRows(model: model, app: app).padding(.top, 4)
                // Some not allowed: what the check does without them, then
                // Continue once what's needed is (all allowed goes on by itself).
                let missing = model.permissions.missingOptional(antiDot: model.antiDot)
                if !model.permissions.neededAllowed {
                    NoteLabel(AddAppText.accessibilityNeeded(app)).padding(.top, 4)
                } else if !missing.isEmpty {
                    NoteLabel(AddAppText.withoutWarning(missing, app: app)).padding(.top, 4)
                    AddAppStepButton(AddAppText.continueButton) { model.continueWithoutAll() }
                }
            }
        }
    }

    @ViewBuilder private func reopenStep(_ mark: AddAppModel.Mark) -> some View {
        switch mark {
        case .done:
            StepNote(model.reopenOutcome == .skipped ? AddAppText.notReopened : AddAppText.reopened)
        case .busy:
            StepNote(AddAppText.reopening(appName ?? ""))
        case .current:
            NoteLabel(AddAppText.reopenAlertMessage(appName ?? "")).padding(.top, 2)
            if model.reopenFailed { NoteLabel(AddAppText.didNotQuit(appName ?? "")).padding(.top, 2) }
            StepButtons {
                AddAppStepButton(AddAppText.reopenTitle(appName ?? "")) { model.reopen() }
                AddAppStepButton(AddAppText.skip, secondary: true) { model.skipReopen() }
            }
        default:
            StepNote(AddAppText.reopenPending)
        }
    }

    @ViewBuilder private func playStep(_ mark: AddAppModel.Mark) -> some View {
        switch (mark, model.stage) {
        case (.done, _):
            StepNote(AddAppText.playingNote)
        case (.current, .waitingToPlay(let since)):
            StepNote(AddAppText.playNow(appName ?? ""))
            TimelineView(.periodic(from: .now, by: 1)) { context in
                CountdownBanner(text: AddAppText.timeToPlay(AddAppModel.playWait - context.date.timeIntervalSince(since)))
            }
            .padding(.top, 2)
        case (.failed, _) where model.appQuit:
            NoteLabel(AddAppText.appQuit(appName ?? "")).padding(.top, 2)
            AddAppStepButton(AddAppText.open(appName ?? "")) { model.openAppAgain() }
        case (.failed, _):
            StepNote(AddAppText.didNotPlay(appName ?? ""))
            AddAppStepButton(AddAppText.tryAgain) { model.waitForPlaying() }
        default:
            StepNote(AddAppText.playWaits)
        }
    }

    /// The app is muted during the check: Audio Recording is allowed and
    /// AntiDot mode is off.
    private var mutedInCheck: Bool { model.permissions.audio == .allowed && !model.antiDot }

    @ViewBuilder private func checkStep(_ mark: AddAppModel.Mark) -> some View {
        switch (mark, model.stage) {
        case (.done, _):
            StepNote(AddAppText.putBackNote)
        case (.busy, _):
            StepNote(model.isEndingLastCheck ? AddAppText.lastCheckEnding : AddAppText.stage(model.progress.stage))
            StepNote(AddAppText.stopHint)
            AddAppStepButton(AddAppText.stop, secondary: true, cancels: true) { model.stopCheck() }
        case (.failed, .stopped):
            StepNote(AddAppText.stoppedNote)
            AddAppStepButton(AddAppText.checkAgain) { model.checkAgain() }
        case (.failed, _):
            StepNote(AddAppText.checkFailed(model.failureReason, app: appName ?? ""))
            StepButtons {
                AddAppStepButton(AddAppText.checkAgain) { model.checkAgain() }
                if model.failureReason == .other {
                    AddAppStepButton(AddAppText.showLog, secondary: true) { model.showLog() }
                }
            }
        default:
            if let app = appName, !mutedInCheck {
                StepNote(AddAppText.checkNoteHeard(app))
            } else {
                StepNote(AddAppText.checkNote(appName))
            }
            if model.traits?.framework != nil { StepNote(AddAppText.switchNote) }
            if mark == .current {
                AddAppStepButton(AddAppText.continueToCheck) { model.continueToCheck() }
            }
        }
    }

    @ViewBuilder private func useStep() -> some View {
        if let result = model.result, let app = appName {
            if result.setup == nil {
                StepNote(AddAppText.nothingWorked(app))
            } else {
                StepNote(AddAppText.useOrder)
            }
            WaysList(result: result, app: app).padding(.top, 4)
            if result.setup == nil {
                // No way pauses it: it can be muted instead (the user, 2026-10-15).
                StepNote(AddAppText.muteInstead(app)).padding(.top, 4)
                if model.antiDot {
                    NoteLabel(ControlFailure.muteUnavailable.text(player: app)).padding(.top, 2)
                } else if !model.canMute {
                    if model.audioAwaitsReopen {
                        NoteLabel(AddAppText.audioAfterReopen).padding(.top, 2)
                        Button { model.reopenAutoHush() } label: { Text(verbatim: PermissionText.reopen) }
                            .buttonStyle(.chip)
                    } else {
                        NoteLabel(AddAppText.muteNeedsAudio).padding(.top, 2)
                        Button { model.allowMuting() } label: { Text(verbatim: AddAppText.allowButton) }
                            .buttonStyle(.chip)
                            .accessibilityLabel(Text(verbatim: AddAppText.allowLabel(PermissionText.audioTitle)))
                    }
                }
                StepButtons {
                    AddAppStepButton(AddAppText.muteItInstead) { model.useMuting() }
                        .disabled(!model.canMute)
                    AddAppStepButton(AddAppText.checkAgain, secondary: true) { model.checkAgain() }
                }
            } else {
                AddAppStepButton(AddAppText.use(app)) { model.use() }
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
        Text(verbatim: text).captionStyle().fixedSize(horizontal: false, vertical: true)
    }
}

/// A step's button, as a checklist's (`StepActionButton`): blue, Return
/// pressing it, as a window's main button; grey for the other way on
/// beside it.
private struct AddAppStepButton: View {
    let title: String
    var secondary = false
    /// Escape presses it (the check's Stop).
    var cancels = false
    let action: () -> Void

    init(_ title: String, secondary: Bool = false, cancels: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.secondary = secondary
        self.cancels = cancels
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(verbatim: title).font(secondary ? .appBody : .appBody.weight(.semibold)).padding(.horizontal, 6)
                .fixedSize()
        }
        .buttonStyle(ChipButtonStyle(filled: true, isSelected: !secondary, padded: true))
        .keyboardShortcut(cancels ? .cancelAction : secondary ? nil : .defaultAction)
        .padding(.top, 2)
    }
}

/// Side by side when they fit, else one under the other.
private struct StepButtons<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content }
            VStack(alignment: .leading, spacing: 6) { content }
        }
    }
}

/// Step 2's permissions: each one the chosen app's check needs, with what
/// it's for and Allow… until it's allowed. In AntiDot mode, Audio Recording
/// isn't used; allowed in System Settings, it waits for AutoHush to reopen.
private struct CheckPermissionRows: View {
    let model: AddAppModel
    let app: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(symbol: "accessibility", title: AddAppText.accessibilityTitle, note: AddAppText.accessibilityUse(app),
                allowed: model.permissions.accessibility, permission: .accessibility)
            if model.antiDot {
                row(symbol: "waveform", title: PermissionText.audioTitle, note: AddAppText.audioInAntiDot,
                    allowed: nil, permission: .audioRecording)
            } else {
                row(symbol: "waveform", title: PermissionText.audioTitle,
                    note: model.audioAwaitsReopen && model.permissions.audio != .allowed ? AddAppText.audioAfterReopen : AddAppText.audioUse(app),
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
        HStack(spacing: 10) {
            SymbolTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: title)
                    // Accessibility is needed; the check goes on without the others.
                    if permission == .accessibility {
                        HeadingBadge(text: AddAppText.neededBadge)
                    } else if allowed != nil {
                        Text(verbatim: AddAppText.optionalLabel).font(.appCaption).foregroundStyle(.appSecondary)
                    }
                }
                Text(verbatim: note).captionStyle().fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if allowed == true {
                Label {
                    Text(verbatim: AddAppText.allowedLabel)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.appSuccess)
                }
                .font(.appCallout)
                .foregroundStyle(.appSecondary)
                .fixedSize()
            } else if allowed == false {
                if permission == .audioRecording, model.audioAwaitsReopen {
                    Button { model.reopenAutoHush() } label: { Text(verbatim: PermissionText.reopen) }
                        .buttonStyle(.chip)
                        .fixedSize()
                } else {
                    Button { model.request(permission) } label: { Text(verbatim: AddAppText.allowButton) }
                        .buttonStyle(.chip)
                        .fixedSize()
                        .accessibilityLabel(Text(verbatim: AddAppText.allowLabel(title)))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The ways the check tried, each with how it did (C5).
private struct WaysList: View {
    let result: CheckResult
    let app: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(result.ways, id: \.kind) { way in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    symbol(way.mark).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: AddAppText.wayTitle(way.kind)).fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: AddAppText.wayNote(way, app: app)).captionStyle().fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private func symbol(_ mark: CheckResult.Mark) -> some View {
        switch mark {
        case .works: Image(systemName: "checkmark.circle.fill").foregroundStyle(.appSuccess)
        case .some: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.appWarning)
        case .none, .notThere: Image(systemName: "xmark.circle.fill").foregroundStyle(.appSecondary)
        case .notTried, .notChecked: Image(systemName: "minus.circle").foregroundStyle(.appSecondary)
        }
    }
}
