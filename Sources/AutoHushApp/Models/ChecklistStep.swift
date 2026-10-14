import SwiftUI

/// Where a step of a window's checklist stands (adding a web app, learning
/// its controls). The check, arrow, circle or cross beside it shows that on
/// screen; VoiceOver reads it after the step's words.
enum StepState: Equatable {
    case done, current, todo
    /// AutoHush tried it and couldn't (pausing a web app itself).
    case failed

    var voiceOverValue: String {
        switch self {
        case .done:
            String(localized: "Completed",
                   comment: "VoiceOver, after a step of a checklist (adding a web app, learning its controls): the step is done")
        case .current:
            String(localized: "In progress",
                   comment: "VoiceOver, after a step of a checklist (adding a web app, learning its controls): the step to do now")
        case .todo:
            String(localized: "To do",
                   comment: "VoiceOver, after a step of a checklist (adding a web app, learning its controls): a step still to come")
        case .failed:
            String(localized: "Failed",
                   comment: "VoiceOver, after a step of a checklist (learning a web app's controls): AutoHush tried the step and couldn't do it")
        }
    }
}

/// What the user clicks in a checklist step while it's the one to do, to say
/// it's done (learning: the song plays, it's paused) or to go on (adding).
enum StepButton: Equatable, Sendable {
    case itsPlaying, itsPaused, addToDock
    /// AutoHush couldn't pause the web app itself: it tries again, or the
    /// user pauses it.
    case tryAgain, pauseManually

    var title: String {
        switch self {
        case .itsPlaying:
            String(localized: "It’s Playing",
                   comment: "Button under the step “Play something in %@” while AutoHush learns a web app's controls: what the user chose plays now, not an ad")
        case .itsPaused:
            String(localized: "It’s Paused",
                   comment: "Button under the step “Pause it yourself” while AutoHush learns a web app's controls: the user has paused it")
        case .tryAgain:
            String(localized: "Try Again",
                   comment: "Button under the step “Let AutoHush pause it” once AutoHush couldn't pause the web app itself: it tries again")
        case .pauseManually:
            String(localized: "Pause It Manually",
                   comment: "Button under the step “Let AutoHush pause it” once AutoHush couldn't pause the web app itself: the user pauses it instead (a step “Pause it yourself” follows)")
        case .addToDock:
            String(localized: "Add to Dock",
                   comment: "Add a Web App window, under the step “Add it to the Dock”: adds the website shown in Safari as a web app (Safari's own menu item is called “Add to Dock…”)")
        }
    }
}

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
    /// What VoiceOver says once it's the step to do now: its title, unless
    /// the step goes on in another way (“Now pause it.”).
    var announcement: String?
}

extension [ChecklistStep] {
    /// What VoiceOver says about the step to do now (or, with none, the one
    /// that failed, which offers what to do next); `nil` when there's none.
    var currentAnnouncement: String? {
        (first { $0.state == .current } ?? first { $0.state == .failed }).map { $0.announcement ?? $0.title }
    }
}
