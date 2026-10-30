import Foundation

/// A web app's pages, read and pressed through Accessibility. Calls block:
/// `SafariWebAppPlayer` makes them on a queue of its own. A protocol, so
/// tests can stand in for it.
package protocol WebPage: Sendable {
    /// Whether AutoHush may use Accessibility; `prompt` shows macOS's request.
    func isTrusted(prompt: Bool) -> Bool
    /// The buttons on the pages in the app's windows, on any Space; `nil`
    /// while it has no window.
    func buttons(pid: pid_t) -> [PageButton]?
    /// Whether the app has a window, on any Space (minimized ones too).
    func hasWindow(pid: pid_t) -> Bool
    /// The button as it is now; `nil` once it's gone (the page reloaded) or
    /// doesn't answer.
    func button(_ handle: ButtonHandle) -> PageButton?
    /// Where the button is; `nil` once it's gone.
    func place(of handle: ButtonHandle) -> ButtonPlace?
    /// Whether it's in sight and among a player's controls, for learning;
    /// `nil` once it's gone.
    func standing(of handle: ButtonHandle) -> ButtonStanding?
    /// Presses it; `false` when that wasn't possible.
    func press(_ handle: ButtonHandle) -> Bool
    /// Whether the app's sound is on: a process it's responsible for (its
    /// WebKit process) has output running.
    func isPlayingSound(pid: pid_t) -> Bool
    /// Whether its page's words are current now: a WebKit page's always; a
    /// Chromium or Flutter page's only while one of its windows can be seen.
    func wordsAreCurrent(pid: pid_t) -> Bool
    /// Turns back off the switch it turned on to show the app's page, now
    /// that the app is no longer the player.
    func release()
    /// The page's word was current and said whether it plays: a Chromium web
    /// app's page counts its browser's other playing pages then, to tell its
    /// own sound from theirs while its word isn't current.
    func noteState(playing: Bool, pid: pid_t)
}

extension WebPage {
    package func wordsAreCurrent(pid: pid_t) -> Bool { true }
    package func noteState(playing: Bool, pid: pid_t) {}
}
