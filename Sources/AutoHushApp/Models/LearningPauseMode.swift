import SwiftUI

/// How the pause goes once it plays: AutoHush tries it itself first.
enum LearningPauseMode: Equatable, Sendable {
    /// AutoHush pauses it itself, once it plays.
    case automatic
    /// AutoHush is pausing it now.
    case trying
    /// AutoHush couldn't: the user picks Try Again or Pause It Yourself.
    case failed
    /// The user pauses it and says so, within the minute.
    case byHand
    /// The same, at once: another app is Now Playing, so the Play/Pause key
    /// would have reached that one, and AutoHush didn't press it.
    case keyElsewhere

    /// The user pauses it (`byHand`, `keyElsewhere`).
    var pausesByHand: Bool { self == .byHand || self == .keyElsewhere }
}
