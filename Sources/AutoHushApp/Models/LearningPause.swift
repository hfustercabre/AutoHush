import Foundation

/// Where the pause stands while the user teaches AutoHush a web app's
/// controls, for the windows that show the steps.
struct LearningPause: Equatable {
    /// Once the user said it plays and is to pause it: when learning starts
    /// over without the pause.
    var deadline: Date?
    /// Why the user's last click didn't move it on.
    var note: LearningNote?
    /// Once the user said it plays: AutoHush pauses it itself, to learn which
    /// button changes, or, when it couldn't, the user does.
    var mode = LearningPauseMode.automatic
}
