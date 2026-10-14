import SwiftUI

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
            String(localized: "AutoHush can’t hear \(name) yet. Play a song, then click It’s Playing again.",
                   comment: "Under the step “Play a song in %@” after “It’s Playing” was clicked while the web app was silent; %@ is the web app")
        case .nothingChanged:
            String(localized: "No button changed in \(name). Make sure it’s paused, then click It’s Paused again.",
                   comment: "Under the step “Pause it yourself” after “It’s Paused” was clicked while nothing had changed on the web app's page; %@ is the web app")
        case .timedOut:
            String(localized: "A minute went by without the pause. Play the song again, then click It’s Playing.",
                   comment: "Under the step “Play a song in %@” once learning went back to it: “It’s Paused” wasn't clicked within a minute")
        case .cantSeePage:
            String(localized: "AutoHush can’t see \(name)’s page. Open its window, or close it and open it again, then click It’s Playing again.",
                   comment: "Under the step “Play a song in %@” when AutoHush couldn't read the web app's page (not running, no window, or a window restored without its buttons' names); %@ is the web app")
        }
    }
}

/// How the pause goes once the song plays: AutoHush tries it itself first.
enum LearningPauseMode: Equatable, Sendable {
    /// AutoHush pauses it itself, once it plays.
    case automatic
    /// AutoHush is pausing it now.
    case trying
    /// AutoHush couldn't: the user picks Try Again or Pause It Manually.
    case failed
    /// The user pauses it and says so, within the minute.
    case byHand
    /// The same, at once: another app is Now Playing, so the Play/Pause key
    /// would have reached that one, and AutoHush didn't press it.
    case keyElsewhere

    /// The user pauses it (`byHand`, `keyElsewhere`).
    var pausesByHand: Bool { self == .byHand || self == .keyElsewhere }
}
