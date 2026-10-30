import Foundation

/// What the user clicks in a checklist step while it's the one to do, to say
/// it's done (learning: it plays, it's paused) or to go on (adding).
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
            TryAgainText.title
        case .pauseManually:
            String(localized: "Pause It Yourself",
                   comment: "Button under the step “Let AutoHush pause it” once AutoHush couldn't pause the web app itself: the user pauses it instead (a step “Pause it yourself” follows)")
        case .addToDock:
            String(localized: "Add to Dock",
                   comment: "Add a Web App window, under the step “Add it to the Dock”: adds the website shown in Safari as a web app (Safari's own menu item is called “Add to Dock…”)")
        }
    }
}
