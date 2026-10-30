import Foundation

/// A step as a checklist shows it: its words, the lines under them, and
/// where it stands.
struct ChecklistStep: Equatable {
    let title: String
    var notes: [String] = []
    let state: StepState
    /// What the user clicks while it's the one to do (blue), and another way
    /// on beside it (grey).
    var button: StepButton?
    var secondaryButton: StepButton?
    /// Why the last try didn't go on, under the lines (a `NoteLabel`).
    var warning: String?
    /// How long is left to do it, as a sentence: a tinted line that stands
    /// out (`CountdownBanner`).
    var countdown: String?
    /// AutoHush is doing it now: a spinner instead of its circle.
    var isBusy = false
    /// Where it stands, as the mark beside it shows it.
    var status: StepStatus { StepStatus(state: state, isBusy: isBusy) }
    /// What VoiceOver says once it's the step to do now: its title, unless
    /// the step goes on in another way (“Now pause it.”).
    var announcement: String?
}

extension [ChecklistStep] {
    /// What VoiceOver says about the step to do now (or, with none, the one
    /// that failed, which offers what to do next), then its warning: a
    /// warning that appears under the same step (AutoHush can't hear it,
    /// say) changes it, so it's said too. `nil` when there's none.
    var currentAnnouncement: String? {
        currentStep.map { step in
            [step.announcement ?? step.title, step.warning].compactMap { $0 }.joined(separator: "\n")
        }
    }

    /// The title of the step to do now (or the one that failed): VoiceOver's
    /// cursor goes to it as it changes.
    var currentTitle: String? { currentStep?.title }

    private var currentStep: ChecklistStep? {
        first { $0.state == .current } ?? first { $0.state == .failed }
    }
}
