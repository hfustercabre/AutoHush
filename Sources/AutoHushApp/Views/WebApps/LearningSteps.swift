import SwiftUI

// A player AutoHush must first learn to control (a Safari web app: which of
// its buttons plays and pauses it) asks the user to play it and say so
// (It's Playing). AutoHush then pauses it itself. When that doesn't take, the
// step is marked failed, with Try Again and Pause It Yourself; the latter
// adds a step where the user pauses it and says so (It's Paused), within a
// minute.
// The steps show only in a window: the learning window, which asks when the
// player is chosen, or Add a Web App, once it has made the web app. The
// menu's card and Settings → General have a Controls row saying whether
// they're learned, with Learn Controls (or Learn Again once learned): a new
// learning window that starts over (the user may have closed the last one
// halfway). The row's words are `LearnText`'s.

/// What the user does while AutoHush learns, and what AutoHush does, each
/// ticked once done, with a tip and a button under the one to do now.
struct LearningSteps: View {
    let name: String
    let hasPlayed: Bool
    let hasPaused: Bool
    /// A permission is missing: the steps wait, locked, without tips.
    var locked = false
    /// Tells VoiceOver when the next step comes (in the learning window).
    var announces = false
    /// What VoiceOver hears while locked: the permission and why.
    var lockedAnnouncement: String?
    /// Once it plays: when learning starts over without the pause.
    var deadline: Date?
    var note: LearningNote?
    var pauseMode = LearningPauseMode.automatic
    var action: @MainActor (StepButton) -> Void = { _ in }

    var body: some View {
        Group {
            if let deadline, hasPlayed, !hasPaused, !locked, pauseMode.pausesByHand {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    list(remaining: max(0, deadline.timeIntervalSince(context.date)))
                }
            } else {
                list(remaining: nil)
            }
        }
    }

    private func list(remaining: TimeInterval?) -> some View {
        let steps = Self.steps(name: name, hasPlayed: hasPlayed, hasPaused: hasPaused, locked: locked,
                               remaining: remaining, note: note, pauseMode: pauseMode)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(steps, id: \.title) { step($0) }
        }
        .announcesCurrentStep(announces ? (locked ? lockedAnnouncement : steps.currentAnnouncement) : nil,
                              atOnce: announces && locked)
    }

    /// Play, then AutoHush pauses it: the one to do now has its tip, its
    /// button, and the note about the last click. While AutoHush pauses it,
    /// its step spins; when it couldn't, the step is marked failed, with Try
    /// Again and Pause It Yourself, and the latter adds the user's pause
    /// step, which counts down. When the key would have reached another app,
    /// the user's pause step comes at once, saying so. Locked, none is to
    /// do yet.
    static func steps(name: String, hasPlayed: Bool, hasPaused: Bool, locked: Bool,
                      remaining: TimeInterval? = nil, note: LearningNote? = nil,
                      pauseMode: LearningPauseMode = .automatic) -> [ChecklistStep] {
        let mode = locked ? .automatic : pauseMode
        let play: StepState = hasPlayed || mode != .automatic ? .done : locked ? .todo : .current
        let playStep = ChecklistStep(title: LearningText.playStep(name), notes: play == .current ? [LearningText.playTip(name)] : [],
                                     state: play, button: play == .current ? .itsPlaying : nil,
                                     warning: play == .current && note != .nothingChanged ? note?.text(name) : nil)
        let autoPause: ChecklistStep
        switch mode {
        case .automatic:
            autoPause = ChecklistStep(title: LearningText.autoPauseStep, state: hasPaused ? .done : .todo)
        case .trying:
            autoPause = ChecklistStep(title: LearningText.autoPauseStep, notes: [LearningText.autoPauseTip(name)],
                                      state: hasPaused ? .done : .current, isBusy: !hasPaused)
        case .failed:
            autoPause = ChecklistStep(title: LearningText.autoPauseStep, state: .failed, button: .tryAgain,
                                      secondaryButton: .pauseManually, warning: LearningText.autoPauseFailed(name))
        case .byHand:
            autoPause = ChecklistStep(title: LearningText.autoPauseStep, notes: [LearningText.autoPauseFailed(name)], state: .failed)
        case .keyElsewhere:
            autoPause = ChecklistStep(title: LearningText.autoPauseStep, notes: [LearningText.keyElsewhere(name)], state: .failed)
        }
        guard mode.pausesByHand else { return [playStep, autoPause] }
        let handPause = ChecklistStep(title: LearningText.handPauseStep, notes: hasPaused ? [] : [LearningText.pauseTip],
                                      state: hasPaused ? .done : .current, button: hasPaused ? nil : .itsPaused,
                                      warning: !hasPaused && note == .nothingChanged ? note?.text(name) : nil,
                                      countdown: hasPaused ? nil : remaining.map(LearningText.countdown))
        return [playStep, autoPause, handPause]
    }

    private func step(_ step: ChecklistStep) -> some View {
        ChecklistStepRow(step: step, dimmed: step.state == .done || (locked && step.state == .todo),
                         bold: [.current, .failed].contains(step.state), action: action) {
            StepSymbol(step: step, locked: locked)
        }
    }
}
