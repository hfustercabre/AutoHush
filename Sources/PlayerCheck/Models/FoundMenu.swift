import AppKit
import AutoHushKit

/// The app's playback menu, as `playbackMenu` finds it: its title, and its
/// first item, which plays or pauses.
struct FoundMenu {
    let title: String
    let toggle: AXUIElement
    /// Its Previous and Next shortcuts, e.g. `standardArrows` or "⇧← ⇧→".
    let arrows: String
    /// The Previous and Next that AutoHush finds a playback menu by first (`playbackMenu`).
    static let standardArrows = "⌘← ⌘→"
    var toggleTitle: String { toggle.title }
    var toggleEnabled: Bool { toggle.value(kAXEnabledAttribute) as? Bool ?? false }
}
