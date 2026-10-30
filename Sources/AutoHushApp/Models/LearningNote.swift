import Foundation

/// Why the user's last click didn't move the learning on, shown under its
/// step until the next one.
enum LearningNote: Equatable, Sendable {
    /// It's Playing, while the web app couldn't be heard.
    case notHeard
    /// It's Paused, while no button had changed since It's Playing.
    case nothingChanged
    /// It's Paused didn't come within `LearningStatus.pauseWait`.
    case timedOut
    /// The web app's page couldn't be read: it isn't running, has no window,
    /// or its window shows its buttons without their words.
    case cantSeePage

    func text(_ name: String) -> String {
        switch self {
        case .notHeard:
            String(localized: "AutoHush can’t hear \(name) yet. Play something, then click It’s Playing again.",
                   comment: "Under the step “Play something in %@” after “It’s Playing” was clicked while the web app was silent; %@ is the web app")
        case .nothingChanged:
            String(localized: "No button changed in \(name). Make sure it’s paused, then click It’s Paused again.",
                   comment: "Under the step “Pause it yourself” after “It’s Paused” was clicked while nothing had changed on the web app's page; %@ is the web app")
        case .timedOut:
            String(localized: "A minute went by without the pause. Play it again, then click It’s Playing.",
                   comment: "Under the step “Play something in %@” once learning went back to it: “It’s Paused” wasn't clicked within a minute")
        case .cantSeePage:
            String(localized: "AutoHush can’t see \(name)’s page. Open its window, or close and reopen it, then click It’s Playing again.",
                   comment: "Under the step “Play something in %@” when AutoHush couldn't read the web app's page (not running, no window, or a window restored without its buttons' names); %@ is the web app")
        }
    }
}
