import Foundation

/// An app's playback menu, read and pressed through Accessibility: for apps
/// that can't be scripted, this is the only way to control that app, not
/// whichever app macOS considers "now playing". Calls block: `MenuPlayer`
/// makes them on a queue of its own. A protocol, so tests can stand in for it.
package protocol PlaybackMenu: Sendable {
    /// Whether AutoHush may use Accessibility; `prompt` shows macOS's request.
    func isTrusted(prompt: Bool) -> Bool
    /// The Play/Pause item of the app running as `pid`; `nil` when the menu
    /// can't be found.
    func toggle(pid: pid_t) -> MenuToggle?
    /// Presses it; `false` when that wasn't possible.
    func pressToggle(pid: pid_t) -> Bool
}
