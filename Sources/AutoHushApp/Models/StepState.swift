import Foundation

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
