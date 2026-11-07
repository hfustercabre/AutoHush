import Foundation

/// The Controls row of a player AutoHush must learn to control (the menu's
/// card, Settings → General): whether its controls are learned, and the way
/// to learn them in a new learning window, which Diagnostics offers too.
enum LearnText {
    /// The row's title, and Media Player's row to the player's controls
    /// in Fine-Tuning (`BackupText.controls`).
    static var controlsTitle: String {
        String(localized: "Controls",
               comment: "The menu's card and Settings → General: title of the row about the chosen web app's controls (its Play/Pause button), under the media player; Settings → Media Player: title of the row that shows the chosen player's controls in Fine-Tuning, with what they're set to")
    }

    /// Under the row's title, until they're learned.
    static func notLearnedNote(_ name: String) -> String {
        String(localized: "Not learned yet: AutoHush can’t pause \(name) until it has.",
               comment: "The menu's card and Settings → General, under “Controls”, while AutoHush hasn't learned the web app's Play/Pause button (the learning window was closed); “Learn Controls…” follows; %@ is the web app's name")
    }

    /// Under the row's title, once they're learned.
    static var learnedNote: String {
        String(localized: "Learned. Learn them again if AutoHush gets them wrong.",
               comment: "The menu's card and Settings → General, under “Controls”: the web app's controls (its Play/Pause button) are learned, and what to do if AutoHush gets them wrong; “Learn Again…” follows")
    }

    /// The row's button, until they're learned, and the chip under the
    /// status line that says so (`AppStatus.controlsNotLearned`), and
    /// under Fine-Tuning's "Controls not learned" (`PlayerControlsCard`).
    static var learnButton: String {
        String(localized: "Learn Controls…",
               comment: "The menu's card and Settings → General, in the “Controls” row while the web app's controls aren't learned yet, or under the status line “Controls not learned” (also in Settings → Fine-Tuning's player card), and Settings → Diagnostics beside “Play/Pause button learned: No”: button that opens the window that learns them, from the first step. Keep it short: the row's title already says “Controls”, so “Learn” alone is fine")
    }

    /// The row's button, once they're learned.
    static var learnAgainButton: String {
        String(localized: "Learn Again…",
               comment: "The menu's card and Settings → General, in the “Controls” row once the web app's controls are learned: button that learns them again in a new window (also in the alert that says why the web app couldn't be paused or controlled); what was learned keeps working until the user clicks “It’s Playing” there")
    }
}
