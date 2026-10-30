import Foundation

/// One of a page's buttons, the same between looks while the page isn't
/// reloaded. Holds the button's Accessibility element; a number in tests.
package struct ButtonHandle: Hashable, @unchecked Sendable {
    let element: AnyHashable

    package init(_ element: AnyHashable) {
        self.element = element
    }
}

/// A button as one look at a page found it.
package struct PageButton: Equatable, Sendable {
    package let handle: ButtonHandle
    /// What it says to VoiceOver, e.g. "Pause" or "Play Discover Weekly", in
    /// the site's language.
    package let label: String
    let isEnabled: Bool

    package init(handle: ButtonHandle, label: String, isEnabled: Bool = true) {
        self.handle = handle
        self.label = label
        self.isEnabled = isEnabled
    }
}

/// What learning weighs about a button whose words changed, besides its
/// place. A player's bar is in sight, among the player's other controls; a
/// song's own button (a tile, a row) can be scrolled out of sight and has
/// none around it (measured on SoundCloud and YouTube Music).
package struct ButtonStanding: Equatable, Sendable {
    /// Inside its window: not scrolled below or above it.
    let isInWindow: Bool
    /// Something just around it holds a slider or a progress bar, as a
    /// player's bar does (its progress, its volume).
    package let isWithPlayerControls: Bool

    init(isInWindow: Bool = true, isWithPlayerControls: Bool = false) {
        self.isInWindow = isInWindow
        self.isWithPlayerControls = isWithPlayerControls
    }
}

/// Where a button is on its page, to find it again after a reload, when
/// every element is new.
package struct ButtonPlace: Codable, Equatable, Sendable {
    /// The kinds of element around it, its parent first, up to the page:
    /// e.g. "AXGroup", "AXToolbar", "AXGroup:AXLandmarkComplementary". Never
    /// their names, which are in the site's language and can change.
    package let path: [String]
    /// Points from its middle to the bottom of its window: players keep
    /// their controls at the bottom.
    package let distanceFromBottom: Double

    package init(path: [String], distanceFromBottom: Double) {
        self.path = path
        self.distanceFromBottom = distanceFromBottom
    }
}
