import Foundation

/// The Controls row of a player AutoHush must learn to control (the menu's
/// card, Settings → General): whether its controls are learned, and the way
/// to learn them in a new learning window, which Diagnostics offers too.
enum LearnText {
    /// The row's title.
    static var controlsTitle: String {
        String(localized: "Controls",
               comment: "The menu's card and Settings → General: title of the row about the chosen web app's controls (its Play/Pause button), under the media player")
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

    /// The row's button, until they're learned.
    static var learnButton: String {
        String(localized: "Learn Controls…",
               comment: "The menu's card and Settings → General, in the “Controls” row while the web app's controls aren't learned yet, and Settings → Diagnostics beside “Play/Pause button learned: No”: button that opens the window that learns them, from the first step. Keep it short: the row's title already says “Controls”, so “Learn” alone is fine")
    }

    /// The row's button, once they're learned.
    static var learnAgainButton: String {
        String(localized: "Learn Again…",
               comment: "The menu's card and Settings → General, in the “Controls” row once the web app's controls are learned: button that learns them again in a new window; what was learned keeps working until the user clicks “It’s Playing” there")
    }
}
